import CoreModels

/// `CoreModels.Observation` under a name that does not clash with the `Observation` module.
///
/// Files that use `@Observable` must NOT `import CoreModels`: the macro expands to
/// `Observation.Observable`, which then resolves to the struct and fails to compile.
/// Such files use `LearnerObservation` instead.
typealias LearnerObservation = CoreModels.Observation
