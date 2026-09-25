import UIKit

enum HapticsService {
    private static let impact = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()

    /// Call as the drag begins so the engine is warm when the swipe commits.
    static func prepare() {
        impact.prepare()
    }

    static func swipeCommitted() {
        impact.impactOccurred()
    }

    static func undone() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func failed() {
        notification.notificationOccurred(.error)
    }
}
