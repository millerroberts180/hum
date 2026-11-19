import Foundation

/// One step in the history file's schema. Steps run in order, each in its own
/// transaction, and `PRAGMA user_version` records the last one applied.
struct HistoryMigration: Sendable {
    let version: Int
    let apply: @Sendable (SQLiteDatabase) throws -> Void
}

enum HistorySchema {
    static let migrations: [HistoryMigration] = [
        HistoryMigration(version: 1) { database in
            try database.execute("""
                CREATE TABLE plays (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    track_id TEXT NOT NULL,
                    song_key TEXT NOT NULL,
                    title TEXT NOT NULL,
                    artist TEXT NOT NULL,
                    album TEXT NOT NULL,
                    source TEXT NOT NULL,
                    context_kind TEXT,
                    context_name TEXT,
                    context_id TEXT,
                    started_at REAL NOT NULL,
                    ended_at REAL NOT NULL,
                    listened REAL NOT NULL,
                    duration REAL,
                    ending TEXT NOT NULL,
                    counts INTEGER NOT NULL,
                    origin TEXT NOT NULL
                );
                CREATE INDEX plays_by_start ON plays (started_at);
                CREATE INDEX plays_by_song ON plays (song_key, started_at);
                CREATE TABLE pending_listen (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    body TEXT NOT NULL
                );
                CREATE TABLE meta (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
                """)
        },
        // Version 2 changes nothing now. It stays so a file that reached it
        // still opens, and the next change is version 3.
        HistoryMigration(version: 2) { _ in },
    ]

    /// Indexes that only speed things up, made if the file lacks them. They
    /// take no schema version, so an older Hum still opens the file, and
    /// SQLite keeps them current whichever Hum writes.
    static func addIndexes(_ database: SQLiteDatabase) throws {
        // The imported part of history, for its summary and its removal. It
        // holds `origin` too, so the summary never reads the table: macOS 15's
        // SQLite doesn't count a partial index's WHERE column as covered.
        try database.execute("CREATE INDEX IF NOT EXISTS plays_imported ON plays (started_at, ended_at, origin) WHERE origin = 'imported'")
    }

    /// Bring `database` up to the newest version in `migrations`. A file written by a
    /// newer Hum is left untouched.
    static func migrate(_ database: SQLiteDatabase, migrations: [HistoryMigration] = migrations) throws {
        let latest = migrations.map(\.version).max() ?? 0
        let current = try version(of: database)
        guard current <= latest else {
            throw SQLiteDatabase.Failure.newerSchema(found: current, supported: latest)
        }
        for migration in migrations.sorted(by: { $0.version < $1.version }) where migration.version > current {
            try database.transaction {
                try migration.apply(database)
                try database.execute("PRAGMA user_version = \(migration.version)")
            }
        }
    }

    static func version(of database: SQLiteDatabase) throws -> Int {
        try database.query("PRAGMA user_version") { Int($0.integer(0)) }.first ?? 0
    }
}
