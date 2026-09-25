import Foundation
import Photos
import UIKit

/// An image delivered for a card, plus whether a better version is still coming.
struct LoadedImage: Sendable {
    let image: UIImage
    let isDegraded: Bool
}

/// Wraps `PHCachingImageManager` so the next few cards are already decoded (and, for
/// iCloud-only originals, already downloaded) by the time the user swipes to them.
@Observable
final class ImageProvider {
    private let manager = PHCachingImageManager()
    private var cachedAssets: [PHAsset] = []

    /// How many upcoming cards are kept warm. Large enough to hide an iCloud download,
    /// small enough that a 10k-photo library does not blow up memory.
    static let lookaheadWindow = 4

    // MARK: - Prefetching

    func updateCache(for assets: [PHAsset], targetSize: CGSize) {
        let newIdentifiers = Set(assets.map(\.localIdentifier))
        let staleAssets = cachedAssets.filter { !newIdentifiers.contains($0.localIdentifier) }

        if !staleAssets.isEmpty {
            manager.stopCachingImages(
                for: staleAssets,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: Self.imageRequestOptions(deliveryMode: .highQualityFormat)
            )
        }

        let cachedIdentifiers = Set(cachedAssets.map(\.localIdentifier))
        let freshAssets = assets.filter { !cachedIdentifiers.contains($0.localIdentifier) }
        if !freshAssets.isEmpty {
            manager.startCachingImages(
                for: freshAssets,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: Self.imageRequestOptions(deliveryMode: .highQualityFormat)
            )
        }

        cachedAssets = assets
    }

    func stopCachingAll() {
        manager.stopCachingImagesForAllAssets()
        cachedAssets = []
    }

    // MARK: - Loading

    /// Yields a fast low-quality image first (when one is available) and then the full
    /// one, so an iCloud download shows something immediately instead of a blank card.
    func imageStream(for asset: PHAsset, targetSize: CGSize) -> AsyncStream<LoadedImage> {
        AsyncStream { continuation in
            let options = Self.imageRequestOptions(deliveryMode: .opportunistic)
            let requestID = manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                guard !isCancelled else {
                    continuation.finish()
                    return
                }
                if let image {
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    continuation.yield(LoadedImage(image: image, isDegraded: isDegraded))
                    if !isDegraded { continuation.finish() }
                } else if info?[PHImageErrorKey] != nil {
                    continuation.finish()
                }
            }

            continuation.onTermination = { [manager] reason in
                if case .cancelled = reason {
                    manager.cancelImageRequest(requestID)
                }
            }
        }
    }

    func livePhoto(for asset: PHAsset, targetSize: CGSize) async -> PHLivePhoto? {
        await withCheckedContinuation { continuation in
            let options = PHLivePhotoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            // The handler can fire more than once; only the first non-degraded result
            // resumes the continuation.
            let hasResumed = ResumeGuard()
            manager.requestLivePhoto(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { livePhoto, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded else { return }
                guard hasResumed.claim() else { return }
                continuation.resume(returning: livePhoto)
            }
        }
    }

    // MARK: - Helpers

    private static func imageRequestOptions(
        deliveryMode: PHImageRequestOptionsDeliveryMode
    ) -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        // Photos stored only in iCloud must be downloaded before they can be shown.
        options.isNetworkAccessAllowed = true
        options.deliveryMode = deliveryMode
        options.resizeMode = .fast
        options.isSynchronous = false
        return options
    }

    /// Target size in pixels for a full-screen card, so Photos does not decode originals.
    static func cardTargetSize(for size: CGSize) -> CGSize {
        let scale = UIScreen.main.scale
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

/// Ensures a multi-call PhotoKit handler resumes its continuation exactly once.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
