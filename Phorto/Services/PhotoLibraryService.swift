import Foundation
import Photos
import UIKit

struct AlbumInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let count: Int
}

enum PhotoLibraryError: LocalizedError {
    case albumNotFound
    case assetNotFound
    case albumCreationFailed

    var errorDescription: String? {
        switch self {
        case .albumNotFound: "アルバムが見つかりませんでした。"
        case .assetNotFound: "写真が見つかりませんでした。"
        case .albumCreationFailed: "アルバムを作成できませんでした。"
        }
    }
}

/// Every call into the Photos framework goes through here, so PhotoKit's
/// callback- and background-queue-based API stays out of the view layer.
@Observable
final class PhotoLibraryService {
    private(set) var authorizationStatus: PHAuthorizationStatus

    init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    var hasAnyAccess: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    // MARK: - Authorization

    @discardableResult
    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func presentLimitedLibraryPicker(from controller: UIViewController) {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }

    // MARK: - Fetching

    /// Walks the library and returns the identifiers to sort, in display order.
    ///
    /// `nonisolated` and self-contained on purpose: `PHFetchResult` and `PHAsset` are not
    /// `Sendable`, so they must never escape this function. Only `[String]` crosses back.
    nonisolated static func fetchAssetIdentifiers(
        scope: ScopeType,
        dateRangeStart: Date?,
        dateRangeEnd: Date?,
        scopeAlbumIdentifier: String?,
        sortOrder: PhotoSortOrder,
        excluding processedIdentifiers: Set<String>
    ) -> [String] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d",
            PHAssetMediaType.image.rawValue
        )
        // Random order is shuffled after fetching, so any stable order works here.
        let ascending = sortOrder == .oldest
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: ascending)
        ]

        if scope == .dateRange, let start = dateRangeStart, let end = dateRangeEnd {
            let mediaPredicate = options.predicate!
            let rangePredicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@",
                start as NSDate,
                end as NSDate
            )
            options.predicate = NSCompoundPredicate(
                andPredicateWithSubpredicates: [mediaPredicate, rangePredicate]
            )
        }

        let result: PHFetchResult<PHAsset>
        if scope == .specificAlbum, let albumIdentifier = scopeAlbumIdentifier {
            let collections = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumIdentifier],
                options: nil
            )
            guard let collection = collections.firstObject else { return [] }
            result = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            result = PHAsset.fetchAssets(with: options)
        }

        // Screenshot exclusion is filtered here rather than via an NSPredicate: the Photos
        // framework does not reliably support bitmask predicates on mediaSubtype.
        let excludeScreenshots = scope == .excludeScreenshots
        var identifiers: [String] = []
        identifiers.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            if excludeScreenshots, asset.mediaSubtypes.contains(.photoScreenshot) {
                return
            }
            if processedIdentifiers.contains(asset.localIdentifier) {
                return
            }
            identifiers.append(asset.localIdentifier)
        }

        return sortOrder == .random ? identifiers.shuffled() : identifiers
    }

    func asset(for identifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    func assets(for identifiers: [String]) -> [PHAsset] {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var byIdentifier: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in
            byIdentifier[asset.localIdentifier] = asset
        }
        // Preserve the caller's ordering; missing assets are silently dropped.
        return identifiers.compactMap { byIdentifier[$0] }
    }

    // MARK: - Albums

    func userAlbums() -> [AlbumInfo] {
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )
        var albums: [AlbumInfo] = []
        collections.enumerateObjects { collection, _, _ in
            let assetCount = PHAsset.fetchAssets(in: collection, options: nil).count
            albums.append(
                AlbumInfo(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? "名称未設定",
                    count: assetCount
                )
            )
        }
        return albums.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func albumTitle(for identifier: String) -> String? {
        PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [identifier],
            options: nil
        ).firstObject?.localizedTitle
    }

    /// Creates an album and returns its local identifier.
    func createAlbum(titled title: String) async throws -> String {
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                withTitle: title
            )
            placeholder = request.placeholderForCreatedAssetCollection
        }
        guard let identifier = placeholder?.localIdentifier else {
            throw PhotoLibraryError.albumCreationFailed
        }
        return identifier
    }

    func isAsset(_ assetIdentifier: String, inAlbum albumIdentifier: String) -> Bool {
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier],
            options: nil
        )
        guard let collection = collections.firstObject else { return false }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "localIdentifier == %@", assetIdentifier)
        return PHAsset.fetchAssets(in: collection, options: options).count > 0
    }

    func addAsset(_ assetIdentifier: String, toAlbum albumIdentifier: String) async throws {
        guard let asset = asset(for: assetIdentifier) else {
            throw PhotoLibraryError.assetNotFound
        }
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier],
            options: nil
        )
        guard let collection = collections.firstObject else {
            throw PhotoLibraryError.albumNotFound
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest(for: collection)
            request?.addAssets([asset] as NSArray)
        }
    }

    func removeAsset(_ assetIdentifier: String, fromAlbum albumIdentifier: String) async throws {
        guard let asset = asset(for: assetIdentifier) else {
            throw PhotoLibraryError.assetNotFound
        }
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier],
            options: nil
        )
        guard let collection = collections.firstObject else {
            throw PhotoLibraryError.albumNotFound
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest(for: collection)
            request?.removeAssets([asset] as NSArray)
        }
    }

    // MARK: - Deletion

    /// Deletes the whole batch in a single change request, so iOS asks the user only once.
    func deleteAssets(_ identifiers: [String]) async throws {
        let assetsToDelete = assets(for: identifiers)
        guard !assetsToDelete.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
        }
    }
}
