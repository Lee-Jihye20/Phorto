import Photos
import SwiftUI

struct DeleteConfirmationSheet: View {
    var isPendingFromPreviousLaunch = false

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 6)]

    private var viewModel: SortingViewModel? { appState.sortingViewModel }

    var body: some View {
        NavigationStack {
            Group {
                if assets.isEmpty {
                    ContentUnavailableView(
                        "削除待ちの写真はありません",
                        systemImage: "trash",
                        description: Text("ゴミ箱の方向にスワイプした写真がここに並びます。")
                    )
                } else {
                    grid
                }
            }
            .navigationTitle("削除の確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isPendingFromPreviousLaunch ? "あとで" : "閉じる") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !assets.isEmpty {
                    deleteButton
                }
            }
            .alert(
                "エラー",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task { reload() }
        }
    }

    private var grid: some View {
        ScrollView {
            if isPendingFromPreviousLaunch {
                Text("前回、削除されないまま残っていた写真があります。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    AssetThumbnailView(asset: asset)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                restore(asset)
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.system(size: 20))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.55))
                                    .padding(4)
                            }
                        }
                }
            }
            .padding(12)
        }
    }

    private var deleteButton: some View {
        VStack(spacing: 8) {
            Text("削除した写真は写真アプリの「最近削除した項目」に入り、30日間は復元できます。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                deleteAll()
            } label: {
                HStack {
                    if isDeleting {
                        ProgressView().tint(.white)
                    }
                    Text("\(assets.count)枚を削除する")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .background(Color.red, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            .disabled(isDeleting)
        }
        .padding(16)
        .background(.bar)
    }

    private func reload() {
        assets = viewModel?.deleteQueueAssets() ?? []
    }

    private func restore(_ asset: PHAsset) {
        viewModel?.restoreFromDeleteQueue(assetID: asset.localIdentifier)
        reload()
        if assets.isEmpty { dismiss() }
    }

    private func deleteAll() {
        guard let viewModel else { return }
        isDeleting = true
        Task {
            do {
                try await viewModel.executeDeleteQueue()
                dismiss()
            } catch {
                // Cancelling the system confirmation lands here; the queue is left intact.
                errorMessage = "削除は実行されませんでした。"
                reload()
            }
            isDeleting = false
        }
    }
}
