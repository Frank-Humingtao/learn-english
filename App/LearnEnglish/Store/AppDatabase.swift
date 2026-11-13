import CoreModels
import Foundation
import GRDB

/// The App's local SQLite database (GRDB). Everything the Learner does is written here first.
///
/// Schema changes: append a new `registerMigration` at the end of `migrator`; never edit a
/// shipped migration. Feature-specific queries live in their own `AppDatabase` extensions
/// (one file per feature, e.g. `ObservationStore.swift`).
final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// `Application Support/LearnEnglish/learn-english.sqlite`.
    static func openDefault() throws -> AppDatabase {
        let fm = FileManager.default
        let dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("LearnEnglish", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: dir.appendingPathComponent("learn-english.sqlite").path)
        return try AppDatabase(queue)
    }

    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1-observation") { db in
            // Append-only log of Observations (see GLOSSARY.md); columns mirror the JSONL fields.
            try db.create(table: "observation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("ts", .text).notNull()
                t.column("lemma", .text).notNull()
                t.column("source", .text).notNull()
                t.column("result", .text).notNull()
                t.column("rt_ms", .integer)
                t.column("session", .text)
                t.column("pseudo", .boolean)
                t.column("lexicon", .text)
                /// `ReviewLog` as JSON, review Observations only.
                t.column("review", .text)
            }
            try db.create(index: "observation_on_session", on: "observation", columns: ["session"])
        }
        m.registerMigration("v2-outbox") { db in
            // Ticket 05: Observations not yet committed to english-data. Filled by a trigger so every
            // insert into `observation` is queued; rows that existed before were never synced.
            try db.execute(sql: """
                CREATE TABLE outbox (observation_id INTEGER PRIMARY KEY REFERENCES observation(id));
                INSERT INTO outbox (observation_id) SELECT id FROM observation;
                CREATE TRIGGER observation_into_outbox AFTER INSERT ON observation
                BEGIN INSERT INTO outbox (observation_id) VALUES (NEW.id); END;
                """)
        }
        registerTestCheckpointMigration(&m)
        return m
    }
}
