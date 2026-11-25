import AileronCore
import AppKit
import SwiftUI

public struct SessionsLibraryView: View {
    @Environment(\.aileronTheme) private var theme
    @Bindable public var engine: AileronEngine
    @Bindable public var layout: DashboardLayoutState
    public let onOpenInLive: () -> Void
    @State private var searchInput: String = ""

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Rectangle().fill(theme.borderSubtle).frame(height: 1)

            HStack(spacing: 0) {
                if layout.showSessionsList {
                    sessionsListColumn
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Rectangle().fill(theme.borderSubtle).frame(width: 1)
                }

                sessionDocumentView
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if !layout.showNavSidebar {
                Button {
                    layout.toggleNavSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13.5))
                }
                .buttonStyle(QuietIconButtonStyle())
                .padding(.leading, 68)
            }

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    layout.showSessionsList.toggle()
                }
            } label: {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 13))
            }
            .buttonStyle(QuietIconButtonStyle(active: layout.showSessionsList))
            .help("Toggle session list")

            Text("Sessions")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            Button("Open in Live") {
                onOpenInLive()
            }
            .buttonStyle(SoftButtonStyle(.subtle, compact: true))

            Button("Copy Markdown") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(engine.exportCurrentSessionMarkdown(), forType: .string)
            }
            .buttonStyle(SoftButtonStyle(.quiet, compact: true))

            Button {
                engine.deleteSession(id: engine.currentSession.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12.5))
            }
            .buttonStyle(QuietIconButtonStyle(tint: theme.danger))
            .help("Delete session")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var sessionsListColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                TextField("Search sessions…", text: $searchInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textPrimary)
                    .onChange(of: searchInput) { _, newValue in
                        engine.searchSessions(newValue)
                    }
                if !searchInput.isEmpty {
                    Button {
                        searchInput = ""
                        engine.searchSessions("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .softCard(background: theme.inputBackground, radius: 9)
            .padding(12)

            ScrollView {
                LazyVStack(spacing: 6) {
                    if engine.sessionList.isEmpty {
                        Text(searchInput.isEmpty ? "No saved sessions yet." : "No matching sessions.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.top, 24)
                    }
                    ForEach(engine.sessionList) { item in
                        let isSelected = engine.currentSession.id == item.id
                        Button {
                            engine.loadSession(id: item.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(theme.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    if item.hasSummary {
                                        Circle().fill(theme.live).frame(width: 6, height: 6)
                                    }
                                }
                                if !item.preview.isEmpty {
                                    Text(item.preview)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(theme.textSecondary)
                                        .lineLimit(2)
                                }
                                Text("\(item.updatedAt.formatted(date: .abbreviated, time: .shortened)) · \(item.turnCount) turns")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .softCard(
                                background: isSelected ? theme.surfaceElevated : Color.clear,
                                radius: 10,
                                border: isSelected ? theme.borderMedium : Color.clear
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 280)
        .background(theme.surface.opacity(0.45))
    }

    private var sessionDocumentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.sectionSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(engine.currentSession.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("\(engine.currentSession.createdAt.formatted(date: .long, time: .shortened)) · \(engine.currentSession.turns.count) turns · \(engine.currentSession.exchanges.count) answers")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }

                if let summary = engine.currentSession.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Summary").sectionCaption()
                        MarkdownTextView(summary)
                    }
                    .padding(theme.cardPadding)
                    .softCard(background: theme.surface, radius: 14, border: theme.live.opacity(0.3))
                }

                if !engine.currentSession.exchanges.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Answers").sectionCaption()
                        ForEach(engine.currentSession.exchanges) { ex in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(ex.prompt)
                                    .font(.system(size: theme.bodyFontSize, weight: .semibold))
                                    .foregroundStyle(theme.textPrimary)
                                MarkdownTextView(ex.response)
                            }
                            .padding(theme.cardPadding)
                            .softCard(background: theme.surface, radius: 12)
                        }
                    }
                }

                if !engine.currentSession.turns.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Transcript").sectionCaption()
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(engine.currentSession.turns) { turn in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(engine.currentSession.displaySpeaker(for: turn.speaker) ?? "Speaker")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(theme.live)
                                        .frame(width: 86, alignment: .leading)
                                    Text(turn.text)
                                        .font(.system(size: theme.bodyFontSize - 0.5))
                                        .foregroundStyle(theme.textPrimary.opacity(0.92))
                                        .lineSpacing(3.5)
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                            }
                        }
                        .padding(theme.cardPadding)
                        .softCard(background: theme.surface, radius: 12)
                    }
                }

                if engine.currentSession.turns.isEmpty && engine.currentSession.exchanges.isEmpty {
                    Text("Select a saved session on the left, or start a live session to begin recording.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.top, 12)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }
}
