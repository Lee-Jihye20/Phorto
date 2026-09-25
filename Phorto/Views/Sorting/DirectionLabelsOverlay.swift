import SwiftUI

/// The four destination names pinned to the edges of the card area. All four stay visible
/// at all times; the one matching the current drag direction highlights.
struct DirectionLabelsOverlay: View {
    let destinations: [Direction: DirectionDestination]
    let activeDirection: Direction?

    var body: some View {
        VStack(spacing: 0) {
            label(for: .up)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                label(for: .left)
                Spacer(minLength: 0)
                label(for: .right)
            }
            Spacer(minLength: 0)
            label(for: .down)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func label(for direction: Direction) -> some View {
        if let destination = destinations[direction] {
            let isActive = activeDirection == direction
            HStack(spacing: 5) {
                Image(systemName: destination.isTrash ? "trash.fill" : direction.symbolName)
                    .font(.system(size: 12, weight: .bold))
                Text(destination.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground(for: destination, isActive: isActive))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(background(for: destination, isActive: isActive), in: Capsule())
            .scaleEffect(isActive ? 1.12 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isActive)
        }
    }

    private func foreground(for destination: DirectionDestination, isActive: Bool) -> Color {
        if isActive { return .white }
        return destination.isTrash ? .red.opacity(0.9) : .white.opacity(0.65)
    }

    private func background(for destination: DirectionDestination, isActive: Bool) -> Color {
        if isActive {
            return destination.isTrash ? .red : .accentColor
        }
        return destination.isTrash ? .red.opacity(0.18) : .white.opacity(0.12)
    }
}
