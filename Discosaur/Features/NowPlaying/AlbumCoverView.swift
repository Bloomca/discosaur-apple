import ImageIO
import SwiftUI

// Avoid decoding unchanged artwork when the player's position updates.
struct AlbumCoverView: View, Equatable {
    let data: Data
    var size: CGFloat = 48

    var body: some View {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceCreateThumbnailWithTransform: true,
               kCGImageSourceThumbnailMaxPixelSize: size * 3,
           ] as CFDictionary) {
            Image(image, scale: 1, label: Text("Album cover"))
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
