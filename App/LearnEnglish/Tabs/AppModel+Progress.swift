import CoreModels
import Foundation
import Lexicon
import ProfileEngine

/// 进度 tab (ticket 09): profile, test streak, public links.
extension AppModel {
    /// The Learner Profile as the 进度 tab and everything else in the app uses it. The same
    /// computation as `profile-engine profile` in GitHub Actions (reference time = latest
    /// Observation), so both publish identical numbers.
    nonisolated static func computeProfile(observations: [LearnerObservation], lexicon: Lexicon) -> LearnerProfile {
        ProgressPage.report(observations: observations, lexicon: lexicon,
                            now: Date(), calendar: .current).profile
    }

    /// 连续天数 and the latest test day (same rule as the public dashboard).
    var testActivity: StudyActivity {
        ProgressPage.activity(observations: observations, now: Date(), calendar: .current)
    }

    // MARK: public dashboard

    static let publicRepoName = "english-profile"
    private static let ownerKey = "progress.publicOwner"

    /// GitHub owner of `english-profile`: learned from the token by sync, else typed in on the 进度 tab.
    var publicOwner: String? {
        if let o = sync.repoOwner, !o.isEmpty { return o }
        let typed = defaults.string(forKey: Self.ownerKey)?.trimmingCharacters(in: .whitespaces)
        return typed?.isEmpty == false ? typed : nil
    }

    func setPublicOwner(_ owner: String) {
        defaults.set(owner.trimmingCharacters(in: .whitespaces), forKey: Self.ownerKey)
    }

    var publicDashboardURL: URL? {
        publicOwner.flatMap { URL(string: "https://github.com/\($0)/\(Self.publicRepoName)") }
    }

    /// Open issues labelled `progress-report` (only the latest report stays open).
    var progressReportURL: URL? {
        publicOwner.flatMap {
            URL(string: "https://github.com/\($0)/\(Self.publicRepoName)/issues?q=is%3Aissue+is%3Aopen+label%3Aprogress-report")
        }
    }

    #if DEBUG
    /// Simulator hook (`LE_SEED_OBSERVATIONS=<path to .jsonl>`): imports Observations once (DEBUG only).
    func seedObservationsIfRequested() async {
        guard let path = ProcessInfo.processInfo.environment["LE_SEED_OBSERVATIONS"],
              !observations.contains(where: { $0.session == "baseline-1" }),
              let data = FileManager.default.contents(atPath: path) else { return }
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            if let o = try? JSONDecoder().decode(LearnerObservation.self, from: Data(line.utf8)) { try? record(o) }
        }
        await recomputeProfile()
    }

    #endif
}
