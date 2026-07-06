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
            .onChange(of: scope) { _, _ in bundle = nil; copied = false }

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

            Divider().opacity(0.4)
            mcpStatusFooter
        }
        .padding(20)
        .frame(width: 380)
        .background(Theme.background)
        .task {
            await model.refreshPsycheStatusFromDisk()
            await model.refreshServerRegistration()
        }
    }

    /// Persistent readout of whether the glia-context MCP will actually inject
    /// what the app writes — the trust signal for the loop.
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
                                 : "glia-context server: not detected — run mcp/install.sh")
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
