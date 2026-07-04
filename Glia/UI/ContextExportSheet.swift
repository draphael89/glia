import SwiftUI

/// Build a "who I am" context pack from a chosen region of the brain, see
/// its size in tokens, and copy or save it for injection into a new chat.
struct ContextExportSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var scope: ContextScope = .identity
    @State private var bundle: ContextBundle?
    @State private var building = false
    @State private var copied = false

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
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.radioGroup)
            .disabled(scope == .selection && model.selectedIndex == nil)
            .onChange(of: scope) { _, _ in bundle = nil; copied = false }

            if scope == .selection && model.selectedIndex == nil {
                Label("Select a node first to export its neighborhood.",
                      systemImage: "info.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
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
            } else {
                Button {
                    building = true
                    Task {
                        let b = model.buildContextBundle(scope)
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
                .disabled(building || (scope == .selection && model.selectedIndex == nil))
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Theme.background)
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
