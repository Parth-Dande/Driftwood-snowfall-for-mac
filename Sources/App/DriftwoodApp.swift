import AppKit
import SwiftUI

/// The app: a gallery window and a menu bar item sharing one `Desktop`.
@main
struct DriftwoodApp: App {
    @State private var desktop = Desktop()

    var body: some SwiftUI.Scene {
        Window("Driftwood", id: "gallery") {
            Gallery(desktop: desktop)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Driftwood", systemImage: "cloud.moon") {
            StatusMenu(desktop: desktop)
        }
        .menuBarExtraStyle(.window)
    }
}
