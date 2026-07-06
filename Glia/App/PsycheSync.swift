import Foundation

/// Trailing-edge debounce for the live psyche sync. `@MainActor` (hence
/// implicitly Sendable), Task-based cancel/sleep — Swift-6 strict-concurrency
/// clean on both arches: the only things captured into the `@Sendable` Task
/// body are `delay` (Sendable) and a `@Sendable @MainActor` operation.
@MainActor
final class Debouncer {
    private var task: Task<Void, Never>?
    private let delay: Duration
    init(delay: Duration) { self.delay = delay }

    /// Run `operation` after `delay`, cancelling any pending run. The op is
    /// `@MainActor` so it may freely touch model state; the sleep is a
    /// suspension, so it never blocks the main thread.
    func schedule(_ operation: @escaping @Sendable @MainActor () async -> Void) {
        task?.cancel()
        task = Task { [delay] in
            do { try await Task.sleep(for: delay) } catch { return } // cancelled → bail
            await operation()
        }
    }

    /// Cancel a pending run without firing (a manual sync supersedes it).
    func cancel() { task?.cancel(); task = nil }
}

/// Observable-friendly snapshot of the psyche→MCP sync, shown in the menu bar
/// and the Export sheet so the loop is visible and trustworthy.
struct PsycheSyncStatus: Sendable, Equatable {
    enum Phase: Sendable { case idle, pending, syncing, synced, failed, skipped }
    enum Source: String, Sendable {
        case collection, identity, custom
        var label: String {
            switch self {
            case .collection: return "starred collection"
            case .identity:   return "identity map"
            case .custom:     return "custom scope"
            }
        }
    }
    var phase: Phase = .idle
    var pageCount = 0
    var source: Source = .identity
    var fileModified: Date? = nil   // mtime of the file the MCP reads
    var fileBytes = 0
    var lastSyncedAt: Date? = nil
    /// Mirrors the server's own gate (loadPsyche: file exists AND trimmed > 200).
    var mcpWillUseFile: Bool { fileModified != nil && fileBytes > 200 }
    /// How the MCP will treat the file: inject it, treat it as thin, or fall back.
    var fileState: PsycheReachability.FileState {
        fileModified == nil ? .missing : (fileBytes > 200 ? .usable : .thin)
    }
}

/// Whether the MCP will actually inject the file the app writes (vs fall back
/// to building from the gbrain source), plus a best-effort registration signal.
struct PsycheReachability: Sendable {
    enum FileState: Sendable { case usable, thin, missing }
    var file: FileState
    var bytes: Int
    var modified: Date?
    var serverRegistered: Bool?   // nil = couldn't determine (sandbox / no config)
}

/// Compact relative time for the status line: "just now", "3m ago", "2h ago".
func relativePsycheTime(_ d: Date, now: Date = .now) -> String {
    let t = Int(now.timeIntervalSince(d))
    if t < 45 { return "just now" }
    if t < 3600 { return "\(t / 60)m ago" }
    if t < 86_400 { return "\(t / 3600)h ago" }
    return "\(t / 86_400)d ago"
}
