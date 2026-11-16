import AppKit

/// The picture that comes with each scene.
@MainActor
final class Wallpapers {
    /// The store every view reads its pictures from.
    static let shared = Wallpapers()

    private var cache: [String: NSImage] = [:]

    /// The file holding the picture for `scene`, or `nil` if the app carries none.
    func imageURL(for scene: Scene) -> URL? {
        Bundle.main.url(forResource: scene.id, withExtension: "jpg", subdirectory: "Artwork")
    }

    /// The picture to show for `scene`, loaded once and then kept.
    func image(for scene: Scene) -> NSImage? {
        if let cached = cache[scene.id] { return cached }
        guard let url = imageURL(for: scene), let image = NSImage(contentsOf: url) else { return nil }
        cache[scene.id] = image
        return image
    }
}
