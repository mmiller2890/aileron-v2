import Foundation

public enum AIClientError: LocalizedError {
    case invalidBaseURL(String)
    case missingAPIKey(String)
    case httpError(statusCode: Int, message: String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let url):
            return "Invalid provider endpoint URL: \(url)"
        case .missingAPIKey(let provider):
            return "\(provider) requires an API key. Add it securely in Providers (stored in macOS Keychain)."
        case .httpError(let code, let message):
            return "Provider returned HTTP \(code): \(message)"
        case .invalidResponse:
            return "Unexpected response format from AI provider."
        }
    }
}

public enum AIClient {
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
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AIClientError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                            if errorBody.count > 600 { break }
                        }
                        throw AIClientError.httpError(
                            statusCode: http.statusCode,
                            message: errorBody.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: http.statusCode) : errorBody
                        )
                    }

                    for try await rawLine in bytes.lines {
                        if Task.isCancelled { break }
                        if let delta = parseStreamLine(rawLine, provider: provider) {
                            if !delta.isEmpty {
                                continuation.yield(delta)
                            }
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

    public static func discoverOllamaModels(baseURL: String) async throws -> [String] {
        let cleaned = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(cleaned)/api/tags") else {
            throw AIClientError.invalidBaseURL(baseURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        let (data, response) = try await URLSession.shared.data(for: request)
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
        let cleaned = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(cleaned)/api/chat"), !model.isEmpty else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": [],
            "keep_alive": "10m",
            "stream": false
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
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
        let cleanedBase = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        switch provider {
        case .ollama:
            guard let url = URL(string: "\(cleanedBase)/api/chat") else {
                throw AIClientError.invalidBaseURL(config.baseURL)
            }
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
                "model": config.model,
                "messages": wireMessages,
                "stream": true,
                "think": config.enableThinking,
                "keep_alive": "10m",
                "options": ["temperature": config.temperature]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            return request

        case .openAI, .lmStudio, .groq, .customOpenAI:
            guard let url = URL(string: "\(cleanedBase)/chat/completions") else {
                throw AIClientError.invalidBaseURL(config.baseURL)
            }
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
                "model": config.model,
                "messages": wireMessages,
                "temperature": config.temperature,
                "stream": true
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            return request

        case .anthropic:
            guard let url = URL(string: "\(cleanedBase)/messages") else {
                throw AIClientError.invalidBaseURL(config.baseURL)
            }
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
                "model": config.model,
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
            let encodedModel = config.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.model
            guard let url = URL(string: "\(cleanedBase)/models/\(encodedModel):streamGenerateContent?alt=sse") else {
                throw AIClientError.invalidBaseURL(config.baseURL)
            }
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
