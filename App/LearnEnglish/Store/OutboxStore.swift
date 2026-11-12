import CoreModels
import Foundation
import GRDB
import SyncCore

/// The sync outbox: ids of Observations not yet committed to `english-data`.
/// Rows are added by an SQLite trigger on `observation` insert (migration `v2-outbox`),
/// so every write path feeds the outbox without knowing about sync.
extension AppDatabase {
    func outboxCount() throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox") ?? 0 }
    }

    /// Oldest first.
    func outboxBatch(limit: Int) throws -> [OutboxItem] {
        try writer.read { db in
            try ObservationRow.fetchAll(db, sql: """
                SELECT observation.* FROM observation JOIN outbox ON outbox.observation_id = observation.id
                ORDER BY observation.id LIMIT ?
                """, arguments: [limit])
                .map { OutboxItem(id: $0.id!, observation: $0.observation) }
        }
    }

    func removeFromOutbox(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try writer.write { db in
            let marks = ids.map { _ in "?" }.joined(separator: ",")
            try db.execute(sql: "DELETE FROM outbox WHERE observation_id IN (\(marks))", arguments: StatementArguments(ids))
        }
    }
}
