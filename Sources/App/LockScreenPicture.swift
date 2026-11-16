import AppKit

/// Shows a scene's picture on the lock screen.
///
/// macOS draws the lock screen from the system desktop picture and lets no app draw there, so the
/// only way to carry a scene onto it is to make the scene's picture the desktop picture. The
/// pictures that were there before are remembered and put back when the scene goes away. The
/// weather itself cannot run on the lock screen.
@MainActor
enum LockScreenPicture {
    private static let savedPicturesKey = "desktopPicturesBeforeDriftwood"

    /// Makes the picture at `url` the desktop picture on every display.
    ///
    /// - Returns: `false` if macOS refused on any display. Driftwood then carries on without it.
    @discardableResult
    static func show(_ url: URL) -> Bool {
        var saved = UserDefaults.standard.dictionary(forKey: savedPicturesKey) as? [String: String] ?? [:]
        var succeeded = true
        for screen in NSScreen.screens {
            let id = String(screen.displayID)
            if saved[id] == nil, let current = NSWorkspace.shared.desktopImageURL(for: screen) { saved[id] = current.path }
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true
                ])
            } catch {
                succeeded = false
            }
        }
        UserDefaults.standard.set(saved, forKey: savedPicturesKey)
        return succeeded
    }

    /// Puts back the desktop pictures that were showing before Driftwood changed them.
    static func restore() {
        guard let saved = UserDefaults.standard.dictionary(forKey: savedPicturesKey) as? [String: String] else { return }
        for screen in NSScreen.screens {
            guard let path = saved[String(screen.displayID)] else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
        }
        UserDefaults.standard.removeObject(forKey: savedPicturesKey)
    }
}
