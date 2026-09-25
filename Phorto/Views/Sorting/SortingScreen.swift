import Photos
import SwiftData
import SwiftUI

struct SortingScreen: View {
    let config: SortSessionConfig

    @Environment(AppState.self) private var appState
    @State private var activeDirection: Direction?

    private var viewModel: SortingViewModel? { appState.sortingViewModel }

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            Color.black.ignoresSafeArea()

            if let viewModel {
                content(viewModel)
            }
        }
        .task {
            guard appState.photoService.hasAnyAccess else { return }
            if viewModel?.loadState == .idle {
                await appState.startSession(config: config)
            }
        }
        .sheet(isPresented: $appState.showsSettings) {
            SettingsSheet(config: config)
        }
        .sheet(isPresented: $appState.showsDeleteConfirmation) {
            DeleteConfirmationSheet()
        }
        .sheet(isPresented: $appState.showsPendingDeleteQueue) {
            DeleteConfirmationSheet(isPendingFromPreviousLaunch: true)
        }
        .fullScreenCover(isPresented: isFinished) {
            CompletionView(config: config)
        }
    }

    private var isFinished: Binding<Bool> {
        Binding(
            get: { viewModel?.loadState == .finished },
            set: { _ in }
        )
    }

    @ViewBuilder
    private func content(_ viewModel: SortingViewModel) -> some View {
        @Bindable var bindableViewModel = viewModel

        VStack(spacing: 0) {
            topBar(viewModel)

            cardArea(viewModel)

            BottomControlBar(
                canUndo: viewModel.canUndo,
                onUndo: {
                    HapticsService.undone()
                    viewModel.undo()
                },
                onSkip: { viewModel.skip() },
                onSettings: { appState.showsSettings = true }
            )
        }
        .overlay {
            if !appState.photoService.hasAnyAccess {
                PermissionRequestView()
            } else if viewModel.loadState == .loading {
                loadingOverlay
            }
        }
        .alert(
            "エラー",
            isPresented: Binding(
                get: { bindableViewModel.errorMessage != nil },
                set: { if !$0 { bindableViewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { bindableViewModel.errorMessage = nil }
        } message: {
            Text(bindableViewModel.errorMessage ?? "")
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("写真を読み込んでいます…")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Top bar

    private func topBar(_ viewModel: SortingViewModel) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(captureDateText(viewModel.currentAsset))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("残り \(viewModel.remainingCount) 枚")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            if viewModel.deleteQueueCount > 0 {
                Button {
                    appState.showsDeleteConfirmation = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("\(viewModel.deleteQueueCount)")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.red, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func captureDateText(_ asset: PHAsset?) -> String {
        guard let date = asset?.creationDate else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    // MARK: - Card area

    private func cardArea(_ viewModel: SortingViewModel) -> some View {
        GeometryReader { proxy in
            // Insets keep the edge labels clear of the card itself.
            let cardSize = CGSize(
                width: proxy.size.width - 56,
                height: proxy.size.height - 104
            )

            ZStack {
                if viewModel.visibleAssets.isEmpty, viewModel.loadState == .ready {
                    Text("表示できる写真がありません")
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    CardStackView(
                        assets: viewModel.visibleAssets,
                        cardSize: cardSize,
                        activeDirection: $activeDirection,
                        onCommit: { viewModel.commit(direction: $0) }
                    )
                }

                DirectionLabelsOverlay(
                    destinations: viewModel.destinations,
                    activeDirection: activeDirection
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear { viewModel.updateCardSize(cardSize) }
            .onChange(of: cardSize) { viewModel.updateCardSize(cardSize) }
        }
    }
}

// MARK: - Bottom controls

struct BottomControlBar: View {
    let canUndo: Bool
    let onUndo: () -> Void
    let onSkip: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack {
            circleButton(systemName: "arrow.uturn.backward", action: onUndo)
                .disabled(!canUndo)
                .opacity(canUndo ? 1 : 0.35)

            Spacer()

            Button(action: onSkip) {
                Text("スキップ")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.14), in: Capsule())
            }

            Spacer()

            circleButton(systemName: "gearshape", action: onSettings)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func circleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color.white.opacity(0.1), in: Circle())
        }
    }
}
