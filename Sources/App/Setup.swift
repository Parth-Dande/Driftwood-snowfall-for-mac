import AppKit

/// The questions Driftwood asks the first time it is opened.
///
/// Everything here is optional. Whatever the user declines, or macOS refuses, is simply left off,
/// and each choice can be changed later from the menu bar item.
@MainActor
enum Setup {
    private static let completedKey = "hasCompletedSetup"

    /// Asks once what Driftwood may do, and applies the answers to `desktop`.
    static func offerOnFirstLaunch(for desktop: Desktop) {
        guard !UserDefaults.standard.bool(forKey: completedKey) else { return }
        UserDefaults.standard.set(true, forKey: completedKey)

        let login = NSButton(checkboxWithTitle: "Open at login and keep running in the background", target: nil, action: nil)
        let lockScreen = NSButton(checkboxWithTitle: "Show the scene\u{2019}s picture on the lock screen", target: nil, action: nil)
        login.state = .on
        lockScreen.state = .on
        let note = NSTextField(wrappingLabelWithString:
            "The lock screen shows the picture only: macOS does not let the weather run there. "
            + "Your current desktop picture is put back when you clear the scene or quit Driftwood.")
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 340
        let choices = NSStackView(views: [login, lockScreen, note])
        choices.orientation = .vertical
        choices.alignment = .leading
        choices.spacing = 8
        choices.frame.size = choices.fittingSize

        let alert = NSAlert()
        alert.messageText = "Let Driftwood…"
        alert.informativeText = "Choose what Driftwood may do. You can change either from its menu bar item at any time."
        alert.accessoryView = choices
        alert.addButton(withTitle: "Continue")
        alert.runModal()

        desktop.opensAtLogin = login.state == .on
        desktop.showsOnLockScreen = lockScreen.state == .on
    }
}
