import CoreModels
import Foundation
import GRDB

/// One row of the `observation` table.
struct ObservationRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "observation"

    var id: Int64?
    var ts: String
    var lemma: String
    var source: String
    var result: String
    var rt_ms: Int?
    var session: String?
    var pseudo: Bool?
    var lexicon: String?

    init(_ o: Observation) {
        ts = o.ts
        lemma = o.lemma
        source = o.source.rawValue
        result = o.result
        rt_ms = o.rtMs
        session = o.session
        pseudo = o.pseudo
        lexicon = o.lexicon
    }

    var observation: Observation {
        Observation(ts: ts, lemma: lemma, source: ObservationSource(rawValue: source), result: result, rtMs: rt_ms,
                    session: session, pseudo: pseudo, lexicon: lexicon)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension AppDatabase {
    /// Appends one Observation. Observations are never updated or deleted.
    @discardableResult
    func append(_ observation: Observation) throws -> Int64 {
        try writer.write { db in
            var row = ObservationRow(observation)
            try row.insert(db)
            return row.id!
        }
    }

    /// All Observations in insertion order.
    func allObservations() throws -> [Observation] {
        try writer.read { db in
            try ObservationRow.order(Column("id")).fetchAll(db).map(\.observation)
        }
    }
}
