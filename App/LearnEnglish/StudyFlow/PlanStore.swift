import Foundation
import Observation
import StudyComposer
import SyncCore

/// The newest Study Plan pulled from `english-data/plan/` (ticket 08), kept on disk so new cards
/// keep coming offline. Word Planning writes the plans on the Mac; the App only reads them.
@Observable @MainActor
final class PlanStore {
    private(set) var plan: StudyPlan?
    /// `plan/YYYY-MM-DD.json` the plan came from.
    private(set) var path: String?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let defaults: UserDefaults

    init(directory: URL = URL.applicationSupportDirectory, defaults: UserDefaults = .standard) {
        fileURL = directory.appendingPathComponent("study-plan.json")
        self.defaults = defaults
        if let data = try? Data(contentsOf: fileURL), let plan = Self.decode(data) {
            self.plan = plan
            path = defaults.string(forKey: Keys.path)
        }
    }

    /// Every successful sync pulls the newest plan and hands it here.
    func attach(to sync: SyncModel) {
        sync.onStudyPlan = { [weak self] file in self?.apply(file) }
    }

    /// Replaces the plan; a file that does not decode is ignored (the previous plan stays).
    func apply(_ file: StudyPlanFile) {
        guard let decoded = Self.decode(file.data) else { return }
        guard decoded != plan || file.path != path else { return }
        plan = decoded
        path = file.path
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? file.data.write(to: fileURL, options: .atomic)
        defaults.set(file.path, forKey: Keys.path)
    }

    static func decode(_ data: Data) -> StudyPlan? {
        try? JSONDecoder().decode(StudyPlan.self, from: data)
    }

    private enum Keys {
        static let path = "studyPlan.path"
    }
}
