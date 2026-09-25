import Photos
import SwiftUI

struct PhotoCardView: View {
    let asset: PHAsset
    let targetSize: CGSize
    let isFront: Bool
    let isDragging: Bool

    @Environment(AppState.self) private var appState

    @State private var image: UIImage?
    @State private var isDegraded = false
    @State private var livePhoto: PHLivePhoto?
    @State private var playbackToken = 0
    @State private var isMuted = true

    private var isLivePhoto: Bool {
        asset.mediaSubtypes.contains(.photoLive)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(white: 0.12))

            content

            if isLivePhoto {
                livePhotoBadge
            }

            if image == nil {
                ProgressView()
                    .tint(.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isFront, isLivePhoto, livePhoto != nil else { return }
            // Tapping replays with sound, per F7.
            isMuted = false
            playbackToken += 1
        }
        .task(id: asset.localIdentifier) {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let livePhoto, isFront {
            LivePhotoDisplayView(
                livePhoto: livePhoto,
                isMuted: isMuted,
                playbackToken: playbackToken,
                isPaused: isDragging
            )
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        }
    }

    private var livePhotoBadge: some View {
        VStack {
            HStack {
                Image(systemName: isMuted ? "livephoto" : "livephoto.play")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.35), in: Circle())
                Spacer()
            }
            Spacer()
        }
        .padding(12)
        .allowsHitTesting(false)
    }

    private func load() async {
        isMuted = true
        livePhoto = nil

        for await loaded in appState.imageProvider.imageStream(for: asset, targetSize: targetSize) {
            image = loaded.image
            isDegraded = loaded.isDegraded
        }

        guard isLivePhoto, isFront, !Task.isCancelled else { return }
        let loadedLivePhoto = await appState.imageProvider.livePhoto(
            for: asset,
            targetSize: targetSize
        )
        guard !Task.isCancelled else { return }
        livePhoto = loadedLivePhoto
        if loadedLivePhoto != nil {
            // Autoplay once, muted, the moment the card is shown.
            playbackToken += 1
        }
    }
}
