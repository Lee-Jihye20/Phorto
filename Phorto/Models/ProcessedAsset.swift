import Foundation
import SwiftData

/// Record of a photo the user has already sorted, so it is never shown again.
@Model
final class ProcessedAsset {
    @Attribute(.unique) var assetLocalIdentifier: String
    var directionRaw: String
    var destinationAlbumIdentifier: String?
    var destinationAlbumTitle: String?
    var wasTrash: Bool
    var processedAt: Date

    init(
        assetLocalIdentifier: String,
        direction: Direction,
        destinationAlbumIdentifier: String?,
        destinationAlbumTitle: String?,
        wasTrash: Bool,
        processedAt: Date = .now
    ) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.directionRaw = direction.rawValue
        self.destinationAlbumIdentifier = destinationAlbumIdentifier
        self.destinationAlbumTitle = destinationAlbumTitle
        self.wasTrash = wasTrash
        self.processedAt = processedAt
    }

    var direction: Direction {
        Direction(rawValue: directionRaw) ?? .up
    }
}
