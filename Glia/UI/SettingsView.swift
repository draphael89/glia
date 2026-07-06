import SwiftUI

/// The ⌘, Preferences window. Glia is a viewer, so this is the ONE place that
/// gathers the MCP integration (status + one-click actions) and the retrieval /
/// injection tuning knobs. The knobs are written to ~/.glia/config.json, which the
/// glia-context server layers under real env vars and reads on its next spawn — so
/// tuning takes effect without re-registering the server.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            MCPSettingsTab(model: model)
                .tabItem { Label("MCP", systemImage: "sparkles") }
            TuningSettingsTab()
                .tabItem { Label("Retrieval", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 480, height: 430)
    }
}

// MARK: - MCP status + actions

private struct MCPSettingsTab: View {
    @Bindable var model: AppModel

    var body: some View {
#if MAS
        VStack(spacing: 10) {
            Image(systemName: "lock.shield").font(.system(size: 26)).foregroundStyle(.secondary)
            Text("The MCP integration isn't available in the App Store build")
                .font(.system(size: 13, weight: .medium))
            Text("The sandboxed build can't reach ~/.glia or your Claude config. Use the direct download to prime Claude sessions with your identity + brain.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 320)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
#else
        Form {
            Section("Registration") {
                statusRow("Node", detail: model.mcpStatus.node.path ?? "not found — install Node",
                          ok: model.mcpStatus.node.path != nil)
                statusRow("Claude Code", detail: label(model.mcpStatus.claudeCode),
                          ok: model.mcpStatus.claudeCode.isRegistered)
                if model.mcpStatus.desktopInstalled {
                    statusRow("Claude Desktop", detail: label(model.mcpStatus.claudeDesktop),
                              ok: model.mcpStatus.claudeDesktop.isRegistered)
                }
            }
            Section("Identity (psyche.md)") {
                let r = model.psycheReachability
                statusRow(scopeLabel, detail: fileDetail(r), ok: r.file == .usable)
            }
            Section("Retrieval completeness") {
                HStack(spacing: 8) {
                    if let h = model.retrievalHealth {
                        Image(systemName: h.contains("✓") ? "checkmark.circle.fill"
                                        : (h.contains("live-fetched") ? "arrow.down.circle.fill" : "exclamationmark.triangle"))
                            .foregroundStyle(h.contains("✓") ? Color.green
                                           : (h.contains("live-fetched") ? Theme.accent : .orange))
                        Text(h).font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Check whether your local mirror covers the pages retrieval ranks top.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.checkingRetrieval ? "Checking…" : "Check") {
                        Task { await model.checkRetrievalHealth() }
                    }
                    .disabled(model.checkingRetrieval)
                }
            }
            Section {
                HStack(spacing: 10) {
                    Button(anyRegistered ? "Re-register" : "Enable MCP") {
                        Task { await model.enableMCP() }
                    }
                    .disabled(model.mcpStatus.phase == .working)
                    Button("Sync Now") { Task { _ = await model.syncPsycheToMCP() } }
                    Button("Export Context…") { model.contextExportVisible = true }
                    Spacer()
                    if model.mcpStatus.phase == .working { ProgressView().controlSize(.small) }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await model.refreshMCPStatus()
            await model.refreshServerRegistration()
            await model.refreshPsycheStatusFromDisk()
        }
#endif
    }

    private var anyRegistered: Bool {
        model.mcpStatus.claudeCode.isRegistered || model.mcpStatus.claudeDesktop.isRegistered
    }
    private var scopeLabel: String { "Scope: " + model.psycheStatus.source.label }

    private func fileDetail(_ r: PsycheReachability) -> String {
        switch r.file {
        case .usable:  return "\(AppModel.psycheFileURL.lastPathComponent) · \(r.bytes / 4) tok · \(model.psycheStatus.pageCount) pages"
        case .missing: return "not synced yet — builds from your gbrain source until you sync"
        case .thin:    return "present but thin — Sync to populate it"
        }
    }
    private func label(_ s: ClientState) -> String {
        switch s {
        case .registered: return "Registered"
        case .registeredNeedsRestart: return "Registered — restart Claude Desktop"
        case .clientMissing: return "not installed"
        case .cliMissing: return "the `claude` CLI isn't on PATH"
        case .failed(let m): return m
        case .unknown: return "not registered"
        }
    }

    @ViewBuilder
    private func statusRow(_ title: String, detail: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Color.green : .secondary)
            Text(title)
            Spacer()
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
    }
}

// MARK: - Retrieval / injection tuning (written to ~/.glia/config.json)

enum TuningConfig {
    static let dFallback = 8, dPsycheCore = 24_000, dConcurrency = 4
    static let dRelFloor = 0.5

    /// ~/.glia/config.json — the default path the glia-context server reads (it also
    /// honors GLIA_CONFIG). Env vars still override it, so power users aren't boxed in.
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".glia/config.json")
    }

    static func write(fallbackMax: Int, psycheCore: Int, relFloor: Double, concurrency: Int) {
        // MERGE into any existing config.json — never drop keys the UI doesn't manage.
        // config.ts reads several more from this same file (GBRAIN_TIMEOUT_MS, the cache
        // TTLs, GBRAIN_MAX_PAGE_BYTES, GLIA_PSYCHE_MAX_BYTES); a full replace would wipe a
        // user's hand-set values. Keys are the server's env-var names.
        let url = fileURL
        var payload: [String: Any] = {
            guard let data = try? Data(contentsOf: url), data.count < 1_000_000,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return obj
        }()
        payload["GBRAIN_GET_FALLBACK_MAX"] = fallbackMax
        payload["GLIA_PSYCHE_CORE_MAX_TOKENS"] = psycheCore
        payload["GBRAIN_REL_SCORE_FLOOR"] = relFloor
        payload["GBRAIN_GET_CONCURRENCY"] = concurrency
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// The values currently on disk (numbers only), or nil if absent/unreadable — so the
    /// panel reflects the REAL config.json rather than overwriting it on open.
    static func read() -> [String: NSNumber]? {
        guard let data = try? Data(contentsOf: fileURL), data.count < 1_000_000,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj.compactMapValues { $0 as? NSNumber }
    }
}

private struct TuningSettingsTab: View {
    @AppStorage("glia.tuning.fallbackMax") private var fallbackMax = TuningConfig.dFallback
    @AppStorage("glia.tuning.psycheCore") private var psycheCore = TuningConfig.dPsycheCore
    @AppStorage("glia.tuning.relFloor") private var relFloor = TuningConfig.dRelFloor
    @AppStorage("glia.tuning.concurrency") private var concurrency = TuningConfig.dConcurrency
    /// Set while load() hydrates from disk, so the resulting onChange cascade doesn't
    /// persist (which would clobber a hand-set on-disk value with the clamped one).
    @State private var isLoading = false

    var body: some View {
        Form {
            Section {
                Stepper(fallbackMax == 0 ? "Completeness fallback: **off**" : "Completeness fallback: **\(fallbackMax)** pages",
                        value: $fallbackMax, in: 0...16)
                Stepper("Parallel fetches: **\(concurrency)**", value: $concurrency, in: 1...8)
            } header: { Text("Retrieval") } footer: {
                Text("The local mirror is a subset of your brain, so top-ranked pages can be missing. This is how many to re-read live from the full brain (measured: raises top-page completeness 31%→99%; 0 = off), and how many at once. Higher = more complete, slightly slower.")
            }
            Section {
                Stepper("Identity core: **\(psycheCore / 1000)k** tokens", value: $psycheCore, in: 4_000...24_000, step: 2_000)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Relevance floor: **\(relFloor, format: .number.precision(.fractionLength(2)))**")
                    Slider(value: $relFloor, in: 0...1)
                }
            } header: { Text("Injection") } footer: {
                Text("The identity core in ‘both’ mode is capped at 40% of the token budget (24k under the default), so 24k is the validated best — lowering it trades identity for more retrieval room (v10 found that generally worse). And the minimum relevance — as a fraction of the top page — for a retrieved page to be injected.")
            }
            Section {
                HStack {
                    Button("Reset to defaults") {
                        fallbackMax = TuningConfig.dFallback; psycheCore = TuningConfig.dPsycheCore
                        relFloor = TuningConfig.dRelFloor; concurrency = TuningConfig.dConcurrency
                    }
                    Spacer()
                    Text("Applies next time a Claude session starts the server.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)      // reflect the real config.json — never clobber it on open
        .onChange(of: fallbackMax) { _, _ in persist() }
        .onChange(of: psycheCore) { _, _ in persist() }
        .onChange(of: relFloor) { _, _ in persist() }
        .onChange(of: concurrency) { _, _ in persist() }
    }

    /// Load the on-disk values into the controls (clamped to the UI ranges) so the panel
    /// shows what the server will actually use. A missing file keeps the @AppStorage
    /// values, which equal the server defaults. We do NOT write here — and we suppress the
    /// onChange cascade these assignments cause, so opening the tab can't clobber the file.
    /// Ranges match config.ts's accepted domains (fallback 0 = off; floor 0…1) so a
    /// hand-set sentinel isn't silently narrowed.
    private func load() {
        guard let d = TuningConfig.read() else { return }
        isLoading = true
        if let n = d["GBRAIN_GET_FALLBACK_MAX"] { fallbackMax = min(max(n.intValue, 0), 16) }
        if let n = d["GBRAIN_GET_CONCURRENCY"] { concurrency = min(max(n.intValue, 1), 8) }
        if let n = d["GLIA_PSYCHE_CORE_MAX_TOKENS"] { psycheCore = min(max(n.intValue, 4_000), 24_000) }
        if let n = d["GBRAIN_REL_SCORE_FLOOR"] { relFloor = min(max(n.doubleValue, 0), 1) }
        DispatchQueue.main.async { isLoading = false }   // after the onChange handlers run
    }

    private func persist() {
        guard !isLoading else { return }   // don't write while hydrating from disk
        TuningConfig.write(fallbackMax: fallbackMax, psycheCore: psycheCore, relFloor: relFloor, concurrency: concurrency)
    }
}
