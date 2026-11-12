import Foundation
import Lexicon
import Observation
import ProfileEngine

/// The single app-state / dependency container, injected into the view tree with `.environment`.
///
/// Owns the database, the bundled lexicon, the in-memory Observation history and the current
/// Learner Profile. Feature flows (test, study, ...) get what they need from here and report
/// new Observations back through `record(_:)`, the one write path (sync hooks in here later).
@Observable @MainActor
final class AppModel {
    enum Tab: Hashable { case study, test, progress, settings }

    /// A full-screen flow covering the tab bar. Later tickets add cases (study session, baseline...).
    enum Flow: Identifiable {
        case test(TestFlowModel)
        case study(StudyFlowModel)

        var id: ObjectIdentifier {
            switch self {
            case .test(let m): ObjectIdentifier(m)
            case .study(let m): ObjectIdentifier(m)
            }
        }
    }

    var selectedTab: Tab = .study
    var presentedFlow: Flow?

    let database: AppDatabase
    /// Outbox sync to english-data (ticket 05).
    let sync: SyncModel
    /// Newest Study Plan pulled from english-data (ticket 08).
    let plans = PlanStore()
    private(set) var lexicon: Lexicon?
    private(set) var observations: [LearnerObservation] = []
    private(set) var profile: LearnerProfile?
    private(set) var loadError: String?

    init(database: AppDatabase) {
        self.database = database
        sync = SyncModel(database: database)
        plans.attach(to: sync)
    }

    var isLoaded: Bool { lexicon != nil && profile != nil }

    /// Loads the lexicon (off the main actor), the Observation history and the profile.
    func load() async {
        do {
            let observations = try database.allObservations()
            let (lexicon, profile) = try await Task.detached(priority: .userInitiated) {
                guard let dir = Bundle.main.url(forResource: "lexicon", withExtension: nil) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let lexicon = try Lexicon.load(directory: dir)
                return (lexicon, ProfileEngine.compute(observations: observations, lexicon: lexicon))
            }.value
            self.observations = observations
            self.lexicon = lexicon
            self.profile = profile
        } catch {
            loadError = "\(error)"
        }
    }

    /// Stores one Observation locally (SQLite first, then the in-memory history).
    func record(_ observation: LearnerObservation) throws {
        try database.append(observation)
        observations.append(observation)
        sync.refreshCount()
    }

    /// A test or study session ended (result shown or flow closed): push the outbox.
    func sessionEnded() {
        sync.syncSoon()
    }

    /// Replaces the profile after a flow recomputed it (e.g. on the test result screen).
    func update(profile: LearnerProfile) {
        self.profile = profile
    }

    /// Recomputes the profile from all Observations.
    func recomputeProfile() async {
        guard let lexicon else { return }
        let observations = observations
        profile = await Task.detached(priority: .userInitiated) {
            ProfileEngine.compute(observations: observations, lexicon: lexicon)
        }.value
    }

    // MARK: derived

    /// Local calendar day (yyyy-MM-dd) of the latest Vocabulary Test answer.
    var lastTestDay: String? {
        observations.last(where: { [.test, .spotcheck, .verify].contains($0.source) })
            .flatMap { Clock.date(fromISO: $0.ts) }.map(Clock.localDay)
    }

    var testedToday: Bool { lastTestDay == Clock.localDay(Date()) }

    // MARK: flows

    func startTest() {
        guard let lexicon, let profile else { return }
        presentedFlow = .test(TestFlowModel(app: self, lexicon: lexicon, profile: profile))
    }

    func dismissFlow() {
        presentedFlow = nil
        sessionEnded()
    }
}

/// Timestamp helpers. Observations carry UTC ISO 8601 with milliseconds.
enum Clock {
    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func date(fromISO s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    static func localDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Session id: UTC time plus 4 random hex digits, e.g. `20261112T083000Z-3fa9`.
    static func sessionID(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date) + "-" + String(format: "%04x", UInt16.random(in: 0...UInt16.max))
    }
}
