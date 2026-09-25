import Photos
import SwiftUI

struct PermissionRequestView: View {
    @Environment(AppState.self) private var appState

    private var status: PHAuthorizationStatus {
        appState.photoService.authorizationStatus
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.white)

                VStack(spacing: 10) {
                    Text("写真へのアクセスを許可してください")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Phortoは写真を1枚ずつ表示して、スワイプでアルバムに仕分けます。写真の読み取りと、アルバムへの追加・削除のために写真ライブラリへのアクセスが必要です。")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                actionButton
            }
            .padding(32)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if status == .denied || status == .restricted {
            VStack(spacing: 12) {
                Text("アクセスが許可されていません。設定アプリから変更できます。")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)

                Button("設定アプリを開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            Button("アクセスを許可") {
                Task { await appState.photoService.requestAuthorization() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

/// Shown while the app is running on a partial photo selection. Non-blocking on purpose:
/// sorting still works within the allowed subset.
struct LimitedAccessBanner: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("一部の写真のみアクセスが許可されています")
                    .font(.caption.bold())
                Text("対象を増やすには写真を追加で選択してください。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("選択") {
                presentLimitedPicker()
            }
            .font(.caption.bold())
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func presentLimitedPicker() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let controller = scene.keyWindow?.rootViewController
        else { return }
        appState.photoService.presentLimitedLibraryPicker(from: controller)
    }
}
