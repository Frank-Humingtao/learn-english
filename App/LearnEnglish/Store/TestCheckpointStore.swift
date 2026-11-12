import CoreModels
import Foundation
import GRDB
import TestEngine

/// A resumable Vocabulary Test (the Baseline Test): the `TestSession` as it was created, before
/// any answer. Progress is not stored here; it is the session's Observations in the `observation`
/// table, replayed onto this checkpoint on resume (`TestSession.replay`), so answers are never
/// duplicated or lost.
struct TestCheckpoint: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "test_checkpoint"

    enum Kind: String, Codable { case baseline }

    var session: String
    var kind: Kind
    var created_at: String
    var completed_at: String?
    /// Expected item count, for progress display without decoding `state`.
    var total: Int
    /// JSON-encoded `TestSession`.
    var state: String

    var isCompleted: Bool { completed_at != nil }

    init(session s: TestSession, kind: Kind, createdAt: String) throws {
        session = s.sessionID
        self.kind = kind
        created_at = createdAt
        total = s.progress.total
        state = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
    }

    func testSession() throws -> TestSession {
        try JSONDecoder().decode(TestSession.self, from: Data(state.utf8))
    }
}

extension AppDatabase {
    static func registerTestCheckpointMigration(_ m: inout DatabaseMigrator) {
        m.registerMigration("v2-test-checkpoint") { db in
            try db.create(table: "test_checkpoint") { t in
                t.primaryKey("session", .text)
                t.column("kind", .text).notNull()
                t.column("created_at", .text).notNull()
                t.column("completed_at", .text)
                t.column("total", .integer).notNull()
                t.column("state", .text).notNull()
            }
        }
    }

    func save(_ checkpoint: TestCheckpoint) throws {
        try writer.write { try checkpoint.save($0) }
    }

    /// The most recently started test of `kind` (completed or not).
    func latestCheckpoint(kind: TestCheckpoint.Kind) throws -> TestCheckpoint? {
        try writer.read { db in
            try TestCheckpoint.filter(Column("kind") == kind.rawValue)
                .order(Column("created_at").desc, Column("rowid").desc).fetchOne(db)
        }
    }

    func markCheckpointCompleted(session: String, at ts: String) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE test_checkpoint SET completed_at = ? WHERE session = ?", arguments: [ts, session])
        }
    }
}
