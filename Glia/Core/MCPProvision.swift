import Foundation

// Sendable value types describing MCP provisioning state (observed by the sheet).

enum NodeState: Sendable, Equatable {
    case unknown, missing
    case found(String)
    var path: String? { if case let .found(p) = self { return p }; return nil }
}

enum ClientState: Sendable, Equatable {
    case unknown
    case registered
    case registeredNeedsRestart   // Claude Desktop only reads its config at launch
    case clientMissing            // the app isn't installed
    case cliMissing               // the `claude` CLI isn't on PATH
    case failed(String)

    var isRegistered: Bool {
        self == .registered || self == .registeredNeedsRestart
    }
}

struct MCPStatus: Sendable, Equatable {
    enum Phase: Sendable, Equatable { case idle, working, needsNode, done; case error(String) }
    var phase: Phase = .idle
    var node: NodeState = .unknown
    var claudeCode: ClientState = .unknown
    var claudeDesktop: ClientState = .unknown
    var desktopInstalled = false
    var distPath: String?
}

/// All Process/file work for registering the glia-context MCP with Claude Code
/// and Claude Desktop. `nonisolated` throughout: every non-Sendable object
/// (Process/Pipe/FileHandle) stays inside a single `Task.detached`, and only
/// Sendable structs/enums cross the actor hop — Swift-6 strict-concurrency clean.
enum MCPProvision {
    struct ShellResult: Sendable { let status: Int32; let stdout: String; let stderr: String }
    enum ProvisionError: LocalizedError {
        case noPayload
        var errorDescription: String? {
            switch self {
            case .noPayload: return "the glia-context server wasn't found (build it with `cd mcp && npm install && npm run build`, or run mcp/install.sh)"
            }
        }
    }

    // MARK: process

    /// Thread-safe holder for the two concurrent pipe drains. `@unchecked
    /// Sendable` with a lock; the reads run on UNSTRUCTURED tasks we can abandon.
    private final class DrainBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _out = Data(); private var _err = Data(); private var _done = 0
        func finishOut(_ d: Data) { lock.lock(); _out = d; _done += 1; lock.unlock() }
        func finishErr(_ d: Data) { lock.lock(); _err = d; _done += 1; lock.unlock() }
        var out: Data { lock.lock(); defer { lock.unlock() }; return _out }
        var err: Data { lock.lock(); defer { lock.unlock() }; return _err }
        var doneCount: Int { lock.lock(); defer { lock.unlock() }; return _done }
    }

    /// Run an executable and return a Sendable result. Drains stdout and stderr
    /// CONCURRENTLY (sequential draining deadlocks if the child fills one pipe
    /// buffer while we're blocked on the other), and bounds the wait by `timeout`
    /// — so even a fast-exiting child that leaves a grandchild holding the pipe
    /// write-ends can't hang us: we abandon the stuck reads and return.
    nonisolated static func runProcess(_ url: URL, _ args: [String], env extra: [String: String]? = nil,
                                       timeout: TimeInterval = 30) async -> ShellResult {
        await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = url
            p.arguments = args
            if let extra {
                var e = ProcessInfo.processInfo.environment
                extra.forEach { e[$0] = $1 }
                p.environment = e
            }
            let out = Pipe(); let err = Pipe()
            p.standardOutput = out; p.standardError = err
            do { try p.run() } catch { return ShellResult(status: -1, stdout: "", stderr: "\(error)") }

            let outHandle = out.fileHandleForReading
            let errHandle = err.fileHandleForReading
            let box = DrainBox()
            // Unstructured so they can be abandoned on timeout (a blocking read
            // is not cancellation-aware, so we must not structurally await it).
            Task.detached { box.finishOut(outHandle.readDataToEndOfFile()) }
            Task.detached { box.finishErr(errHandle.readDataToEndOfFile()) }

            let deadline = Date().addingTimeInterval(timeout)
            while box.doneCount < 2 && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(25))
            }
            let completed = box.doneCount >= 2
            if p.isRunning { p.terminate() }
            if completed { p.waitUntilExit() }
            return ShellResult(
                status: completed ? p.terminationStatus : -1,
                stdout: String(decoding: box.out, as: UTF8.self),
                stderr: completed ? String(decoding: box.err, as: UTF8.self)
                                  : "runProcess timed out after \(Int(timeout))s")
        }.value
    }

    /// A GUI-spawned process gets a minimal PATH where bare `node`/`claude`
    /// don't resolve, so ask the login shell first, then probe known locations.
    nonisolated static func resolveExecutable(_ name: String) async -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // `-l` (login) sources the profile for PATH, but NOT `-i` (interactive):
        // interactive rc files can background daemons that inherit our pipe and
        // keep the read from ever reaching EOF. The known-location probe below
        // covers the rare user whose PATH is set only in an interactive rc.
        let r = await runProcess(URL(fileURLWithPath: shell), ["-lc", "command -v \(name) 2>/dev/null || true"], timeout: 12)
        if let hit = r.stdout.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces),
           !hit.isEmpty, FileManager.default.isExecutableFile(atPath: hit) {
            return hit
        }
        let home = NSHomeDirectory()
        for p in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "\(home)/.local/bin/\(name)",
                  "/opt/homebrew/opt/node@22/bin/\(name)", "/usr/bin/\(name)"]
        where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return nil
    }

    /// Cheap synchronous node probe (no shell spawn) for the initial sheet status.
    nonisolated static func probeNodePath() -> String? {
        let home = NSHomeDirectory()
        for p in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "\(home)/.local/bin/node",
                  "/opt/homebrew/opt/node@22/bin/node", "/usr/bin/node"]
        where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return nil
    }

    // MARK: server payload

    /// Absolute path to a runnable `dist/index.js`, resolved in order:
    /// bundled payload (staged to a stable ~/.glia/mcp) → already-staged →
    /// an existing Claude Code registration that still points at a real file →
    /// GLIA_MCP_SRC dev source. Throws if none is available.
    nonisolated static func ensureStaged() async throws -> String {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let stageDir = home.appendingPathComponent(".glia/mcp")
        let staged = stageDir.appendingPathComponent("dist/index.js")

        if let res = Bundle.main.resourceURL?.appendingPathComponent("glia-context-mcp"),
           fm.fileExists(atPath: res.appendingPathComponent("dist/index.js").path) {
            return try await stageBundle(from: res, to: stageDir)
        }
        if fm.fileExists(atPath: staged.path) { return staged.path }
        if let existing = await existingRegisteredDist() { return existing }
        if let src = ProcessInfo.processInfo.environment["GLIA_MCP_SRC"], !src.isEmpty {
            let d = URL(fileURLWithPath: (src as NSString).expandingTildeInPath).appendingPathComponent("dist/index.js")
            if fm.fileExists(atPath: d.path) { return d.path }
        }
        throw ProvisionError.noPayload
    }

    /// Copy a bundled payload to the stable ~/.glia/mcp (survives app move /
    /// Sparkle update), re-copying only when the app version changed.
    nonisolated static func stageBundle(from res: URL, to dest: URL) async throws -> String {
        try await Task.detached {
            let fm = FileManager.default
            let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            let marker = dest.appendingPathComponent(".staged-version")
            let current = try? String(contentsOf: marker, encoding: .utf8)
            let distExists = fm.fileExists(atPath: dest.appendingPathComponent("dist/index.js").path)
            if current != version || !distExists {
                // Stage into a temp sibling, then swap atomically — so a failed
                // copy never destroys the live ~/.glia/mcp the clients point at.
                let parent = dest.deletingLastPathComponent()
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                // Unique per invocation: two provisioning flows (Enable-MCP + injection
                // preview) staging the same new version concurrently must not share — and
                // thus delete — each other's temp mid-copy (a spurious "couldn't prepare
                // server"). defer-clean so a failed stage never leaks a temp dir.
                let tmp = parent.appendingPathComponent(".mcp-staging-\(version)-\(UUID().uuidString)")
                defer { try? fm.removeItem(at: tmp) }
                try fm.copyItem(at: res, to: tmp)
                try? version.write(to: tmp.appendingPathComponent(".staged-version"), atomically: true, encoding: .utf8)
                if fm.fileExists(atPath: dest.path) {
                    _ = try fm.replaceItemAt(dest, withItemAt: tmp)   // atomic; old removed only on success
                } else {
                    try fm.moveItem(at: tmp, to: dest)
                }
            }
            return dest.appendingPathComponent("dist/index.js").path
        }.value
    }

    /// Reuse a dist path from an existing Claude Code registration if the file
    /// still exists (lets an already-set-up machine register Desktop with no bundle).
    nonisolated static func existingRegisteredDist() async -> String? {
        await Task.detached {
            let cfg = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
            guard let d = try? Data(contentsOf: cfg),
                  let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let servers = root["mcpServers"] as? [String: Any],
                  let g = servers["glia-context"] as? [String: Any],
                  let args = g["args"] as? [String], let dist = args.last,
                  FileManager.default.fileExists(atPath: dist)
            else { return nil }
            return dist
        }.value
    }

    // MARK: client registration

    /// Register Claude Code at user scope via the CLI (remove-then-add is
    /// idempotent; `-s user` BEFORE the name, matching `claude mcp add --help`).
    nonisolated static func registerClaudeCode(node: String, dist: String, claude: String) async -> ClientState {
        _ = await runProcess(URL(fileURLWithPath: claude), ["mcp", "remove", "-s", "user", "glia-context"])
        let r = await runProcess(URL(fileURLWithPath: claude), ["mcp", "add", "-s", "user", "glia-context", node, dist])
        return r.status == 0 ? .registered : .failed(r.stderr.isEmpty ? r.stdout : r.stderr)
    }

    /// PURE + testable: merge glia-context into a Claude-Desktop-shaped JSON,
    /// preserving all other keys and mcpServers siblings. Absolute node/dist
    /// (the GUI PATH is minimal). Returns nil only on an encode failure.
    nonisolated static func mergeDesktopConfig(existing: Data?, node: String, dist: String) -> Data? {
        var root: [String: Any] = [:]
        if let data = existing, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = obj
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers["glia-context"] = ["command": node, "args": [dist]]
        root["mcpServers"] = servers
        return try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    nonisolated static func isParseableJSON(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    /// READ-MERGE-WRITE the Claude Desktop config (never clobber other keys /
    /// servers). If the file exists but is unparseable, back it up and ABORT
    /// rather than destroy it.
    nonisolated static func registerClaudeDesktop(node: String, dist: String, desktopInstalled: Bool) async -> ClientState {
        guard desktopInstalled else { return .clientMissing }
        return await Task.detached {
            let fm = FileManager.default
            let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
            let cfg = dir.appendingPathComponent("claude_desktop_config.json")
            let fileExists = fm.fileExists(atPath: cfg.path)
            let existing = try? Data(contentsOf: cfg)

            // Exists but unreadable → don't risk clobbering it.
            if fileExists && existing == nil {
                return .failed("Claude Desktop config exists but couldn't be read (permissions?) — not modified")
            }
            // Present but not a valid JSON OBJECT (unparseable, or an array/scalar),
            // or its mcpServers isn't an object → back up and ABORT, never destroy.
            if let existing {
                let obj = try? JSONSerialization.jsonObject(with: existing)
                let dict = obj as? [String: Any]
                let mcpBad = (dict?["mcpServers"]).map { !($0 is [String: Any]) } ?? false
                if obj == nil || dict == nil || mcpBad {
                    try? fm.copyItem(at: cfg, to: cfg.appendingPathExtension("glia-backup"))
                    return .failed("existing Claude Desktop config isn't a JSON object we can safely merge — backed up to .glia-backup, not modified")
                }
            }
            guard let out = mergeDesktopConfig(existing: existing, node: node, dist: dist) else {
                return .failed("couldn't encode config")
            }
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                // Write to the symlink TARGET, not the link. An atomic write is
                // temp-file + rename(), which would replace a symlinked config
                // (dotfiles setups) with a regular file and silently break the link.
                let writeTarget = cfg.resolvingSymlinksInPath()
                try out.write(to: writeTarget, options: .atomic)
            } catch { return .failed("\(error)") }
            return .registeredNeedsRestart
        }.value
    }

    /// Run the registered server's `--explain` CLI to preview EXACTLY what
    /// prime_context would inject for a task (identity sections + retrieved pages
    /// + tokens). Returns the manifest text, or nil if node/the server isn't ready.
    nonisolated static func previewInjection(task: String) async -> String? {
        guard let node = await resolveExecutable("node") else { return nil }
        let dist: String
        do { dist = try await ensureStaged() } catch { return nil }
        let r = await runProcess(URL(fileURLWithPath: node), [dist, "--explain", task], timeout: 20)
        return r.status == 0 && !r.stdout.isEmpty ? r.stdout : nil
    }

    // MARK: status (fast, no spawning)

    /// Read both client configs + cheap-probe node for the initial sheet state.
    nonisolated static func currentStatus(desktopInstalled: Bool) async -> MCPStatus {
        await Task.detached {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            var st = MCPStatus()
            st.desktopInstalled = desktopInstalled
            st.node = probeNodePath().map { NodeState.found($0) } ?? .unknown

            // Only report "registered" if glia-context is present AND its recorded
            // dist still exists on disk — a substring match would show green for a
            // stale registration pointing at a deleted/moved dist (which won't run).
            func registeredAndUsable(_ url: URL) -> Bool {
                guard let d = try? Data(contentsOf: url),
                      let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let servers = root["mcpServers"] as? [String: Any],
                      let g = servers["glia-context"] as? [String: Any],
                      let args = g["args"] as? [String], let dist = args.last else { return false }
                return fm.fileExists(atPath: dist)
            }
            st.claudeCode = registeredAndUsable(home.appendingPathComponent(".claude.json")) ? .registered : .unknown
            if desktopInstalled {
                st.claudeDesktop = registeredAndUsable(home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json"))
                    ? .registered : .unknown
            } else {
                st.claudeDesktop = .clientMissing
            }
            return st
        }.value
    }
}
