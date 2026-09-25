import Photos
import SwiftUI

struct AssetThumbnailView: View {
    let asset: PHAsset
    var side: CGFloat = 200

    @Environment(AppState.self) private var appState
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.15))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipped()
        .task(id: asset.localIdentifier) {
            let targetSize = CGSize(width: side, height: side)
            for await loaded in appState.imageProvider.imageStream(
                for: asset,
                targetSize: targetSize
            ) {
                image = loaded.image
            }
        }
    }
}
