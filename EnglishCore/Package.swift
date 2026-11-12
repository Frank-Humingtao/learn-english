// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EnglishCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "CoreModels", targets: ["CoreModels"]),
        .library(name: "Lexicon", targets: ["Lexicon"]),
        .library(name: "ProfileEngine", targets: ["ProfileEngine"]),
        .library(name: "TestEngine", targets: ["TestEngine"]),
        .library(name: "StudyComposer", targets: ["StudyComposer"]),
        .library(name: "SyncCore", targets: ["SyncCore"]),
        .executable(name: "profile-engine", targets: ["profile-engine"]),
    ],
    dependencies: [
        // FSRS-6 scheduler (MIT). Pinned: the repo publishes tags, not releases.
        .package(url: "https://github.com/open-spaced-repetition/swift-fsrs", exact: "6.0.0"),
    ],
    targets: [
        // Shared Observation model (no IO beyond Codable).
        .target(name: "CoreModels"),
        // Read-only reference lexicon built by tools/lexicon-build.
        .target(name: "Lexicon"),
        // Pure computation: Observations + Lexicon -> Learner Profile.
        .target(name: "ProfileEngine", dependencies: ["CoreModels", "Lexicon"]),
        // Vocabulary Test item selection, pseudowords, meaning checks, result summary. Pure.
        .target(name: "TestEngine", dependencies: ["CoreModels", "Lexicon", "ProfileEngine"]),
        // Card study: FSRS scheduling, card states from review Observations, session composition. Pure.
        .target(name: "StudyComposer", dependencies: ["CoreModels", "Lexicon", "ProfileEngine",
                                                     .product(name: "FSRS", package: "swift-fsrs")]),
        // GitHub client (GraphQL createCommitOnBranch + REST Contents) and outbox sync logic,
        // over an injectable HTTP transport. No third-party Git/GitHub libraries.
        .target(name: "SyncCore", dependencies: ["CoreModels"]),
        // Command-line front end, kept as a library so tests can drive it in-process.
        .target(name: "ProfileEngineCLI", dependencies: ["CoreModels", "Lexicon", "ProfileEngine"]),
        .executableTarget(name: "profile-engine", dependencies: ["ProfileEngineCLI"]),
        .testTarget(name: "ProfileEngineTests", dependencies: ["ProfileEngine", "CoreModels", "Lexicon"]),
        .testTarget(name: "TestEngineTests",
                    dependencies: ["TestEngine", "ProfileEngine", "ProfileEngineCLI", "CoreModels", "Lexicon"]),
        .testTarget(name: "StudyComposerTests",
                    dependencies: ["StudyComposer", "ProfileEngine", "CoreModels", "Lexicon",
                                   .product(name: "FSRS", package: "swift-fsrs")]),
        .testTarget(name: "SyncCoreTests", dependencies: ["SyncCore", "CoreModels"]),
        .testTarget(name: "LexiconTests", dependencies: ["Lexicon"]),
        .testTarget(name: "CLITests", dependencies: ["ProfileEngineCLI", "Lexicon"]),
    ]
)
