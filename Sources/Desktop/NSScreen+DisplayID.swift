import AppKit
import CoreGraphics

extension NSScreen {
    /// The Core Graphics identifier of this screen's display.
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }

    /// Screen frame in Quartz coordinates (origin at the top-left of the primary display).
    ///
    /// - Complexity: O(n), where n is the number of connected displays.
    var quartzFrame: CGRect {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
        let primaryHeight = primary?.frame.height ?? frame.height
        return CGRect(
            x: frame.origin.x,
            y: primaryHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    /// The screen's size in device pixels.
    var backingPixelSize: CGSize {
        CGSize(width: frame.width * backingScaleFactor, height: frame.height * backingScaleFactor)
    }
}
