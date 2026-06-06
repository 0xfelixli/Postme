import Foundation
import SQLite3

final class SQLiteWorkspaceStore {
    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let databaseURL: URL
    private var database: OpaquePointer?

    init(fileManager: FileManager = .default) throws {
        let supportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = supportURL.appendingPathComponent("Postme", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        databaseURL = directoryURL.appendingPathComponent("Postme.sqlite")
        try open()
        try configure()
        try migrate()
    }

    deinit {
        sqlite3_close(database)
    }

    func loadWorkspace() throws -> Workspace? {
        let requests: [APIRequest] = try loadPayloads(
            from: "SELECT payload FROM requests ORDER BY sort_order ASC",
            as: APIRequest.self
        )
        let history: [HistoryEntry] = try loadPayloads(
            from: "SELECT payload FROM history ORDER BY sort_order ASC",
            as: HistoryEntry.self
        )
        let variables: [EnvironmentVariable] = try loadPayloads(
            from: "SELECT payload FROM variables ORDER BY sort_order ASC",
            as: EnvironmentVariable.self
        )

        guard !requests.isEmpty || !history.isEmpty || !variables.isEmpty else {
            return nil
        }

        return Workspace(requests: requests, history: history, variables: variables)
    }

    func saveWorkspace(_ workspace: Workspace) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute("DELETE FROM requests")
            try execute("DELETE FROM history")
            try execute("DELETE FROM variables")

            try insertRequests(workspace.requests)
            try insertHistory(workspace.history)
            try insertVariables(workspace.variables)
            try setMetadataValue("1", forKey: "schema_version")

            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func open() throws {
        let result = sqlite3_open(databaseURL.path, &database)
        guard result == SQLITE_OK else {
            throw SQLiteWorkspaceError.openFailed(lastErrorMessage)
        }
    }

    private func configure() throws {
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS requests (
            id TEXT PRIMARY KEY,
            sort_order INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            payload BLOB NOT NULL
        )
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS history (
            id TEXT PRIMARY KEY,
            sort_order INTEGER NOT NULL,
            sent_at TEXT NOT NULL,
            payload BLOB NOT NULL
        )
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS variables (
            id TEXT PRIMARY KEY,
            sort_order INTEGER NOT NULL,
            payload BLOB NOT NULL
        )
        """)
        try execute("PRAGMA user_version = 1")
    }

    private func insertRequests(_ requests: [APIRequest]) throws {
        let sql = "INSERT INTO requests (id, sort_order, updated_at, payload) VALUES (?, ?, ?, ?)"
        for (index, request) in requests.enumerated() {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            try bindText(request.id.uuidString, to: 1, in: statement)
            try bindInt(index, to: 2, in: statement)
            try bindText(Self.dateFormatter.string(from: request.updatedAt), to: 3, in: statement)
            try bindData(try JSONEncoder.postme.encode(request), to: 4, in: statement)
            try stepDone(statement)
        }
    }

    private func insertHistory(_ history: [HistoryEntry]) throws {
        let sql = "INSERT INTO history (id, sort_order, sent_at, payload) VALUES (?, ?, ?, ?)"
        for (index, entry) in history.enumerated() {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            try bindText(entry.id.uuidString, to: 1, in: statement)
            try bindInt(index, to: 2, in: statement)
            try bindText(Self.dateFormatter.string(from: entry.sentAt), to: 3, in: statement)
            try bindData(try JSONEncoder.postme.encode(entry), to: 4, in: statement)
            try stepDone(statement)
        }
    }

    private func insertVariables(_ variables: [EnvironmentVariable]) throws {
        let sql = "INSERT INTO variables (id, sort_order, payload) VALUES (?, ?, ?)"
        for (index, variable) in variables.enumerated() {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            try bindText(variable.id.uuidString, to: 1, in: statement)
            try bindInt(index, to: 2, in: statement)
            try bindData(try JSONEncoder.postme.encode(variable), to: 3, in: statement)
            try stepDone(statement)
        }
    }

    private func setMetadataValue(_ value: String, forKey key: String) throws {
        let statement = try prepare("INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)")
        defer { sqlite3_finalize(statement) }

        try bindText(key, to: 1, in: statement)
        try bindText(value, to: 2, in: statement)
        try stepDone(statement)
    }

    private func loadPayloads<Value: Decodable>(from sql: String, as type: Value.Type) throws -> [Value] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var values: [Value] = []
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                let byteCount = sqlite3_column_bytes(statement, 0)
                guard let bytes = sqlite3_column_blob(statement, 0) else {
                    values.append(try JSONDecoder.postme.decode(Value.self, from: Data()))
                    continue
                }
                let data = Data(bytes: bytes, count: Int(byteCount))
                values.append(try JSONDecoder.postme.decode(Value.self, from: data))
            case SQLITE_DONE:
                return values
            default:
                throw SQLiteWorkspaceError.stepFailed(lastErrorMessage)
            }
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteWorkspaceError.stepFailed(lastErrorMessage)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteWorkspaceError.prepareFailed(lastErrorMessage)
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteWorkspaceError.stepFailed(lastErrorMessage)
        }
    }

    private func bindText(_ value: String, to index: Int32, in statement: OpaquePointer?) throws {
        let result = sqlite3_bind_text(statement, index, value, -1, Self.transientDestructor)
        guard result == SQLITE_OK else {
            throw SQLiteWorkspaceError.bindFailed(lastErrorMessage)
        }
    }

    private func bindInt(_ value: Int, to index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else {
            throw SQLiteWorkspaceError.bindFailed(lastErrorMessage)
        }
    }

    private func bindData(_ data: Data, to index: Int32, in statement: OpaquePointer?) throws {
        let result = data.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), Self.transientDestructor)
        }
        guard result == SQLITE_OK else {
            throw SQLiteWorkspaceError.bindFailed(lastErrorMessage)
        }
    }

    private var lastErrorMessage: String {
        guard let database else { return "SQLite database is not open." }
        guard let message = sqlite3_errmsg(database) else { return "Unknown SQLite error." }
        return String(cString: message)
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

enum SQLiteWorkspaceError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "Unable to open workspace database: \(message)"
        case .prepareFailed(let message):
            return "Unable to prepare workspace database query: \(message)"
        case .stepFailed(let message):
            return "Unable to update workspace database: \(message)"
        case .bindFailed(let message):
            return "Unable to bind workspace database value: \(message)"
        }
    }
}
