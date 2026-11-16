import Foundation
import ServiceManagement

/// Driftwood's place among the things macOS starts when the user logs in.
///
/// It is a launch agent in the user's own Library: a small file telling macOS to open this copy of
/// Driftwood at login. That works for an app built from source, which macOS's newer login-item
/// service does not reliably accept, and it needs no approval. The file is the whole of the state,
/// so removing it in Finder or System Settings turns the feature off here too.
enum LoginItem {
    private static let label = "local.driftwood.wallpaper.login"
    private static let launchArgument = "-launchedAtLogin"

    private static var agentFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// Whether macOS will open this copy of Driftwood when the user logs in.
    static var isEnabled: Bool {
        guard let agent = NSDictionary(contentsOf: agentFile), let arguments = agent["ProgramArguments"] as? [String] else { return false }
        return arguments.first == Bundle.main.executablePath
    }

    /// Whether this launch was started by macOS at login instead of by the user.
    static var launchedAtLogin: Bool { UserDefaults.standard.bool(forKey: "launchedAtLogin") }

    /// Turns opening at login on or off.
    ///
    /// - Returns: `true` if the change was made. `false` means the file could not be written or
    ///   removed; Driftwood carries on without the feature.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        // An earlier version registered with the login-item service; make sure that entry is gone
        // so Driftwood is never started twice.
        try? SMAppService.mainApp.unregister()
        do {
            guard enabled else {
                if FileManager.default.fileExists(atPath: agentFile.path) { try FileManager.default.removeItem(at: agentFile) }
                return true
            }
            guard let executable = Bundle.main.executablePath else { return false }
            let agent: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executable, launchArgument, "YES"],
                "RunAtLoad": true,
                "ProcessType": "Interactive"
            ]
            try FileManager.default.createDirectory(at: agentFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0).write(to: agentFile, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
