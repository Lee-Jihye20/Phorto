import SwiftUI

/// Picks what a single direction sorts into: an existing album, a new album, or the trash.
struct DestinationPickerView: View {
    let direction: Direction
    let takenAlbumIDs: Set<String>
    let isTrashTaken: Bool
    let onSelect: (DirectionDestination) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var albums: [AlbumInfo] = []
    @State private var isCreatingAlbum = false
    @State private var newAlbumName = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelect(
                            DirectionDestination(
                                direction: direction,
                                type: .trash,
                                albumID: nil,
                                title: "ゴミ箱"
                            )
                        )
                        dismiss()
                    } label: {
                        Label("ゴミ箱", systemImage: "trash.fill")
                            .foregroundStyle(isTrashTaken ? Color.secondary : Color.red)
                    }
                    .disabled(isTrashTaken)

                    Button {
                        newAlbumName = ""
                        isCreatingAlbum = true
                    } label: {
                        Label("新規アルバムを作成", systemImage: "folder.badge.plus")
                    }
                } footer: {
                    if isTrashTaken {
                        Text("ゴミ箱は1方向にのみ割り当てられます。")
                    }
                }

                Section("既存のアルバム") {
                    if albums.isEmpty {
                        Text("アルバムがありません")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(albums) { album in
                        let isTaken = takenAlbumIDs.contains(album.id)
                        Button {
                            onSelect(
                                DirectionDestination(
                                    direction: direction,
                                    type: .album,
                                    albumID: album.id,
                                    title: album.title
                                )
                            )
                            dismiss()
                        } label: {
                            HStack {
                                Label(album.title, systemImage: "rectangle.stack")
                                Spacer()
                                Text("\(album.count)")
                                    .foregroundStyle(.secondary)
                                if isTaken {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(isTaken)
                        .foregroundStyle(isTaken ? Color.secondary : Color.primary)
                    }
                }
            }
            .navigationTitle("\(direction.label)方向の行き先")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .alert("新規アルバム", isPresented: $isCreatingAlbum) {
                TextField("アルバム名", text: $newAlbumName)
                Button("キャンセル", role: .cancel) {}
                Button("作成") { createAlbum() }
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
            .task {
                albums = appState.photoService.userAlbums()
            }
        }
    }

    private func createAlbum() {
        let title = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        Task {
            do {
                let identifier = try await appState.photoService.createAlbum(titled: title)
                onSelect(
                    DirectionDestination(
                        direction: direction,
                        type: .album,
                        albumID: identifier,
                        title: title
                    )
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
