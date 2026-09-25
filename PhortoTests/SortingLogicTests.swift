import Testing
import CoreGraphics
@testable import Phorto

@Suite("スワイプ方向の判定")
struct DirectionTests {
    @Test("移動量が大きい軸で方向が決まる")
    func dominantAxis() {
        #expect(Direction.from(translation: CGSize(width: -120, height: 20)) == .left)
        #expect(Direction.from(translation: CGSize(width: 120, height: -20)) == .right)
        #expect(Direction.from(translation: CGSize(width: 10, height: -140)) == .up)
        #expect(Direction.from(translation: CGSize(width: -10, height: 140)) == .down)
    }

    @Test("移動がなければ方向は決まらない")
    func noMovement() {
        #expect(Direction.from(translation: .zero) == nil)
    }

    @Test("縦横が同値なら横方向を優先する")
    func tieBreaksHorizontal() {
        #expect(Direction.from(translation: CGSize(width: 50, height: 50)) == .right)
    }
}

@Suite("Undo対象の識別")
struct UndoableActionTests {
    @Test("種類にかかわらず対象の写真IDを取り出せる")
    func assetIDExtraction() {
        let sorted = UndoableAction.sorted(
            assetID: "A",
            direction: .left,
            albumID: "album",
            albumTitle: "旅行",
            wasAlreadyInAlbum: false
        )
        #expect(sorted.assetID == "A")
        #expect(UndoableAction.trashed(assetID: "B", direction: .down).assetID == "B")
        #expect(UndoableAction.skipped(assetID: "C").assetID == "C")
    }
}
