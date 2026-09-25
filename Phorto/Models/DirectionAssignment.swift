import Foundation
import SwiftData

@Model
final class DirectionAssignment {
    @Attribute(.unique) var directionRaw: String
    var destinationTypeRaw: String
    var albumLocalIdentifier: String?
    var albumTitle: String

    init(
        direction: Direction,
        destinationType: DestinationType,
        albumLocalIdentifier: String?,
        albumTitle: String
    ) {
        self.directionRaw = direction.rawValue
        self.destinationTypeRaw = destinationType.rawValue
        self.albumLocalIdentifier = albumLocalIdentifier
        self.albumTitle = albumTitle
    }

    var direction: Direction {
        get { Direction(rawValue: directionRaw) ?? .up }
        set { directionRaw = newValue.rawValue }
    }

    var destinationType: DestinationType {
        get { DestinationType(rawValue: destinationTypeRaw) ?? .album }
        set { destinationTypeRaw = newValue.rawValue }
    }

    /// Display name shown on the matching edge of the sorting screen.
    var displayTitle: String {
        destinationType == .trash ? "ゴミ箱" : albumTitle
    }
}
