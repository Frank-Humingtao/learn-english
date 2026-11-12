// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EnglishCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "CoreModels", targets: ["CoreModels"]),
        .library(name: "Lexicon", targets: ["Lexicon"]),
        .library(name: "ProfileEngine", targets: ["ProfileEngine"]),
        .executable(name: "profile-engine", targets: ["profile-engine"]),
    ],
    targets: [
        // Shared Observation model (no IO beyond Codable).
        .target(name: "CoreModels"),
        // Read-only reference lexicon built by tools/lexicon-build.
        .target(name: "Lexicon"),
        // Pure computation: Observations + Lexicon -> Learner Profile.
        .target(name: "ProfileEngine", dependencies: ["CoreModels", "Lexicon"]),
        // Command-line front end, kept as a library so tests can drive it in-process.
        .target(name: "ProfileEngineCLI", dependencies: ["CoreModels", "Lexicon", "ProfileEngine"]),
        .executableTarget(name: "profile-engine", dependencies: ["ProfileEngineCLI"]),
        .testTarget(name: "ProfileEngineTests", dependencies: ["ProfileEngine", "CoreModels", "Lexicon"]),
        .testTarget(name: "LexiconTests", dependencies: ["Lexicon"]),
        .testTarget(name: "CLITests", dependencies: ["ProfileEngineCLI", "Lexicon"]),
    ]
)
