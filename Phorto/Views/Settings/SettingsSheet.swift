import Photos
import SwiftData
import SwiftUI

struct SettingsSheet: View {
    let config: SortSessionConfig

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = OnboardingViewModel()
    @State private var editingDirection: Direction?
    @State private var albums: [AlbumInfo] = []
    @State private var showsResetConfirmation = false
    @State private var processedCount = 0
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            Form {
                if appState.photoService.authorizationStatus == .limited {
                    Section {
                        LimitedAccessBanner()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                directionsSection
                scopeSection
                orderSection
                maintenanceSection
                accessSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!viewModel.isDirectionStepValid || !viewModel.isScopeStepValid)
                }
            }
            .sheet(item: $editingDirection) { direction in
                DestinationPickerView(
                    direction: direction,
                    takenAlbumIDs: viewModel.takenAlbumIDs(excluding: direction),
                    isTrashTaken: viewModel.isTrashTaken(excluding: direction),
                    onSelect: { viewModel.draft[direction] = $0 }
                )
            }
            .confirmationDialog(
                "処理済みの記録をリセットしますか?",
                isPresented: $showsResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("リセットする", role: .destructive) { resetProcessed() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("すべての写真が最初から表示されるようになります。アルバムに追加済みの写真はそのままです。")
            }
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                viewModel.loadExisting(config: config, context: modelContext)
                albums = appState.photoService.userAlbums()
                refreshProcessedCount()
            }
        }
    }

    // MARK: - Sections

    private var directionsSection: some View {
        Section("方向の割り当て") {
            ForEach(Direction.allCases, id: \.rawValue) { direction in
                Button {
                    editingDirection = direction
                } label: {
                    HStack {
                        Label(direction.label, systemImage: direction.symbolName)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(viewModel.draft[direction]?.title ?? "未設定")
                            .foregroundStyle(
                                viewModel.draft[direction]?.isTrash == true ? .red : .secondary
                            )
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var scopeSection: some View {
        Section("仕分けの対象") {
            Picker("対象", selection: $viewModel.scope) {
                ForEach(ScopeType.allCases, id: \.rawValue) { scope in
                    Text(scope.label).tag(scope)
                }
            }

            if viewModel.scope == .dateRange {
                DatePicker("開始", selection: $viewModel.dateRangeStart, displayedComponents: .date)
                DatePicker("終了", selection: $viewModel.dateRangeEnd, displayedComponents: .date)
            }

            if viewModel.scope == .specificAlbum {
                Picker("アルバム", selection: $viewModel.scopeAlbum) {
                    Text("未選択").tag(AlbumInfo?.none)
                    ForEach(albums) { album in
                        Text(album.title).tag(AlbumInfo?.some(album))
                    }
                }
            }
        }
    }

    private var orderSection: some View {
        Section("表示順") {
            Picker("順番", selection: $viewModel.sortOrder) {
                ForEach(PhotoSortOrder.allCases, id: \.rawValue) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var maintenanceSection: some View {
        Section {
            Button("処理済みの記録をリセット", role: .destructive) {
                showsResetConfirmation = true
            }
        } header: {
            Text("記録")
        } footer: {
            Text("現在 \(processedCount) 枚が処理済みとして記録されています。")
        }
    }

    private var accessSection: some View {
        Section {
            HStack {
                Text("写真へのアクセス")
                Spacer()
                Text(accessStatusText)
                    .foregroundStyle(.secondary)
            }
            Button("設定アプリを開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } header: {
            Text("権限")
        }
    }

    private var accessStatusText: String {
        switch appState.photoService.authorizationStatus {
        case .authorized: "すべて許可"
        case .limited: "一部のみ許可"
        case .denied: "拒否"
        case .restricted: "制限あり"
        case .notDetermined: "未設定"
        @unknown default: "不明"
        }
    }

    // MARK: - Actions

    private func save() {
        viewModel.persist(config: config, context: modelContext)
        // Scope or order may have changed, so the queue is rebuilt from scratch.
        Task {
            await appState.sortingViewModel?.restartSession(config: config)
            dismiss()
        }
    }

    private func resetProcessed() {
        let records = (try? modelContext.fetch(FetchDescriptor<ProcessedAsset>())) ?? []
        for record in records {
            modelContext.delete(record)
        }
        try? modelContext.save()
        refreshProcessedCount()
        Task {
            await appState.sortingViewModel?.restartSession(config: config)
        }
    }

    private func refreshProcessedCount() {
        processedCount = (try? modelContext.fetchCount(FetchDescriptor<ProcessedAsset>())) ?? 0
    }
}
