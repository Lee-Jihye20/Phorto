import Photos
import PhotosUI
import SwiftUI

/// Wraps `PHLivePhotoView`, which shows the still key photo whenever it is not playing —
/// exactly the "play once, then freeze" behaviour the spec asks for.
struct LivePhotoDisplayView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let isMuted: Bool
    /// Bumping this plays the Live Photo from the start.
    let playbackToken: Int
    /// Set while the card is being dragged, which stops playback.
    let isPaused: Bool

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.isMuted = isMuted
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        if uiView.livePhoto !== livePhoto {
            uiView.livePhoto = livePhoto
            context.coordinator.playedToken = nil
        }
        uiView.isMuted = isMuted

        if isPaused {
            if context.coordinator.isPlaying {
                uiView.stopPlayback()
                context.coordinator.isPlaying = false
            }
            return
        }

        if context.coordinator.playedToken != playbackToken {
            context.coordinator.playedToken = playbackToken
            context.coordinator.isPlaying = true
            uiView.startPlayback(with: .full)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var playedToken: Int?
        var isPlaying = false
    }
}
