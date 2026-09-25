import Foundation
import SwiftData

/// Single-row model holding the scope and ordering the sorting session runs with.
@Model
final class SortSessionConfig {
    var scopeRaw: String
    var dateRangeStart: Date?
    var dateRangeEnd: Date?
    var scopeAlbumIdentifier: String?
    var scopeAlbumTitle: String?
    var sortOrderRaw: String
    var hasCompletedOnboarding: Bool

    init(
        scope: ScopeType = .all,
        sortOrder: PhotoSortOrder = .newest,
        hasCompletedOnboarding: Bool = false
    ) {
        self.scopeRaw = scope.rawValue
        self.sortOrderRaw = sortOrder.rawValue
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    var scope: ScopeType {
        get { ScopeType(rawValue: scopeRaw) ?? .all }
        set { scopeRaw = newValue.rawValue }
    }

    var sortOrder: PhotoSortOrder {
        get { PhotoSortOrder(rawValue: sortOrderRaw) ?? .newest }
        set { sortOrderRaw = newValue.rawValue }
    }

    var scopeDescription: String {
        switch scope {
        case .all, .excludeScreenshots:
            return scope.label
        case .dateRange:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            let start = dateRangeStart.map(formatter.string(from:)) ?? "指定なし"
            let end = dateRangeEnd.map(formatter.string(from:)) ?? "指定なし"
            return "\(start) 〜 \(end)"
        case .specificAlbum:
            return scopeAlbumTitle ?? "アルバム未選択"
        }
    }
}
