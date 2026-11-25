import AileronCore
import SwiftUI

public struct PrepProfilesView: View {
    @Environment(\.aileronTheme) private var theme
    @Bindable public var engine: AileronEngine
    @Bindable public var layout: DashboardLayoutState

    @State private var selectedId: UUID?
    @State private var nameDraft: String = ""
    @State private var roleDraft: String = ""
    @State private var promptDraft: String = ""
    @State private var notesDraft: String = ""
    @State private var savedFlash: Bool = false

    private var effectiveSelectedId: UUID? {
        selectedId ?? engine.activeProfile?.id ?? engine.profiles.first?.id
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Rectangle().fill(theme.borderSubtle).frame(height: 1)

            HStack(spacing: 0) {
                if layout.showProfilesList {
                    profileListColumn
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Rectangle().fill(theme.borderSubtle).frame(width: 1)
                }

                editorPane
            }
        }
        .onAppear {
            if let initial = engine.activeProfile ?? engine.profiles.first {
                loadIntoEditor(initial)
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
                    layout.showProfilesList.toggle()
                }
            } label: {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 13))
            }
            .buttonStyle(QuietIconButtonStyle(active: layout.showProfilesList))
            .help("Toggle profiles list")

            Text("Prep Profiles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            if let id = effectiveSelectedId, engine.activeProfile?.id != id {
                Button("Use Profile") {
                    engine.selectProfile(id: id)
                }
                .buttonStyle(SoftButtonStyle(.live, compact: true))
            }

            Button(savedFlash ? "Saved" : "Save") {
                saveCurrentProfile()
            }
            .buttonStyle(SoftButtonStyle(.primary, compact: true))
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var profileListColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Saved Profiles").sectionCaption()
                Spacer()
                Button {
                    createProfile()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(QuietIconButtonStyle())
                .help("New Prep Profile")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(engine.profiles) { profile in
                        let isActive = engine.activeProfile?.id == profile.id
                        let isSelected = effectiveSelectedId == profile.id
                        Button {
                            loadIntoEditor(profile)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(profile.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(theme.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    if isActive {
                                        SoftPill("Active", color: theme.live, fill: theme.liveTint)
                                    }
                                }
                                if !profile.roleContext.isEmpty {
                                    Text(profile.roleContext)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(theme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .softCard(
                                background: isSelected ? theme.surfaceElevated : Color.clear,
                                radius: 9,
                                border: isSelected ? theme.borderMedium : Color.clear
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(width: 245)
        .background(theme.surface.opacity(0.45))
    }

    private var editorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.sectionSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name").sectionCaption()
                    TextField("e.g. Staff Systems Interview", text: $nameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .padding(11)
                        .softCard(background: theme.inputBackground, radius: 10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Role or Meeting Context").sectionCaption()
                    TextField("e.g. Principal Engineer loop — reliability & distributed systems", text: $roleDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: theme.bodyFontSize))
                        .foregroundStyle(theme.textPrimary)
                        .padding(11)
                        .softCard(background: theme.inputBackground, radius: 10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Answering Style").sectionCaption()
                    TextEditor(text: $promptDraft)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: theme.bodyFontSize))
                        .foregroundStyle(theme.textPrimary)
                        .padding(10)
                        .frame(minHeight: 105)
                        .softCard(background: theme.inputBackground, radius: 10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Background Notes, Resume & Talking Points").sectionCaption()
                    Text("Include projects, metrics, or job description details you want Aileron to reference naturally.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                    TextEditor(text: $notesDraft)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: theme.bodyFontSize - 0.5))
                        .foregroundStyle(theme.textPrimary)
                        .padding(10)
                        .frame(minHeight: 200)
                        .softCard(background: theme.inputBackground, radius: 10)
                }

                if engine.profiles.count > 1, let id = effectiveSelectedId {
                    HStack {
                        Spacer()
                        Button("Delete Profile") {
                            engine.deleteProfile(id: id)
                            if let next = engine.profiles.first {
                                loadIntoEditor(next)
                            }
                        }
                        .buttonStyle(SoftButtonStyle(.danger, compact: true))
                    }
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    private func loadIntoEditor(_ profile: PrepProfile) {
        selectedId = profile.id
        nameDraft = profile.name
        roleDraft = profile.roleContext
        promptDraft = profile.systemPrompt
        notesDraft = profile.backgroundNotes
    }

    private func createProfile() {
        let created = PrepProfile(
            name: "New Profile",
            roleContext: "",
            systemPrompt: "Give concise, natural, first-person answers grounded in my notes.",
            backgroundNotes: ""
        )
        engine.saveProfile(created)
        engine.selectProfile(id: created.id)
        loadIntoEditor(created)
    }

    private func saveCurrentProfile() {
        guard let id = effectiveSelectedId else { return }
        let existing = engine.profiles.first { $0.id == id }
        let updated = PrepProfile(
            id: id,
            name: nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Profile" : nameDraft,
            roleContext: roleDraft,
            systemPrompt: promptDraft,
            backgroundNotes: notesDraft,
            createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date()
        )
        engine.saveProfile(updated)
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            savedFlash = false
        }
    }
}
