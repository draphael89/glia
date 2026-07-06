import SwiftUI

/// One-click registration of the glia-context MCP with Claude Code + Claude
/// Desktop. The direct build can provision (spawn node/claude, write configs);
/// the sandboxed App Store build shows a guidance card instead.
struct EnableMCPSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
#if MAS
            masCard
#else
            liveBody
#endif
        }
        .padding(20)
        .frame(width: 400)
        .background(Theme.background)
        .task { await model.refreshMCPStatus() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles").foregroundStyle(Theme.accent)
            Text("Enable glia-context MCP").font(.system(size: 15, weight: .semibold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain).keyboardShortcut(.escape, modifiers: [])
        }
    }

    /// Shown in the sandboxed App Store build, which can't provision.
    private var masCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sandboxed build", systemImage: "lock.shield")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
            Text("The Mac App Store build can't modify Claude's configuration. Get the direct build for one-click setup, or run this in Terminal:")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("cd mcp && ./install.sh")
                .font(.system(size: 11, design: .monospaced))
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

#if !MAS
    private var s: MCPStatus { model.mcpStatus }

    @ViewBuilder private var liveBody: some View {
        Text("Register the MCP so any Claude session primes with who you are, plus what's relevant from your gbrain.")
            .font(.system(size: 11.5)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Divider().opacity(0.4)

        VStack(alignment: .leading, spacing: 9) {
            statusRow("terminal", "Node", nodeText, nodeOK)
            statusRow("curlybraces", "Claude Code", clientText(s.claudeCode, app: "Claude Code"), clientOK(s.claudeCode))
            statusRow("desktopcomputer", "Claude Desktop", desktopText, clientOK(s.claudeDesktop))
        }

        if case .needsNode = s.phase {
            Button("Install Node…") { NSWorkspace.shared.open(URL(string: "https://nodejs.org")!) }
                .font(.system(size: 11))
        }
        if case let .error(msg) = s.phase {
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.system(size: 10.5)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        if s.claudeDesktop == .registeredNeedsRestart {
            Label("Quit & reopen Claude Desktop to finish.", systemImage: "arrow.clockwise.circle")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }

        Button {
            Task { await model.enableMCP() }
        } label: {
            HStack {
                if s.phase == .working { ProgressView().controlSize(.small) }
                Text(enableLabel).frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent).tint(Theme.accent)
        .disabled(s.phase == .working)

        Text("Direct build only — writes ~/.claude.json and Claude Desktop's config. Or run `cd mcp && ./install.sh`.")
            .font(.system(size: 9.5)).foregroundStyle(.tertiary)
    }

    // state → text/ok
    private var nodeText: String {
        switch s.node {
        case .found(let p): return p
        case .missing: return "Not found — install Node to run the server"
        case .unknown: return "checking…"
        }
    }
    private var nodeOK: Bool? { if case .found = s.node { return true }; if case .missing = s.node { return false }; return nil }

    private func clientText(_ st: ClientState, app: String) -> String {
        switch st {
        case .registered, .registeredNeedsRestart: return "Registered"
        case .clientMissing: return "\(app) not installed"
        case .cliMissing: return "claude CLI not found — install Claude Code"
        case .failed(let m): return m
        case .unknown: return "Not registered yet"
        }
    }
    private var desktopText: String {
        if !s.desktopInstalled && s.claudeDesktop == .clientMissing { return "Not installed" }
        return clientText(s.claudeDesktop, app: "Claude Desktop")
    }
    private func clientOK(_ st: ClientState) -> Bool? {
        switch st {
        case .registered, .registeredNeedsRestart: return true
        case .failed: return false
        default: return nil
        }
    }
    private var enableLabel: String {
        switch s.phase {
        case .working: return "Enabling…"
        case .done: return "Re-enable MCP"
        default: return "Enable MCP"
        }
    }

    private func statusRow(_ symbol: String, _ title: String, _ detail: String, _ ok: Bool?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 16)
            Text(title).font(.system(size: 12, weight: .medium)).frame(width: 96, alignment: .leading)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.middle)
            Spacer(minLength: 4)
            Image(systemName: ok == true ? "checkmark.circle.fill" : (ok == false ? "xmark.circle.fill" : "circle.dotted"))
                .font(.system(size: 12))
                .foregroundStyle(ok == true ? Theme.accent : (ok == false ? Color.orange : Color.secondary))
        }
    }
#endif
}
