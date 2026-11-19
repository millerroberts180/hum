import Foundation
import SQLite3

/// A minimal SQLite connection: enough for the history store and no more.
///
/// Not thread-safe on its own. `HistoryStore` owns one and only touches it from
/// inside the actor.
final class SQLiteDatabase {
    enum Failure: Error, Equatable, CustomStringConvertible {
        case open(String)
        case prepare(String, sql: String)
        case step(String)
        case newerSchema(found: Int, supported: Int)

        var description: String {
            switch self {
            case .open(let message): "Couldn't open the database: \(message)"
            case .prepare(let message, let sql): "Couldn't prepare \(sql): \(message)"
            case .step(let message): "A statement failed: \(message)"
            case .newerSchema(let found, let supported):
                "The history file uses schema \(found); this build understands up to \(supported)."
            }
        }
    }

    /// A value to bind to a `?` placeholder.
    enum Value: Equatable {
        case integer(Int64)
        case real(Double)
        case text(String)
        case null

        static func optional(_ text: String?) -> Value { text.map(Value.text) ?? .null }
        static func optional(_ real: Double?) -> Value { real.map(Value.real) ?? .null }
    }

    private var handle: OpaquePointer?

    /// Open the file at `url`, creating it and its folder if needed. `nil` opens a
    /// private in-memory database.
    init(url: URL?) throws {
        let path: String
        if let url {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            path = url.path
        } else {
            path = ":memory:"
        }
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(result)"
            sqlite3_close_v2(handle)
            handle = nil
            throw Failure.open(message)
        }
        sqlite3_busy_timeout(handle, 2_000)
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    var lastInsertedRowID: Int64 { sqlite3_last_insert_rowid(handle) }
    var changes: Int { Int(sqlite3_changes(handle)) }

    /// Run one or more statements that take no parameters and return no rows.
    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(error)
            throw Failure.step(message)
        }
    }

    /// Run a statement with parameters, ignoring any rows.
    func run(_ sql: String, _ values: [Value] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW { result = sqlite3_step(statement) }
        guard result == SQLITE_DONE else { throw Failure.step(errorMessage) }
    }

    /// Run a query and map each row.
    func query<Row>(_ sql: String, _ values: [Value] = [], map: (Cursor) -> Row) throws -> [Row] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var rows: [Row] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            rows.append(map(Cursor(statement: statement)))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw Failure.step(errorMessage) }
        return rows
    }

    /// Run `body` in a transaction, rolling back if it throws.
    func transaction<Result>(_ body: () throws -> Result) throws -> Result {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private var errorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no connection"
    }

    private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure.prepare(errorMessage, sql: sql)
        }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .integer(let number): sqlite3_bind_int64(statement, index, number)
            case .real(let number): sqlite3_bind_double(statement, index, number)
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    /// Tells SQLite to copy bound text, since Swift's buffer is temporary.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Reads columns of the current row.
    struct Cursor {
        fileprivate let statement: OpaquePointer?

        func isNull(_ column: Int32) -> Bool {
            sqlite3_column_type(statement, column) == SQLITE_NULL
        }

        func integer(_ column: Int32) -> Int64 {
            sqlite3_column_int64(statement, column)
        }

        func real(_ column: Int32) -> Double {
            sqlite3_column_double(statement, column)
        }

        func optionalReal(_ column: Int32) -> Double? {
            isNull(column) ? nil : real(column)
        }

        func text(_ column: Int32) -> String {
            guard let pointer = sqlite3_column_text(statement, column) else { return "" }
            return String(cString: pointer)
        }

        func optionalText(_ column: Int32) -> String? {
            isNull(column) ? nil : text(column)
        }
    }
}
