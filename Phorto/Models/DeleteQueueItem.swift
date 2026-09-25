import Foundation
import SwiftData

/// A photo swiped toward the trash but not yet deleted.
///
/// iOS shows a system confirmation for every `deleteAssets` call, so deletions are
/// batched: items accumulate here and are deleted together in one call. This survives
/// app termination on purpose — a queue left pending is offered again on next launch.
@Model
final class DeleteQueueItem {
    @Attribute(.unique) var assetLocalIdentifier: String
    var queuedAt: Date

    init(assetLocalIdentifier: String, queuedAt: Date = .now) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.queuedAt = queuedAt
    }
}
