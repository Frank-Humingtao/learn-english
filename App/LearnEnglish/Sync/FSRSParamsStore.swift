import Foundation
import StudyComposer

/// Personal FSRS parameters (ticket 10): the last `fsrs/params.json` read from `english-data`,
/// cached in UserDefaults so scheduling uses it offline and across launches.
///
/// `config` is what card study schedules with: personal weights when the cached file is valid,
/// FSRS-6 defaults otherwise (no file yet, invalid file, never synced).
@MainActor
final class FSRSParamsStore {
    private let defaults: UserDefaults
    private(set) var config: FSRSConfig
    /// The cached file's metadata, nil while on defaults.
    private(set) var params: PersonalFSRSParams?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.key)
        params = data.flatMap(PersonalFSRSParams.decode)
        config = .resolved(paramsFile: data)
    }

    /// Replaces the cache with the file just read from the repo (nil: the repo has none).
    func update(fileData: Data?) {
        if let fileData { defaults.set(fileData, forKey: Self.key) } else { defaults.removeObject(forKey: Self.key) }
        params = fileData.flatMap(PersonalFSRSParams.decode)
        config = .resolved(paramsFile: fileData)
    }

    private static let key = "fsrs.params"
}
