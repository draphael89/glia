import SwiftUI

/// Build a "who I am" context pack from a chosen region of the brain, see
/// its size in tokens, and copy or save it for injection into a new chat.
struct ContextExportSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var scope: ContextScope = .identity
    private var scopeEmpty: Bool {
        (scope == .selection && model.selectedIndex == nil)
        || (scope == .collection && model.starredCount == 0)
    }
    @State private var bundle: ContextBundle?
    @State private var building = false
    @State private var copied = false
    @State private var synced = 0
    @State private var previewTask = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(Theme.accent)
                Text("Export Context")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            Text("A map of your mind, ready to paste at the top of a new chat — telling the model who you are, not just what's relevant.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Scope", selection: $scope) {
                ForEach(ContextScope.allCases) { s in
                    Text(s == .collection ? "My collection (\(model.starredCount) starred)" : s.label)
                        .tag(s)
                }
            }
            .pickerStyle(.radioGroup)
            .onChange(of: scope) { _, _ in bundle = nil; copied = false; synced = 0 }

            if scope == .selection && model.selectedIndex == nil {
                hint("Select a node first to export its neighborhood.")
            } else if scope == .collection && model.starredCount == 0 {
                hint("Star nodes (⌘D, or the ☆ in the inspector) to build your collection.")
            }

            Divider().opacity(0.4)

            if let bundle {
                HStack(spacing: 16) {
                    stat("\(bundle.pageCount)", "pages")
                    stat(tokenLabel(bundle.tokenEstimate), "tokens")
                    Spacer()
                }
                HStack(spacing: 10) {
                    Button {
                        bundle.copyToPasteboard()
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    Button {
                        bundle.save()
                    } label: {
                        Label("Save .md", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
#if !MAS
                Button {
                    Task {
                        synced = await model.syncPsycheToMCP(scope: scope)
                        await model.refreshPsycheStatusFromDisk()
                    }
                } label: {
                    Label(synced > 0 ? "Synced \(synced) pages to MCP" : "Sync to glia-context MCP",
                          systemImage: synced > 0 ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .help("Write \(AppModel.psycheFileURL.path) so any agent using the glia-context MCP injects this")
#endif
            } else {
                Button {
                    building = true
                    Task {
                        let b = await model.buildContextBundleOffMain(scope)
                        bundle = b
                        building = false
                    }
                } label: {
                    HStack {
                        if building { ProgressView().controlSize(.small) }
                        Text(building ? "Building…" : "Build Context Pack")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(building || scopeEmpty)
            }

#if !MAS
            Divider().opacity(0.4)
            mcpStatusFooter
            injectionPreview
#endif
        }
        .padding(20)
        .frame(width: 380)
        .background(Theme.background)
#if !MAS
        .task {
            await model.refreshPsycheStatusFromDisk()
            await model.refreshServerRegistration()
        }
#endif
    }

#if !MAS
    /// Persistent readout of whether the glia-context MCP will actually inject
    /// what the app writes — the trust signal for the loop. (Direct build only:
    /// the sandboxed MAS build can't reach the real ~/.glia or Claude config.)
    @ViewBuilder private var mcpStatusFooter: some View {
        let reach = model.psycheReachability
        VStack(alignment: .leading, spacing: 4) {
            switch reach.file {
            case .usable:
                mcpLine("checkmark.seal.fill", Theme.accent,
                        "glia-context will inject this — \(AppModel.psycheFileURL.lastPathComponent), \(tokenLabel(reach.bytes / 4)) tokens" +
                        (reach.modified.map { " · updated \(relativePsycheTime($0))" } ?? ""))
            case .thin:
                mcpLine("exclamationmark.triangle.fill", .orange,
                        "psyche.md is thin — the MCP will fall back to building from your gbrain source. Sync a fuller collection.")
            case .missing:
                mcpLine("arrow.triangle.2.circlepath", .secondary,
                        "Not synced yet — the MCP builds from your gbrain source until you sync.")
            }
            Text("Live sync: \(model.psycheStatus.source.label)")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            if let registered = reach.serverRegistered {
                Text(registered ? "glia-context server: registered with Claude Code"
                                 : "glia-context server: not detected — open Enable MCP… to register it")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    private func mcpLine(_ symbol: String, _ color: Color, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10.5))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// See EXACTLY what the MCP would inject for a task (identity + retrieval).
    @ViewBuilder private var injectionPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Preview injection for a task…", text: $previewTask)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { Task { await model.previewInjection(task: previewTask) } }
                Button {
                    Task { await model.previewInjection(task: previewTask) }
                } label: {
                    if model.previewingInjection { ProgressView().controlSize(.small) }
                    else { Image(systemName: "eye").font(.system(size: 11)) }
                }
                .buttonStyle(.bordered)
                .disabled(previewTask.trimmingCharacters(in: .whitespaces).isEmpty || model.previewingInjection)
                .help("Run the glia-context server's preview for this task")
            }
            if let preview = model.injectionPreview {
                // Surface the core measured result — how much retrieval ADDED vs how
                // much your identity already covered (the complement/dedup thesis) —
                // as a legible header, not buried in 9.5pt gray monospace below.
                if let s = injectionSummary(preview) {
                    HStack(spacing: 6) {
                        previewChip("person.fill", "Identity \(s.identityTokens)")
                        previewChip("magnifyingglass", "\(s.pages) new page\(s.pages == 1 ? "" : "s")")
                        if s.deduped > 0 {
                            previewChip("arrow.triangle.merge", "\(s.deduped) already in identity")
                        }
                    }
                }
                ScrollView {
                    Text(preview)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .padding(6)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func previewChip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Theme.accent.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }

    /// Parse the stable summary lines of the `--explain` manifest:
    ///   `## Identity (file, ~23961 tok) — …`  and
    ///   `## Retrieval (ok, ~5890 tok, 6 pages, 8 deduped)`
    private func injectionSummary(_ text: String) -> (identityTokens: String, pages: Int, deduped: Int)? {
        func firstMatch(_ line: Substring, _ pattern: String) -> String? {
            guard let r = line.range(of: pattern, options: .regularExpression) else { return nil }
            return String(line[r])
        }
        var identity: String?
        var pages = 0, deduped = 0, sawRetrieval = false
        for line in text.split(separator: "\n") {
            if line.hasPrefix("## Identity") {
                if let m = firstMatch(line, #"~\d+ tok"#) {
                    identity = tokenLabel((Int(m.dropFirst().replacingOccurrences(of: " tok", with: "")) ?? 0))
                }
            } else if line.hasPrefix("## Retrieval") {
                sawRetrieval = true
                if let m = firstMatch(line, #"\d+ pages"#) { pages = Int(m.replacingOccurrences(of: " pages", with: "")) ?? 0 }
                if let m = firstMatch(line, #"\d+ deduped"#) { deduped = Int(m.replacingOccurrences(of: " deduped", with: "")) ?? 0 }
            }
        }
        guard identity != nil || sawRetrieval else { return nil }
        return (identity ?? "~0", pages, deduped)
    }
#endif

    private func hint(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(label).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }

    private func tokenLabel(_ n: Int) -> String {
        n >= 1000 ? String(format: "~%.0fk", Double(n) / 1000) : "~\(n)"
    }
}
