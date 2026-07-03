import AppIntents
import SwiftUI

/// "Show <page> in Glia" — usable from Shortcuts, Spotlight, and Siri.
struct OpenBrainNodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Brain Page"
    static let description = IntentDescription(
        "Opens Glia and flies the camera to a page in your brain.")
    static let openAppWhenRun = true

    @Parameter(title: "Page", description: "Slug or title to search for")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let model = AppModel.shared else { return .result() }
        let q = query.lowercased()
        if let i = model.graph.nodes.firstIndex(where: {
            $0.slug.lowercased().contains(q) || $0.title.lowercased().contains(q)
        }) {
            model.select(index: i)
        } else {
            model.searchText = query
            model.paletteVisible = true
        }
        return .result()
    }
}

struct GliaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Free-form String parameters can't appear in invocation phrases
        // (AppEntity/AppEnum only) — Shortcuts prompts for the page instead.
        AppShortcut(
            intent: OpenBrainNodeIntent(),
            phrases: ["Search my brain in \(.applicationName)"],
            shortTitle: "Show Brain Page",
            systemImageName: "brain.head.profile"
        )
    }
}
