import AppKit
import Foundation

/// Terminal emulators that open a directory as the working directory of a new window when handed one
/// through Launch Services (`open -a <App> <dir>`).
struct TerminalApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }

    static let known: [TerminalApp] = [
        TerminalApp(bundleID: "com.apple.Terminal", name: "Terminal"),
        TerminalApp(bundleID: "com.googlecode.iterm2", name: "iTerm2"),
        TerminalApp(bundleID: "net.kovidgoyal.kitty", name: "kitty"),
        TerminalApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
        TerminalApp(bundleID: "com.github.wez.wezterm", name: "WezTerm"),
        TerminalApp(bundleID: "org.alacritty", name: "Alacritty"),
        TerminalApp(bundleID: "dev.warp.Warp-Stable", name: "Warp"),
    ]

    /// Where Launch Services finds the app, or nil when it is not installed.
    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    /// Known terminals present on this machine; Terminal.app is always first.
    static var installed: [TerminalApp] { known.filter { $0.url != nil } }

    /// The configured terminal if installed, else Terminal.app.
    static func resolve(bundleID: String) -> URL {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { return url }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
            ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
    }
}
