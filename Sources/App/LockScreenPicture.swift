import AppKit

/// Shows a scene's picture on the lock screen.
///
/// macOS draws the lock screen from the system desktop picture and lets no app draw there, so the
/// only way to carry a scene onto it is to make the scene's picture the desktop picture. The
/// weather itself cannot run on the lock screen.
///
/// macOS keeps a separate desktop picture for every display and every desktop, and only lets an
/// app set the one in view. So this is applied again whenever the displays change, the Mac wakes or
/// the user switches desktop, and each call puts right whatever it finds wrong.
@MainActor
enum LockScreenPicture {
    private static let savedPicturesKey = "desktopPicturesBeforeDriftwood"

    /// Makes the picture at `url` the desktop picture on every display, or, given `nil`, puts the
    /// user's own picture back on any display still showing one of Driftwood's.
    ///
    /// - Returns: `false` if macOS refused on any display. Driftwood then carries on without it.
    @discardableResult
    static func show(pictureAt url: URL?) -> Bool {
        var saved = UserDefaults.standard.dictionary(forKey: savedPicturesKey) as? [String: String] ?? [:]
        var succeeded = true
        for screen in NSScreen.screens {
            let id = String(screen.displayID)
            let current = NSWorkspace.shared.desktopImageURL(for: screen)
            // Remember what the user had, but never mistake one of Driftwood's pictures for it.
            if let current, !isDriftwoodPicture(current) { saved[id] = current.path }
            let wanted: URL
            if let url {
                wanted = url
            } else {
                guard let current, isDriftwoodPicture(current), let original = saved[id] else { continue }
                wanted = URL(fileURLWithPath: original)
            }
            guard current?.standardizedFileURL != wanted.standardizedFileURL else { continue }
            do {
                try NSWorkspace.shared.setDesktopImageURL(wanted, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true
                ])
            } catch {
                succeeded = false
            }
        }
        UserDefaults.standard.set(saved, forKey: savedPicturesKey)
        return succeeded
    }

    /// Puts the user's own picture back on every display still showing one of Driftwood's.
    @discardableResult
    static func restoreUserPicture() -> Bool { show(pictureAt: nil) }

    /// Whether `url` is a scene picture: bundled artwork from any copy of Driftwood, or one the user chose for a scene.
    private static func isDriftwoodPicture(_ url: URL) -> Bool {
        url.path.contains("/Driftwood.app/Contents/Resources/Artwork/")
            || url.path.contains("/Application Support/Driftwood/Wallpapers/")
    }
}
