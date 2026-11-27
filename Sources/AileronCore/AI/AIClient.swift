import Foundation

public enum AIClientError: LocalizedError {
    case invalidBaseURL(String)
    case insecureEndpoint(String)
    case invalidModelName(String)
    case missingAPIKey(String)
    case httpError(statusCode: Int, message: String)
    case invalidResponse
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let url):
            return "Invalid provider endpoint URL: \(url)"
        case .insecureEndpoint(let host):
            return "Blocked insecure HTTP endpoint (\(host)). Use HTTPS for remote hosts or localhost for local servers."
        case .invalidModelName(let name):
            return "Invalid model identifier: \(name)"
        case .missingAPIKey(let provider):
            return "\(provider) requires an API key. Add it securely in Providers (stored in macOS Keychain)."
        case .httpError(let code, let message):
            return "Provider returned HTTP \(code): \(message)"
        case .invalidResponse:
            return "Unexpected response format from AI provider."
        case .responseTooLarge:
            return "AI provider response exceeded the safety size limit."
        }
    }

    public var safeLogSummary: String {
        switch self {
        case .invalidBaseURL:
            return "invalid_base_url"
        case .insecureEndpoint:
            return "insecure_endpoint_blocked"
        case .invalidModelName:
            return "invalid_model_name"
        case .missingAPIKey(let provider):
            return "missing_api_key(\(provider))"
        case .httpError(let code, _):
            return "http_error(\(code))"
        case .invalidResponse:
            return "invalid_response"
        case .responseTooLarge:
            return "response_too_large"
        }
    }
}

private final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public enum AIClient {
    public static let maxStreamBytes = 131_072
    public static let maxDiscoveryBytes = 2_097_152

    private static let redirectDelegate = NoRedirectSessionDelegate()
    private static let secureSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.tlsMinimumSupportedProtocolVersion = .TLSv12
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg, delegate: redirectDelegate, delegateQueue: nil)
    }()

    public static func isLoopbackHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower == "localhost" || lower == "127.0.0.1" || lower == "::1" || lower == "[::1]"
    }

    public static func validatedEndpointURL(baseURL: String, pathSuffix: String) throws -> URL {
        let cleaned = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ \t\n\r"))
        guard !cleaned.isEmpty,
              let components = URLComponents(string: "\(cleaned)\(pathSuffix)"),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else {
            throw AIClientError.invalidBaseURL(baseURL)
        }
        if scheme == "http" && !isLoopbackHost(host) {
            throw AIClientError.insecureEndpoint(host)
        }
        return url
    }

    public static func validatedModelName(_ model: String, provider: AIProviderKind) throws -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 200,
              trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw AIClientError.invalidModelName(model)
        }
        if provider == .gemini {
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
            guard !trimmed.contains(".."),
                  !trimmed.hasPrefix("."),
                  trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                throw AIClientError.invalidModelName(model)
            }
        }
        return trimmed
    }

    public static func streamCompletion(
        provider: AIProviderKind,
        config: ProviderSettings,
        apiKey: String?,
        systemPrompt: String,
        messages: [AIChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if provider.requiresAPIKey && (apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                        throw AIClientError.missingAPIKey(provider.displayName)
                    }
                    let request = try buildRequest(
                        provider: provider,
                        config: config,
                        apiKey: apiKey,
                        systemPrompt: systemPrompt,
                        messages: messages
                    )
                    let (bytes, response) = try await secureSession.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AIClientError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                            if errorBody.count > 400 { break }
                        }
                        throw AIClientError.httpError(
                            statusCode: http.statusCode,
                            message: errorBody.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: http.statusCode) : errorBody
                        )
                    }

                    var streamedBytes = 0
                    for try await rawLine in bytes.lines {
                        if Task.isCancelled { break }
                        if let delta = parseStreamLine(rawLine, provider: provider), !delta.isEmpty {
                            streamedBytes += delta.utf8.count
                            if streamedBytes > maxStreamBytes {
                                continuation.yield("\n\n_[Response truncated at safety limit]_")
                                break
                            }
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public static func parseStreamLine(_ line: String, provider: AIProviderKind) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch provider {
        case .ollama:
            return parseOllamaNDJSONLine(trimmed)
        case .openAI, .lmStudio, .groq, .customOpenAI:
            return parseOpenAISSELine(trimmed)
        case .anthropic:
            return parseAnthropicSSELine(trimmed)
        case .gemini:
            return parseGeminiSSELine(trimmed)
        }
    }

    public static func parseOllamaNDJSONLine(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return nil
        }
        return content
    }

    public static func parseOpenAISSELine(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" || payload.isEmpty { return nil }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String else {
            return nil
        }
        return content
    }

    public static func parseAnthropicSSELine(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "content_block_delta",
              let delta = json["delta"] as? [String: Any],
              let text = delta["text"] as? String else {
            return nil
        }
        return text
    }

    public static func parseGeminiSSELine(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return nil
        }
        let joined = parts.compactMap { $0["text"] as? String }.joined()
        return joined.isEmpty ? nil : joined
    }

    public static func isSafeExternalURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else {
            return false
        }
        return true
    }

    public static func discoverOllamaModels(baseURL: String) async throws -> [String] {
        let url = try validatedEndpointURL(baseURL: baseURL, pathSuffix: "/api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        let (data, response) = try await secureSession.data(for: request)
        guard data.count <= maxDiscoveryBytes else {
            throw AIClientError.responseTooLarge
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIClientError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    public static func warmupOllamaModel(baseURL: String, model: String) async {
        guard let url = try? validatedEndpointURL(baseURL: baseURL, pathSuffix: "/api/chat"),
              let validModel = try? validatedModelName(model, provider: .ollama) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": validModel,
            "messages": [],
            "keep_alive": "10m",
            "stream": false
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await secureSession.data(for: request)
    }

    public static func testConnection(
        provider: AIProviderKind,
        config: ProviderSettings,
        apiKey: String?
    ) async throws -> Int {
        let start = Date()
        var receivedAny = false
        let stream = streamCompletion(
            provider: provider,
            config: config,
            apiKey: apiKey,
            systemPrompt: "Reply with OK.",
            messages: [AIChatMessage(role: .user, text: "Ping")]
        )
        for try await chunk in stream {
            if !chunk.isEmpty {
                receivedAny = true
                break
            }
        }
        if !receivedAny {
            throw AIClientError.invalidResponse
        }
        return Int(Date().timeIntervalSince(start) * 1000)
    }

    private static func buildRequest(
        provider: AIProviderKind,
        config: ProviderSettings,
        apiKey: String?,
        systemPrompt: String,
        messages: [AIChatMessage]
    ) throws -> URLRequest {
        let validModel = try validatedModelName(config.model, provider: provider)
        switch provider {
        case .ollama:
            let url = try validatedEndpointURL(baseURL: config.baseURL, pathSuffix: "/api/chat")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var wireMessages: [[String: Any]] = []
            if !systemPrompt.isEmpty {
                wireMessages.append(["role": "system", "content": systemPrompt])
            }
            for msg in messages {
                var obj: [String: Any] = ["role": msg.role.rawValue, "content": msg.text]
                if let img = msg.imageJPEGData {
                    obj["images"] = [img.base64EncodedString()]
                }
                wireMessages.append(obj)
            }
            let payload: [String: Any] = [
                "model": validModel,
                "messages": wireMessages,
                "stream": true,
                "think": config.enableThinking,
                "keep_alive": "10m",
                "options": ["temperature": config.temperature]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            return request

        case .openAI, .lmStudio, .groq, .customOpenAI:
            let url = try validatedEndpointURL(baseURL: config.baseURL, pathSuffix: "/chat/completions")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
            var wireMessages: [[String: Any]] = []
            if !systemPrompt.isEmpty {
                wireMessages.append(["role": "system", "content": systemPrompt])
            }
            for msg in messages {
                if let img = msg.imageJPEGData, provider.supportsVision {
                    let b64 = img.base64EncodedString()
                    wireMessages.append([
                        "role": msg.role.rawValue,
                        "content": [
                            ["type": "text", "text": msg.text],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]]
                        ]
                    ])
                } else {
                    wireMessages.append(["role": msg.role.rawValue, "content": msg.text])
                }
            }
            let payload: [String: Any] = [
                "model": validModel,
                "messages": wireMessages,
                "temperature": config.temperature,
                "stream": true
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            return request

        case .anthropic:
            let url = try validatedEndpointURL(baseURL: config.baseURL, pathSuffix: "/messages")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                request.setValue(key, forHTTPHeaderField: "x-api-key")
            }
            var wireMessages: [[String: Any]] = []
            for msg in messages where msg.role != .system {
                if let img = msg.imageJPEGData {
                    wireMessages.append([
                        "role": msg.role.rawValue,
                        "content": [
                            [
                                "type": "image",
                                "source": [
                                    "type": "base64",
                                    "media_type": "image/jpeg",
                                    "data": img.base64EncodedString()
                                ]
                            ],
                            ["type": "text", "text": msg.text]
                        ]
                    ])
                } else {
                    wireMessages.append(["role": msg.role.rawValue, "content": msg.text])
                }
            }
            var payload: [String: Any] = [
                "model": validModel,
                "max_tokens": 2048,
                "temperature": config.temperature,
                "stream": true,
                "messages": wireMessages
            ]
            if !systemPrompt.isEmpty {
                payload["system"] = systemPrompt
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            return request

        case .gemini:
            let url = try validatedEndpointURL(
                baseURL: config.baseURL,
                pathSuffix: "/models/\(validModel):streamGenerateContent?alt=sse"
            )
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            }
            var contents: [[String: Any]] = []
            for msg in messages where msg.role != .system {
                let role = msg.role == .assistant ? "model" : "user"
                var parts: [[String: Any]] = [["text": msg.text]]
                if let img = msg.imageJPEGData {
                    parts.append([
                        "inline_data": [
                            "mime_type": "image/jpeg",
                            "data": img.base64EncodedString()
                        ]
                    ])
                }
                contents.append(["role": role, "parts": parts])
            }
            var payload: [String: Any] = [
                "contents": contents,
                "generationConfig": ["temperature": config.temperature]
            ]
            if !systemPrompt.isEmpty {
                payload["system_instruction"] = ["parts": [["text": systemPrompt]]]
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            return request
        }
    }
}
