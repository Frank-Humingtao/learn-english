import SwiftUI

@main
struct LearnEnglishApp: App {
    @State private var model: AppModel

    init() {
        let database: AppDatabase
        do {
            database = try AppDatabase.openDefault()
        } catch {
            fatalError("cannot open the local database: \(error)")
        }
        _model = State(initialValue: AppModel(database: database))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    await model.load()
                    #if DEBUG
                    // Simulator verification hooks (no effect unless the env vars are set).
                    if ProcessInfo.processInfo.environment["LE_TAB"] == "test" { model.selectedTab = .test }
                    if ProcessInfo.processInfo.environment["LE_START_TEST"] != nil { model.startTest() }
                    model.seedReviewsIfRequested()
                    if ProcessInfo.processInfo.environment["LE_START_STUDY"] != nil { model.startStudy() }
                    #endif
                }
        }
    }
}
