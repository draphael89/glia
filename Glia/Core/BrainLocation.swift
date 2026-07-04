import AppKit
import Foundation

/// Where the brain lives on disk. Resolution order:
///   1. GLIA_DATA env override (dev/tests)
///   2. Demo mode (bundled synthetic brain)
///   3. Security-scoped bookmark (sandbox-safe, user-chosen .gbrain folder)
///   4. ~/.gbrain (direct builds running unsandboxed)
@MainActor
enum BrainLocation {
    private static let bookmarkKey = "brainFolderBookmark"
    private(set) static var demoMode = false
    private static var scopedFolder: URL?

    static func startUp() {
        guard scopedFolder == nil,
              let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &stale),
           url.startAccessingSecurityScopedResource() {
            scopedFolder = url
            if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
        }
    }

    /// The .gbrain-style home folder currently in effect (nil in demo mode).
    static var home: URL? {
        if demoMode { return nil }
        if let env = ProcessInfo.processInfo.environment["GLIA_DATA"] {
            // env points at graph.json; home is <parent-of-viz>
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
                .deletingLastPathComponent().deletingLastPathComponent()
        }
        if let scopedFolder { return scopedFolder }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gbrain")
    }

    static var graphURL: URL? {
        if demoMode {
            return Bundle.main.url(forResource: "DemoBrain", withExtension: "json")
        }
        if let env = ProcessInfo.processInfo.environment["GLIA_DATA"] {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        }
        return home?.appendingPathComponent("viz/graph.json")
    }

    /// Markdown mirror directory for a source id, when one exists on disk.
    static func sourceMirror(for sourceID: String) -> URL? {
        guard !demoMode,
              sourceID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return home?.appendingPathComponent("source-\(sourceID)")
    }

    static func enterDemoMode() { demoMode = true }
    static func exitDemoMode() { demoMode = false }

    /// Sandbox-safe folder selection; persists a security-scoped bookmark.
    static func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Choose your gbrain home folder (usually ~/.gbrain)"
        panel.prompt = "Use This Folder"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        scopedFolder?.stopAccessingSecurityScopedResource()
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        }
        _ = url.startAccessingSecurityScopedResource()
        scopedFolder = url
        demoMode = false
        return true
    }
}
