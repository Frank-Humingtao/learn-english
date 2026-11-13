import Foundation

/// A Study Plan file as stored in `english-data` (decoded by the caller with `StudyComposer.StudyPlan`).
public struct StudyPlanFile: Sendable, Equatable {
    public var path: String
    public var data: Data
}

extension GitHubClient {
    public static let studyPlanDirectory = "plan"

    /// The newest `plan/YYYY-MM-DD.json` (by the date in its name), or nil when there is none.
    public func latestStudyPlan(_ repo: RepoRef) async throws -> StudyPlanFile? {
        let names = try await listDirectory(repo, path: Self.studyPlanDirectory, ref: repo.branch) ?? []
        guard let newest = names.filter(Self.isStudyPlanName).max() else { return nil }
        let path = "\(Self.studyPlanDirectory)/\(newest)"
        return try await readFile(repo, path: path, ref: repo.branch).map { StudyPlanFile(path: path, data: $0) }
    }

    /// `YYYY-MM-DD.json`.
    static func isStudyPlanName(_ name: String) -> Bool {
        let b = Array(name.utf8)
        guard b.count == 15, name.hasSuffix(".json") else { return false }
        return b.enumerated().prefix(10).allSatisfy { i, c in
            i == 4 || i == 7 ? c == UInt8(ascii: "-") : (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(c)
        }
    }
}
