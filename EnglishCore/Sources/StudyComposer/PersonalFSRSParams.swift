import Foundation

/// Personal FSRS-6 weights trained in `english-data` by GitHub Actions
/// (`english-data-template/scripts/fsrs_train.py`, py-fsrs optimizer) and stored at `fsrs/params.json`:
///
///     {"format": 1, "algorithm": "FSRS-6", "w": [21 floats], "decay": w[20],
///      "review_count": 1227, "trained_at": "2026-11-13T04:00:00Z", "optimizer": "py-fsrs 6.3.2"}
///
/// Only `w` drives scheduling; desired retention and steps stay the App's own settings.
public struct PersonalFSRSParams: Codable, Sendable, Equatable {
    /// Path of the file in the `english-data` repo.
    public static let repoPath = "fsrs/params.json"
    /// File formats this App understands. A newer format falls back to defaults until the App updates.
    public static let supportedFormat = 1

    public var format: Int?
    /// 21 FSRS-6 weights; `w[20]` is the forgetting-curve decay.
    public var weights: [Double]
    public var reviewCount: Int?
    public var trainedAt: String?

    enum CodingKeys: String, CodingKey {
        case format, weights = "w", reviewCount = "review_count", trainedAt = "trained_at"
    }

    /// The file's parameters, or nil when it is unreadable or not usable FSRS-6 weights.
    public static func decode(_ data: Data) -> PersonalFSRSParams? {
        guard let p = try? JSONDecoder().decode(Self.self, from: data), p.isUsable else { return nil }
        return p
    }

    /// 21 finite weights, positive initial stabilities, decay within py-fsrs' bounds [0.1, 0.8].
    var isUsable: Bool {
        guard (format ?? Self.supportedFormat) == Self.supportedFormat, weights.count == 21,
              weights.allSatisfy(\.isFinite), weights.prefix(4).allSatisfy({ $0 > 0 }) else { return false }
        return (0.1...0.8).contains(weights[20])
    }
}

extension FSRSConfig {
    /// The App's scheduling config with personal weights from `fsrs/params.json` when present and
    /// valid; otherwise `base` unchanged (FSRS-6 defaults).
    public static func resolved(paramsFile: Data?, base: FSRSConfig = .default) -> FSRSConfig {
        guard let paramsFile, let params = PersonalFSRSParams.decode(paramsFile) else { return base }
        var config = base
        config.weights = params.weights
        return config
    }
}
