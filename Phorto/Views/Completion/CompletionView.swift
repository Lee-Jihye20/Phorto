import SwiftData
import SwiftUI

struct CompletionView: View {
    let config: SortSessionConfig

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showsDeleteConfirmation = false
    @State private var showsSettings = false

    private var viewModel: SortingViewModel? { appState.sortingViewModel }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    header
                    tallyList
                    deleteQueueSection
                    actions
                }
                .padding(24)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsDeleteConfirmation) {
            DeleteConfirmationSheet()
        }
        .sheet(isPresented: $showsSettings) {
            SettingsSheet(config: config)
        }
        .task {
            // Entering the completion screen is one of the two moments the spec says the
            // pending deletions should be offered.
            if (viewModel?.deleteQueueCount ?? 0) > 0 {
                showsDeleteConfirmation = true
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
            Text("仕分け完了")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("対象の写真をすべて処理しました。")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private var tallyList: some View {
        if let summary = viewModel?.tallySummary, !summary.isEmpty {
            VStack(spacing: 0) {
                ForEach(summary, id: \.title) { entry in
                    HStack {
                        Text(entry.title)
                            .foregroundStyle(entry.title == SortingViewModel.trashTitle ? .red : .white)
                        Spacer()
                        Text("\(entry.count) 枚")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .font(.system(size: 15, weight: .medium))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)

                    if entry.title != summary.last?.title {
                        Divider().overlay(Color.white.opacity(0.1))
                    }
                }
            }
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        } else {
            Text("今回は仕分けた写真がありません。")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    @ViewBuilder
    private var deleteQueueSection: some View {
        if let count = viewModel?.deleteQueueCount, count > 0 {
            Button {
                showsDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("\(count)枚の削除を実行する")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if let skippedCount = viewModel?.skippedCount, skippedCount > 0 {
                Button {
                    viewModel?.reviewSkipped()
                    dismiss()
                } label: {
                    Text("スキップした\(skippedCount)枚を見直す")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
            }

            // Without this the screen is a dead end whenever the current scope has
            // nothing left to sort: reloading just returns here.
            Button {
                showsSettings = true
            } label: {
                Label("設定を変更する", systemImage: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }

            Button {
                Task {
                    await viewModel?.restartSession(config: config)
                    dismiss()
                }
            } label: {
                Text("もう一度読み込む")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
