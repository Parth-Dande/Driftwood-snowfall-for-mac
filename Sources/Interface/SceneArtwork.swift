import AppKit
import SwiftUI

struct SceneArtwork: View {
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
                LinearGradient(colors: [ink(0x142137), ink(scene.glow)], startPoint: .bottom, endPoint: .top)
            }
        }
        .accessibilityHidden(true)
    }
}
