import Foundation
import SQLite3

public enum DatabaseError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case executeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "SQLite open failed: \(msg)"
        case .prepareFailed(let msg): return "SQLite prepare failed: \(msg)"
        case .executeFailed(let msg): return "SQLite execution failed: \(msg)"
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class SQLiteConnection: @unchecked Sendable {
    let raw: OpaquePointer

    init(_ raw: OpaquePointer) {
        self.raw = raw
    }

    deinit {
        sqlite3_close(raw)
    }
}

public actor DatabaseStore {
    private let connection: SQLiteConnection
    private var db: OpaquePointer? { connection.raw }

    public init(path: String? = nil) throws {
        let resolvedPath: String
        if let customPath = path {
            resolvedPath = customPath
        } else {
            let dir = SettingsStore.appSupportDirectory()
            resolvedPath = dir.appendingPathComponent("aileron.sqlite").path
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(resolvedPath, &handle, flags, nil)
        guard status == SQLITE_OK, let validHandle = handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            if let handle { sqlite3_close(handle) }
            throw DatabaseError.openFailed(msg)
        }
        self.connection = SQLiteConnection(validHandle)
        try Self.bootstrapSchema(db: validHandle)
        if resolvedPath != ":memory:" {
            for suffix in ["", "-wal", "-shm"] {
                let candidate = URL(fileURLWithPath: resolvedPath + suffix)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    SettingsStore.enforcePrivatePermissions(at: candidate, isDirectory: false)
                }
            }
        }
    }

    private static func bootstrapSchema(db: OpaquePointer) throws {
        let statements = [
            "PRAGMA journal_mode = WAL;",
            "PRAGMA synchronous = NORMAL;",
            "PRAGMA foreign_keys = ON;",
            "PRAGMA busy_timeout = 5000;",
            """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                profile_id TEXT,
                summary TEXT,
                speaker_aliases_json TEXT NOT NULL DEFAULT '{}'
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS turns (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                sequence INTEGER NOT NULL,
                text TEXT NOT NULL,
                speaker TEXT,
                is_question INTEGER NOT NULL DEFAULT 0,
                confidence REAL NOT NULL DEFAULT 1.0,
                duration_seconds REAL NOT NULL DEFAULT 0,
                timestamp REAL NOT NULL,
                source TEXT NOT NULL DEFAULT 'system'
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_turns_session_seq ON turns(session_id, sequence);",
            """
            CREATE TABLE IF NOT EXISTS exchanges (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                prompt TEXT NOT NULL,
                response TEXT NOT NULL,
                provider_name TEXT NOT NULL,
                model_name TEXT NOT NULL,
                has_screenshot INTEGER NOT NULL DEFAULT 0,
                triggered_automatically INTEGER NOT NULL DEFAULT 0,
                latency_ms INTEGER,
                timestamp REAL NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_exchanges_session_ts ON exchanges(session_id, timestamp);",
            """
            CREATE TABLE IF NOT EXISTS prep_profiles (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                role_context TEXT NOT NULL,
                system_prompt TEXT NOT NULL,
                background_notes TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS sessions_fts USING fts5(
                session_id UNINDEXED,
                title,
                summary,
                content
            );
            """
        ]

        for sql in statements {
            try execRaw(db: db, sql: sql)
        }
    }

    private static func execRaw(db: OpaquePointer, sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if status != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errMsg)
            throw DatabaseError.executeFailed(msg)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let db else { throw DatabaseError.openFailed("Database closed") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let valid = stmt else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        return valid
    }

    private func inTransaction(_ body: () throws -> Void) throws {
        guard let db else { throw DatabaseError.openFailed("Database closed") }
        try Self.execRaw(db: db, sql: "BEGIN IMMEDIATE;")
        do {
            try body()
            try Self.execRaw(db: db, sql: "COMMIT;")
        } catch {
            try? Self.execRaw(db: db, sql: "ROLLBACK;")
            throw error
        }
    }

    public func saveSession(_ session: SessionRecord) throws {
        let aliasesData = (try? JSONEncoder().encode(session.speakerAliases)) ?? Data("{}".utf8)
        let aliasesJson = String(data: aliasesData, encoding: .utf8) ?? "{}"

        try inTransaction {
            let upsertSession = try prepare("""
                INSERT INTO sessions (id, title, created_at, updated_at, profile_id, summary, speaker_aliases_json)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    updated_at = excluded.updated_at,
                    profile_id = excluded.profile_id,
                    summary = excluded.summary,
                    speaker_aliases_json = excluded.speaker_aliases_json;
            """)
            defer { sqlite3_finalize(upsertSession) }
            bindText(upsertSession, 1, session.id.uuidString)
            bindText(upsertSession, 2, session.title)
            sqlite3_bind_double(upsertSession, 3, session.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(upsertSession, 4, session.updatedAt.timeIntervalSince1970)
            bindOptionalText(upsertSession, 5, session.profileId?.uuidString)
            bindOptionalText(upsertSession, 6, session.summary)
            bindText(upsertSession, 7, aliasesJson)
            try stepDone(upsertSession)

            let upsertTurn = try prepare("""
                INSERT INTO turns (id, session_id, sequence, text, speaker, is_question, confidence, duration_seconds, timestamp, source)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    sequence = excluded.sequence,
                    text = excluded.text,
                    speaker = excluded.speaker,
                    is_question = excluded.is_question,
                    confidence = excluded.confidence,
                    duration_seconds = excluded.duration_seconds;
            """)
            defer { sqlite3_finalize(upsertTurn) }
            for turn in session.turns {
                sqlite3_reset(upsertTurn)
                sqlite3_clear_bindings(upsertTurn)
                bindText(upsertTurn, 1, turn.id.uuidString)
                bindText(upsertTurn, 2, session.id.uuidString)
                sqlite3_bind_int(upsertTurn, 3, Int32(turn.sequence))
                bindText(upsertTurn, 4, turn.text)
                bindOptionalText(upsertTurn, 5, turn.speaker)
                sqlite3_bind_int(upsertTurn, 6, turn.isQuestion ? 1 : 0)
                sqlite3_bind_double(upsertTurn, 7, Double(turn.confidence))
                sqlite3_bind_double(upsertTurn, 8, turn.durationSeconds)
                sqlite3_bind_double(upsertTurn, 9, turn.timestamp.timeIntervalSince1970)
                bindText(upsertTurn, 10, turn.source.rawValue)
                try stepDone(upsertTurn)
            }

            let upsertExchange = try prepare("""
                INSERT INTO exchanges (id, session_id, prompt, response, provider_name, model_name, has_screenshot, triggered_automatically, latency_ms, timestamp)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    prompt = excluded.prompt,
                    response = excluded.response,
                    provider_name = excluded.provider_name,
                    model_name = excluded.model_name,
                    has_screenshot = excluded.has_screenshot,
                    latency_ms = excluded.latency_ms;
            """)
            defer { sqlite3_finalize(upsertExchange) }
            for exchange in session.exchanges {
                sqlite3_reset(upsertExchange)
                sqlite3_clear_bindings(upsertExchange)
                bindText(upsertExchange, 1, exchange.id.uuidString)
                bindText(upsertExchange, 2, session.id.uuidString)
                bindText(upsertExchange, 3, exchange.prompt)
                bindText(upsertExchange, 4, exchange.response)
                bindText(upsertExchange, 5, exchange.providerName)
                bindText(upsertExchange, 6, exchange.modelName)
                sqlite3_bind_int(upsertExchange, 7, exchange.hasScreenshot ? 1 : 0)
                sqlite3_bind_int(upsertExchange, 8, exchange.triggeredAutomatically ? 1 : 0)
                if let latency = exchange.latencyMs {
                    sqlite3_bind_int(upsertExchange, 9, Int32(latency))
                } else {
                    sqlite3_bind_null(upsertExchange, 9)
                }
                sqlite3_bind_double(upsertExchange, 10, exchange.timestamp.timeIntervalSince1970)
                try stepDone(upsertExchange)
            }

            let deleteFts = try prepare("DELETE FROM sessions_fts WHERE session_id = ?;")
            defer { sqlite3_finalize(deleteFts) }
            bindText(deleteFts, 1, session.id.uuidString)
            try stepDone(deleteFts)

            let combinedContent = (
                session.turns.map(\.text) +
                session.exchanges.flatMap { [$0.prompt, $0.response] }
            ).joined(separator: "\n")

            let insertFts = try prepare("INSERT INTO sessions_fts (session_id, title, summary, content) VALUES (?, ?, ?, ?);")
            defer { sqlite3_finalize(insertFts) }
            bindText(insertFts, 1, session.id.uuidString)
            bindText(insertFts, 2, session.title)
            bindText(insertFts, 3, session.summary ?? "")
            bindText(insertFts, 4, combinedContent)
            try stepDone(insertFts)
        }
    }

    public func loadSession(id: UUID) throws -> SessionRecord? {
        let stmt = try prepare("""
            SELECT id, title, created_at, updated_at, profile_id, summary, speaker_aliases_json
            FROM sessions WHERE id = ?;
        """)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let title = readText(stmt, 1) ?? "Untitled Session"
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        let profileId = readText(stmt, 4).flatMap(UUID.init(uuidString:))
        let summary = readText(stmt, 5)
        let aliasesJson = readText(stmt, 6) ?? "{}"
        let aliases = (try? JSONDecoder().decode([String: String].self, from: Data(aliasesJson.utf8))) ?? [:]

        let turns = try loadTurns(sessionId: id)
        let exchanges = try loadExchanges(sessionId: id)

        return SessionRecord(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            profileId: profileId,
            summary: summary,
            speakerAliases: aliases,
            turns: turns,
            exchanges: exchanges
        )
    }

    public func listSessions(searchQuery: String = "", limit: Int = 100) throws -> [SessionSummaryItem] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let stmt: OpaquePointer
        if trimmed.isEmpty {
            stmt = try prepare("""
                SELECT s.id, s.title, s.created_at, s.updated_at,
                       (SELECT COUNT(*) FROM turns t WHERE t.session_id = s.id) AS turn_count,
                       (SELECT COUNT(*) FROM exchanges e WHERE e.session_id = s.id) AS exchange_count,
                       COALESCE(
                           NULLIF(s.summary, ''),
                           (SELECT t.text FROM turns t WHERE t.session_id = s.id ORDER BY t.sequence DESC LIMIT 1),
                           (SELECT e.prompt FROM exchanges e WHERE e.session_id = s.id ORDER BY e.timestamp DESC LIMIT 1),
                           ''
                       ) AS preview,
                       CASE WHEN s.summary IS NOT NULL AND s.summary != '' THEN 1 ELSE 0 END AS has_summary
                FROM sessions s
                ORDER BY s.updated_at DESC
                LIMIT ?;
            """)
            sqlite3_bind_int(stmt, 1, Int32(limit))
        } else {
            let ftsTokens = trimmed
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .map { "\($0)*" }
                .joined(separator: " ")
            guard !ftsTokens.isEmpty else { return try listSessions(searchQuery: "", limit: limit) }
            stmt = try prepare("""
                SELECT s.id, s.title, s.created_at, s.updated_at,
                       (SELECT COUNT(*) FROM turns t WHERE t.session_id = s.id) AS turn_count,
                       (SELECT COUNT(*) FROM exchanges e WHERE e.session_id = s.id) AS exchange_count,
                       COALESCE(
                           NULLIF(s.summary, ''),
                           (SELECT t.text FROM turns t WHERE t.session_id = s.id ORDER BY t.sequence DESC LIMIT 1),
                           (SELECT e.prompt FROM exchanges e WHERE e.session_id = s.id ORDER BY e.timestamp DESC LIMIT 1),
                           ''
                       ) AS preview,
                       CASE WHEN s.summary IS NOT NULL AND s.summary != '' THEN 1 ELSE 0 END AS has_summary
                FROM sessions s
                INNER JOIN sessions_fts f ON f.session_id = s.id
                WHERE sessions_fts MATCH ?
                ORDER BY s.updated_at DESC
                LIMIT ?;
            """)
            bindText(stmt, 1, ftsTokens)
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }
        defer { sqlite3_finalize(stmt) }

        var items: [SessionSummaryItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = readText(stmt, 0), let uuid = UUID(uuidString: idStr) else { continue }
            items.append(SessionSummaryItem(
                id: uuid,
                title: readText(stmt, 1) ?? "Untitled Session",
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                turnCount: Int(sqlite3_column_int(stmt, 4)),
                exchangeCount: Int(sqlite3_column_int(stmt, 5)),
                preview: readText(stmt, 6) ?? "",
                hasSummary: sqlite3_column_int(stmt, 7) != 0
            ))
        }
        return items
    }

    public func deleteSession(id: UUID) throws {
        try inTransaction {
            let delSession = try prepare("DELETE FROM sessions WHERE id = ?;")
            defer { sqlite3_finalize(delSession) }
            bindText(delSession, 1, id.uuidString)
            try stepDone(delSession)

            let delFts = try prepare("DELETE FROM sessions_fts WHERE session_id = ?;")
            defer { sqlite3_finalize(delFts) }
            bindText(delFts, 1, id.uuidString)
            try stepDone(delFts)
        }
    }

    public func loadProfiles() throws -> [PrepProfile] {
        let stmt = try prepare("""
            SELECT id, name, role_context, system_prompt, background_notes, created_at, updated_at
            FROM prep_profiles
            ORDER BY updated_at DESC;
        """)
        defer { sqlite3_finalize(stmt) }

        var profiles: [PrepProfile] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = readText(stmt, 0), let uuid = UUID(uuidString: idStr) else { continue }
            profiles.append(PrepProfile(
                id: uuid,
                name: readText(stmt, 1) ?? "Profile",
                roleContext: readText(stmt, 2) ?? "",
                systemPrompt: readText(stmt, 3) ?? "",
                backgroundNotes: readText(stmt, 4) ?? "",
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
            ))
        }

        if profiles.isEmpty {
            for seed in PrepProfile.defaultProfiles {
                try saveProfile(seed)
            }
            return PrepProfile.defaultProfiles
        }
        return profiles
    }

    public func saveProfile(_ profile: PrepProfile) throws {
        let stmt = try prepare("""
            INSERT INTO prep_profiles (id, name, role_context, system_prompt, background_notes, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                role_context = excluded.role_context,
                system_prompt = excluded.system_prompt,
                background_notes = excluded.background_notes,
                updated_at = excluded.updated_at;
        """)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, profile.id.uuidString)
        bindText(stmt, 2, profile.name)
        bindText(stmt, 3, profile.roleContext)
        bindText(stmt, 4, profile.systemPrompt)
        bindText(stmt, 5, profile.backgroundNotes)
        sqlite3_bind_double(stmt, 6, profile.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 7, profile.updatedAt.timeIntervalSince1970)
        try stepDone(stmt)
    }

    public func deleteProfile(id: UUID) throws {
        let stmt = try prepare("DELETE FROM prep_profiles WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id.uuidString)
        try stepDone(stmt)
    }

    public static func exportMarkdown(session: SessionRecord) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        var lines: [String] = []
        lines.append("# \(session.title)")
        lines.append("")
        lines.append("- **Date:** \(formatter.string(from: session.createdAt))")
        lines.append("- **Transcript Turns:** \(session.turns.count)")
        lines.append("- **AI Answers:** \(session.exchanges.count)")
        lines.append("")

        if let summary = session.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("## Executive Summary")
            lines.append("")
            lines.append(summary.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }

        if !session.exchanges.isEmpty {
            lines.append("## AI Coaching & Q&A")
            lines.append("")
            for exchange in session.exchanges {
                lines.append("### [\(timeFormatter.string(from: exchange.timestamp))] \(exchange.prompt)")
                lines.append("")
                lines.append(exchange.response.trimmingCharacters(in: .whitespacesAndNewlines))
                lines.append("")
                lines.append("*Model: \(exchange.providerName) / \(exchange.modelName)*")
                lines.append("")
            }
        }

        if !session.turns.isEmpty {
            lines.append("## Transcript")
            lines.append("")
            for turn in session.turns {
                let speakerLabel = session.displaySpeaker(for: turn.speaker) ?? (turn.source == .microphone ? "You" : "Speaker")
                let tag = turn.isQuestion ? " *(Question)*" : ""
                lines.append("- **[\(timeFormatter.string(from: turn.timestamp))] \(speakerLabel)**\(tag): \(turn.text)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func loadTurns(sessionId: UUID) throws -> [TranscriptTurn] {
        let stmt = try prepare("""
            SELECT id, sequence, text, speaker, is_question, confidence, duration_seconds, timestamp, source
            FROM turns WHERE session_id = ? ORDER BY sequence ASC;
        """)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, sessionId.uuidString)

        var turns: [TranscriptTurn] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = readText(stmt, 0), let uuid = UUID(uuidString: idStr) else { continue }
            turns.append(TranscriptTurn(
                id: uuid,
                sequence: Int(sqlite3_column_int(stmt, 1)),
                text: readText(stmt, 2) ?? "",
                speaker: readText(stmt, 3),
                isQuestion: sqlite3_column_int(stmt, 4) != 0,
                confidence: Float(sqlite3_column_double(stmt, 5)),
                durationSeconds: sqlite3_column_double(stmt, 6),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
                source: AudioSourceKind(rawValue: readText(stmt, 8) ?? "system") ?? .system
            ))
        }
        return turns
    }

    private func loadExchanges(sessionId: UUID) throws -> [AIExchange] {
        let stmt = try prepare("""
            SELECT id, prompt, response, provider_name, model_name, has_screenshot, triggered_automatically, latency_ms, timestamp
            FROM exchanges WHERE session_id = ? ORDER BY timestamp ASC;
        """)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, sessionId.uuidString)

        var exchanges: [AIExchange] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = readText(stmt, 0), let uuid = UUID(uuidString: idStr) else { continue }
            let latency: Int? = sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 7))
            exchanges.append(AIExchange(
                id: uuid,
                prompt: readText(stmt, 1) ?? "",
                response: readText(stmt, 2) ?? "",
                providerName: readText(stmt, 3) ?? "",
                modelName: readText(stmt, 4) ?? "",
                hasScreenshot: sqlite3_column_int(stmt, 5) != 0,
                triggeredAutomatically: sqlite3_column_int(stmt, 6) != 0,
                latencyMs: latency,
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
            ))
        }
        return exchanges
    }

    private func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
    }

    private func bindOptionalText(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func readText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    private func stepDone(_ stmt: OpaquePointer) throws {
        let code = sqlite3_step(stmt)
        guard code == SQLITE_DONE else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite error \(code)"
            throw DatabaseError.executeFailed(msg)
        }
    }
}
