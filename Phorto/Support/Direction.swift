import CoreGraphics
import Foundation

nonisolated enum Direction: String, CaseIterable, Codable, Sendable {
    case up
    case down
    case left
    case right

    var label: String {
        switch self {
        case .up: "上"
        case .down: "下"
        case .left: "左"
        case .right: "右"
        }
    }

    var symbolName: String {
        switch self {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        }
    }

    /// Unit vector the card flies toward when a swipe commits.
    var vector: CGSize {
        switch self {
        case .up: CGSize(width: 0, height: -1)
        case .down: CGSize(width: 0, height: 1)
        case .left: CGSize(width: -1, height: 0)
        case .right: CGSize(width: 1, height: 0)
        }
    }

    /// Dominant-axis direction for a drag translation, or nil when there is no movement.
    static func from(translation: CGSize) -> Direction? {
        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        guard horizontal > 0 || vertical > 0 else { return nil }
        if horizontal >= vertical {
            return translation.width < 0 ? .left : .right
        }
        return translation.height < 0 ? .up : .down
    }
}

nonisolated enum DestinationType: String, Codable, Sendable {
    case album
    case trash
}

nonisolated enum ScopeType: String, CaseIterable, Codable, Sendable {
    case all
    case excludeScreenshots
    case dateRange
    case specificAlbum

    var label: String {
        switch self {
        case .all: "すべての写真"
        case .excludeScreenshots: "スクリーンショットを除く"
        case .dateRange: "期間を指定"
        case .specificAlbum: "特定のアルバム"
        }
    }
}

/// Named to avoid colliding with Foundation's own `SortOrder`.
nonisolated enum PhotoSortOrder: String, CaseIterable, Codable, Sendable {
    case newest
    case oldest
    case random

    var label: String {
        switch self {
        case .newest: "新しい順"
        case .oldest: "古い順"
        case .random: "ランダム"
        }
    }
}
