import AppKit
import SwiftUI

/// The picture behind each scene: the bundled artwork, or one the user chose in its place.
@MainActor
@Observable
final class Wallpapers {
    /// The store every view reads its pictures from.
    static let shared = Wallpapers()

    /// A reason a chosen picture could not be used.
    struct ImportError: LocalizedError {
        let errorDescription: String?
    }

    /// Bumped whenever a picture changes, so every view showing one redraws.
    private(set) var revision = 0
    @ObservationIgnored private var cache: [String: NSImage] = [:]

    private static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Driftwood/Wallpapers", isDirectory: true)

    /// The pixel size of the largest connected display. A picture at least this big stays sharp everywhere.
    static var recommendedSize: CGSize {
        NSScreen.screens.map(\.backingPixelSize).max { $0.width * $0.height < $1.width * $1.height }
            ?? CGSize(width: 3840, height: 2160)
    }

    /// Advice on choosing a picture that will look good, for the open panel and tooltips.
    static var guidance: String {
        let size = recommendedSize
        return "Best: a landscape JPEG, PNG or HEIC of \(Int(size.width)) × \(Int(size.height)) pixels or larger, "
            + "the size of your biggest display. Pictures are scaled to fill the screen, so keep anything important away from the edges."
    }

    private func customFile(for scene: Scene) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.deletingPathExtension().lastPathComponent == scene.id }
    }

    /// Whether the user has replaced the bundled picture for `scene`.
    func hasCustomImage(for scene: Scene) -> Bool {
        _ = revision
        return customFile(for: scene) != nil
    }

    /// The picture to show for `scene`: the user's own if there is one, otherwise the bundled artwork.
    func image(for scene: Scene) -> NSImage? {
        _ = revision
        if let cached = cache[scene.id] { return cached }
        let url = customFile(for: scene) ?? Bundle.main.url(forResource: scene.id, withExtension: "jpg", subdirectory: "Artwork")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        cache[scene.id] = image
        return image
    }

    /// Copies the chosen picture into Driftwood's own directory and uses it for this scene from now on.
    /// Returns a note for the user when the picture is smaller than the display it has to fill.
    func setCustomImage(from source: URL, for scene: Scene) throws -> String? {
        guard let image = NSImage(contentsOf: source), let pixels = Self.pixelSize(of: image),
              pixels.width >= 640, pixels.height >= 400 else {
            throw ImportError(errorDescription: "Driftwood couldn’t use \(source.lastPathComponent). Choose a JPEG, PNG or HEIC picture at least 640 × 400 pixels.")
        }
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        if let old = customFile(for: scene) { try FileManager.default.removeItem(at: old) }
        let file = Self.directory.appendingPathComponent(scene.id).appendingPathExtension(source.pathExtension.lowercased())
        try FileManager.default.copyItem(at: source, to: file)
        cache[scene.id] = nil
        revision += 1
        let wanted = Self.recommendedSize
        guard pixels.width < wanted.width * 0.9 || pixels.height < wanted.height * 0.9 else { return nil }
        return "That picture is \(Int(pixels.width)) × \(Int(pixels.height)), smaller than your display, so it may look soft."
    }

    /// Deletes the user's picture for `scene`, bringing the bundled artwork back.
    func removeCustomImage(for scene: Scene) {
        guard let file = customFile(for: scene) else { return }
        try? FileManager.default.removeItem(at: file)
        cache[scene.id] = nil
        revision += 1
    }

    private static func pixelSize(of image: NSImage) -> CGSize? {
        let sizes = image.representations.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) }
        return sizes.max { $0.width * $0.height < $1.width * $1.height }
    }
}
