import SwiftData
import SwiftUI

struct OnboardingFlowView: View {
    let config: SortSessionConfig

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = OnboardingViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if appState.photoService.hasAnyAccess {
                    setupSteps
                } else {
                    PermissionRequestView()
                }
            }
            .navigationTitle(viewModel.step.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: appState.photoService.authorizationStatus) { _, _ in }
    }

    private var setupSteps: some View {
        VStack(spacing: 0) {
            stepIndicator

            Group {
                switch viewModel.step {
                case .directions:
                    DirectionSetupView(viewModel: viewModel)
                case .scope:
                    ScopeSetupView(viewModel: viewModel)
                case .order:
                    OrderSetupView(viewModel: viewModel)
                }
            }

            footer
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingViewModel.Step.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= viewModel.step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack {
            if viewModel.step != .directions {
                Button("戻る") { viewModel.goBack() }
                    .buttonStyle(.bordered)
            }

            Spacer()

            Button(viewModel.step == .order ? "はじめる" : "次へ") {
                if viewModel.step == .order {
                    viewModel.persist(config: config, context: modelContext)
                } else {
                    viewModel.advance()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canAdvance)
        }
        .padding(20)
    }
}

// MARK: - Step 1: directions

struct DirectionSetupView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var editingDirection: Direction?

    var body: some View {
        VStack(spacing: 20) {
            Text("上下左右それぞれをどこに仕分けるか選びます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            directionCross

            if !viewModel.isDirectionStepValid {
                Text("4方向すべてを設定してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.top, 20)
        .sheet(item: $editingDirection) { direction in
            DestinationPickerView(
                direction: direction,
                takenAlbumIDs: viewModel.takenAlbumIDs(excluding: direction),
                isTrashTaken: viewModel.isTrashTaken(excluding: direction),
                onSelect: { viewModel.draft[direction] = $0 }
            )
        }
    }

    /// Cross layout so the setup mirrors the swipe directions themselves.
    private var directionCross: some View {
        VStack(spacing: 10) {
            slot(.up)
            HStack(spacing: 10) {
                slot(.left)
                Image(systemName: "hand.draw")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 64)
                slot(.right)
            }
            slot(.down)
        }
        .padding(.horizontal, 20)
    }

    private func slot(_ direction: Direction) -> some View {
        Button {
            editingDirection = direction
        } label: {
            VStack(spacing: 4) {
                Image(systemName: direction.symbolName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(viewModel.draft[direction]?.title ?? "未設定")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(titleColor(for: direction))
            }
            .frame(width: 116, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.secondary.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        viewModel.draft[direction] == nil ? Color.secondary.opacity(0.3) : Color.accentColor,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func titleColor(for direction: Direction) -> Color {
        guard let destination = viewModel.draft[direction] else { return .secondary }
        return destination.isTrash ? .red : .primary
    }
}

extension Direction: Identifiable {
    var id: String { rawValue }
}

// MARK: - Step 2: scope

struct ScopeSetupView: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(AppState.self) private var appState
    @State private var albums: [AlbumInfo] = []

    var body: some View {
        Form {
            Section {
                ForEach(ScopeType.allCases, id: \.rawValue) { scope in
                    Button {
                        viewModel.scope = scope
                    } label: {
                        HStack {
                            Text(scope.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if viewModel.scope == scope {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            } header: {
                Text("対象にする写真")
            } footer: {
                Text("動画と、すでに仕分けた写真は常に除外されます。")
            }

            if viewModel.scope == .dateRange {
                Section("期間") {
                    DatePicker("開始", selection: $viewModel.dateRangeStart, displayedComponents: .date)
                    DatePicker("終了", selection: $viewModel.dateRangeEnd, displayedComponents: .date)
                }
            }

            if viewModel.scope == .specificAlbum {
                Section("アルバム") {
                    if albums.isEmpty {
                        Text("アルバムがありません")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(albums) { album in
                        Button {
                            viewModel.scopeAlbum = album
                        } label: {
                            HStack {
                                Text(album.title).foregroundStyle(.primary)
                                Spacer()
                                Text("\(album.count)").foregroundStyle(.secondary)
                                if viewModel.scopeAlbum?.id == album.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            albums = appState.photoService.userAlbums()
        }
    }
}

// MARK: - Step 3: order

struct OrderSetupView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        Form {
            Section {
                ForEach(PhotoSortOrder.allCases, id: \.rawValue) { order in
                    Button {
                        viewModel.sortOrder = order
                    } label: {
                        HStack {
                            Text(order.label).foregroundStyle(.primary)
                            Spacer()
                            if viewModel.sortOrder == order {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            } header: {
                Text("表示する順番")
            } footer: {
                Text("ランダムの並びは起動するたびに作り直されます。")
            }
        }
    }
}
