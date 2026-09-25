import SwiftData
import SwiftUI

@main
struct PhortoApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: DirectionAssignment.self,
                SortSessionConfig.self,
                ProcessedAsset.self,
                DeleteQueueItem.self
            )
        } catch {
            fatalError("SwiftData ModelContainer の初期化に失敗しました: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
