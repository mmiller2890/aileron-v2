import AileronCore
import AppKit
import SwiftUI

private enum MarkdownBlock: Identifiable {
    case heading(id: Int, level: Int, text: String)
    case paragraph(id: Int, text: String)
    case bullet(id: Int, text: String)
    case numbered(id: Int, number: String, text: String)
    case code(id: Int, language: String, content: String)
    case divider(id: Int)

    var id: Int {
        switch self {
        case .heading(let id, _, _): return id
        case .paragraph(let id, _): return id
        case .bullet(let id, _): return id
        case .numbered(let id, _, _): return id
        case .code(let id, _, _): return id
        case .divider(let id): return id
        }
    }
}

public struct MarkdownTextView: View {
    @Environment(\.aileronTheme) private var theme
    public let markdown: String
    public let fontSize: CGFloat?
    @State private var pendingExternalURL: URL?

    public init(_ markdown: String, fontSize: CGFloat? = nil) {
        self.markdown = markdown
        self.fontSize = fontSize
    }

    public var body: some View {
        let size = fontSize ?? theme.bodyFontSize
        let blocks = parseBlocks(markdown)
        VStack(alignment: .leading, spacing: 9) {
            ForEach(blocks) { block in
                switch block {
                case .heading(_, let level, let text):
                    inlineMarkdown(text)
                        .font(.system(
                            size: level == 1 ? size + 4 : (level == 2 ? size + 2 : size + 0.5),
                            weight: .semibold
                        ))
                        .foregroundStyle(theme.textPrimary)
                        .padding(.top, 4)

                case .paragraph(_, let text):
                    inlineMarkdown(text)
                        .font(.system(size: size))
                        .foregroundStyle(theme.textPrimary.opacity(0.94))
                        .lineSpacing(4.5)

                case .bullet(_, let text):
                    HStack(alignment: .top, spacing: 9) {
                        Circle()
                            .fill(theme.textTertiary)
                            .frame(width: 4.5, height: 4.5)
                            .padding(.top, 7)
                        inlineMarkdown(text)
                            .font(.system(size: size))
                            .foregroundStyle(theme.textPrimary.opacity(0.94))
                            .lineSpacing(4.5)
                    }

                case .numbered(_, let num, let text):
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(num).")
                            .font(.system(size: size - 0.5, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        inlineMarkdown(text)
                            .font(.system(size: size))
                            .foregroundStyle(theme.textPrimary.opacity(0.94))
                            .lineSpacing(4.5)
                    }

                case .code(_, let lang, let code):
                    CodeBlockCard(language: lang, code: code, fontSize: max(11.5, size - 1))

                case .divider:
                    Divider()
                        .overlay(theme.borderSubtle)
                        .padding(.vertical, 4)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            guard AIClient.isSafeExternalURL(url) else {
                return .discarded
            }
            pendingExternalURL = url
            return .handled
        })
        .alert(
            "Open External Link?",
            isPresented: Binding(
                get: { pendingExternalURL != nil },
                set: { if !$0 { pendingExternalURL = nil } }
            ),
            presenting: pendingExternalURL
        ) { url in
            Button("Open") {
                NSWorkspace.shared.open(url)
                pendingExternalURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingExternalURL = nil
            }
        } message: { url in
            Text("Aileron wants to open:\n\(url.absoluteString)")
        }
    }

    private func inlineMarkdown(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if var attr = try? AttributedString(markdown: text, options: options) {
            for run in attr.runs {
                if let url = run.link, !AIClient.isSafeExternalURL(url) {
                    attr[run.range].link = nil
                }
            }
            return Text(attr)
        }
        return Text(text)
    }

    private func parseBlocks(_ source: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var idCounter = 0
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraphBuffer.removeAll()
            guard !joined.isEmpty else { return }
            result.append(.paragraph(id: idCounter, text: joined))
            idCounter += 1
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                result.append(.code(id: idCounter, language: lang, content: codeLines.joined(separator: "\n")))
                idCounter += 1
                i += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                result.append(.divider(id: idCounter))
                idCounter += 1
                i += 1
                continue
            }

            if trimmed.hasPrefix("### ") {
                flushParagraph()
                result.append(.heading(id: idCounter, level: 3, text: String(trimmed.dropFirst(4))))
                idCounter += 1
                i += 1
                continue
            }
            if trimmed.hasPrefix("## ") {
                flushParagraph()
                result.append(.heading(id: idCounter, level: 2, text: String(trimmed.dropFirst(3))))
                idCounter += 1
                i += 1
                continue
            }
            if trimmed.hasPrefix("# ") {
                flushParagraph()
                result.append(.heading(id: idCounter, level: 1, text: String(trimmed.dropFirst(2))))
                idCounter += 1
                i += 1
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                flushParagraph()
                result.append(.bullet(id: idCounter, text: String(trimmed.dropFirst(2))))
                idCounter += 1
                i += 1
                continue
            }

            if let dotRange = trimmed.range(of: ". "),
               trimmed[..<dotRange.lowerBound].allSatisfy(\.isNumber),
               !trimmed[..<dotRange.lowerBound].isEmpty {
                flushParagraph()
                let num = String(trimmed[..<dotRange.lowerBound])
                let content = String(trimmed[dotRange.upperBound...])
                result.append(.numbered(id: idCounter, number: num, text: content))
                idCounter += 1
                i += 1
                continue
            }

            paragraphBuffer.append(line)
            i += 1
        }
        flushParagraph()
        return result
    }
}

private struct CodeBlockCard: View {
    @Environment(\.aileronTheme) private var theme
    let language: String
    let code: String
    let fontSize: CGFloat
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "Code" : language)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(copied ? theme.live : theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(theme.surfaceElevated.opacity(0.6))
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.borderSubtle).frame(height: 1)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .softCard(background: theme.canvas, radius: 10, border: theme.borderSubtle)
    }
}
