import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var appState = AppState()
    @State private var config: SortSessionConfig?

    var body: some View {
        Group {
            if let config {
                if config.hasCompletedOnboarding {
                    SortingScreen(config: config)
                } else {
                    OnboardingFlowView(config: config)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
        }
        .environment(appState)
        .preferredColorScheme(.dark)
        .task {
            appState.bootstrap(modelContext: modelContext)
            config = appState.configuration(in: modelContext)
        }
    }
}
