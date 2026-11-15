import AppKit
import SwiftUI

/// A scene's picture, scaled to fill the space it is given.
struct SceneArtwork: View {
    /// The scene to show.
    let scene: Scene

    var body: some View {
        GeometryReader { frame in
            if let image = Wallpapers.shared.image(for: scene) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: frame.size.width, height: frame.size.height)
                    .clipped()
            } else {
                LinearGradient(colors: [Color(hex: 0x142137), Color(hex: scene.glowHex)], startPoint: .bottom, endPoint: .top)
            }
        }
        .accessibilityHidden(true)
    }
}
