import Foundation

extension AileronEngine {
    public func startNewSession() {
        cancelAIResponse()
        let hadContent = !currentSession.turns.isEmpty || !currentSession.exchanges.isEmpty
        if hadContent {
            persistSessionNow()
        }
        currentSession = SessionRecord(
            title: Self.defaultSessionTitle(),
            profileId: settings.activeProfileId
        )
        livePartialText = ""
        livePartialSpeaker = nil
        pendingScreenshot = nil
    }

    public func loadSession(id: UUID) {
        Task {
            guard let database else { return }
            do {
                if let loaded = try await database.loadSession(id: id) {
                    cancelAIResponse()
                    currentSession = loaded
                }
            } catch {
                bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
            }
        }
    }

    public func deleteSession(id: UUID) {
        Task {
            guard let database else { return }
            do {
                try await database.deleteSession(id: id)
                if currentSession.id == id {
                    currentSession = SessionRecord(
                        title: Self.defaultSessionTitle(),
                        profileId: settings.activeProfileId
                    )
                }
                await reloadSessionList()
            } catch {
                bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
            }
        }
    }

    public func renameCurrentSession(_ newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentSession.title = trimmed
        currentSession.updatedAt = Date()
        persistSessionMetadataIncrementally()
    }

    public func renameSpeaker(rawSpeaker: String, alias: String) {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            currentSession.speakerAliases.removeValue(forKey: rawSpeaker)
        } else {
            currentSession.speakerAliases[rawSpeaker] = trimmed
        }
        currentSession.updatedAt = Date()
        persistSessionMetadataIncrementally()
    }

    public func searchSessions(_ query: String) {
        searchQuery = query
        Task {
            await reloadSessionList()
        }
    }

    public func reloadSessionList() async {
        guard let database else { return }
        do {
            sessionList = try await database.listSessions(searchQuery: searchQuery)
        } catch {
            bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
        }
    }

    public func exportCurrentSessionMarkdown() -> String {
        DatabaseStore.exportMarkdown(session: currentSession)
    }

    public func saveProfile(_ profile: PrepProfile) {
        var updated = profile
        updated.updatedAt = Date()
        if let idx = profiles.firstIndex(where: { $0.id == updated.id }) {
            profiles[idx] = updated
        } else {
            profiles.insert(updated, at: 0)
        }
        Task {
            guard let database else { return }
            do {
                try await database.saveProfile(updated)
            } catch {
                bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
            }
        }
    }

    public func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        if settings.activeProfileId == id {
            settings.activeProfileId = profiles.first?.id
            saveSettings()
        }
        Task {
            guard let database else { return }
            do {
                try await database.deleteProfile(id: id)
            } catch {
                bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
            }
        }
    }

    public func selectProfile(id: UUID) {
        settings.activeProfileId = id
        currentSession.profileId = id
        saveSettings()
    }

    internal func persistTurnIncrementally(_ turn: TranscriptTurn) {
        let snapshot = currentSession
        Task {
            guard let database else { return }
            do {
                try await database.appendTurn(turn, in: snapshot)
                await reloadSessionList()
            } catch {
                bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
            }
        }
    }

    internal func persistExchangeIncrementally(_ exchange: AIExchange) {
        let snapshot = currentSession
        Task {
            guard let database else { return }
            do {
                try await database.upsertExchange(exchange, in: snapshot)
                await reloadSessionList()
            } catch {
                bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
            }
        }
    }

    internal func persistSessionMetadataIncrementally() {
        let snapshot = currentSession
        guard !snapshot.turns.isEmpty || !snapshot.exchanges.isEmpty || snapshot.summary != nil else { return }
        Task {
            guard let database else { return }
            do {
                try await database.upsertSessionMetadata(snapshot)
                await reloadSessionList()
            } catch {
                bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
            }
        }
    }

    public func persistSessionNow() {
        let snapshot = currentSession
        guard !snapshot.turns.isEmpty || !snapshot.exchanges.isEmpty || snapshot.summary != nil else { return }
        Task {
            guard let database else { return }
            do {
                try await database.saveSession(snapshot)
                await reloadSessionList()
            } catch {
                bannerNotice = EngineNotice(level: .error, message: error.localizedDescription)
            }
        }
    }
}
