import SwiftUI

@main
struct LearnEnglishApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

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
                    #endif
                    model.sync.startNetworkMonitor()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Back in the foreground: push whatever is waiting (ticket 05).
                    if phase == .active { model.sync.syncSoon() }
                }
        }
    }
}
