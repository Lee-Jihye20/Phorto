import Photos
import SwiftUI

struct CardStackView: View {
    let assets: [PHAsset]
    let cardSize: CGSize
    @Binding var activeDirection: Direction?
    let onCommit: (Direction) -> Void

    /// Drag distance past which releasing commits the swipe.
    private static let commitDistance: CGFloat = 110
    /// Fling distance (from the gesture's projected endpoint) that commits regardless.
    private static let flingDistance: CGFloat = 260

    @State private var dragTranslation: CGSize = .zero
    @State private var isCommitting = false
    @State private var zoomScale: CGFloat = 1
    @State private var zoomAnchor: CGFloat = 1

    private var isZoomed: Bool { zoomScale > 1.01 }

    var body: some View {
        ZStack {
            ForEach(Array(assets.enumerated()).reversed(), id: \.element.localIdentifier) { index, asset in
                card(at: index, asset: asset)
            }
        }
        .onChange(of: assets.first?.localIdentifier) {
            // A new front card always starts unzoomed.
            zoomScale = 1
            zoomAnchor = 1
        }
    }

    @ViewBuilder
    private func card(at index: Int, asset: PHAsset) -> some View {
        let isFront = index == 0
        let depth = CGFloat(index)

        PhotoCardView(
            asset: asset,
            targetSize: ImageProvider.cardTargetSize(for: cardSize),
            isFront: isFront,
            isDragging: isFront && dragTranslation != .zero
        )
        .frame(width: cardSize.width, height: cardSize.height)
        .scaleEffect(isFront ? zoomScale : 1 - depth * 0.04)
        .offset(y: isFront ? 0 : depth * 10)
        .offset(isFront ? dragTranslation : .zero)
        .rotationEffect(.degrees(isFront ? Double(dragTranslation.width / 22) : 0))
        .zIndex(Double(assets.count - index))
        .allowsHitTesting(isFront)
        .gesture(dragGesture, including: isFront ? .all : .none)
        .simultaneousGesture(magnifyGesture, including: isFront ? .all : .none)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // While zoomed in, dragging pans the photo instead of sorting it.
                guard !isZoomed, !isCommitting else { return }
                if dragTranslation == .zero {
                    HapticsService.prepare()
                }
                dragTranslation = value.translation
                activeDirection = Direction.from(translation: value.translation)
            }
            .onEnded { value in
                guard !isZoomed, !isCommitting else { return }
                guard let direction = Direction.from(translation: value.translation) else {
                    resetDrag()
                    return
                }

                let distance = magnitude(value.translation, along: direction)
                let projected = magnitude(value.predictedEndTranslation, along: direction)

                if distance > Self.commitDistance || projected > Self.flingDistance {
                    flyAway(direction)
                } else {
                    resetDrag()
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoomScale = min(max(zoomAnchor * value, 1), 4)
            }
            .onEnded { _ in
                if zoomScale < 1.05 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        zoomScale = 1
                    }
                    zoomAnchor = 1
                } else {
                    zoomAnchor = zoomScale
                }
            }
    }

    private func magnitude(_ translation: CGSize, along direction: Direction) -> CGFloat {
        switch direction {
        case .left, .right: abs(translation.width)
        case .up, .down: abs(translation.height)
        }
    }

    private func flyAway(_ direction: Direction) {
        isCommitting = true
        HapticsService.swipeCommitted()

        let exit = CGSize(
            width: direction.vector.width * 900,
            height: direction.vector.height * 1_200
        )
        withAnimation(.easeOut(duration: 0.24)) {
            dragTranslation = exit
        }

        Task {
            try? await Task.sleep(for: .seconds(0.24))
            // Advancing the queue and clearing the offset in the same turn means the next
            // card never renders at the departing card's position.
            onCommit(direction)
            dragTranslation = .zero
            activeDirection = nil
            isCommitting = false
        }
    }

    private func resetDrag() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
            dragTranslation = .zero
        }
        activeDirection = nil
    }
}
