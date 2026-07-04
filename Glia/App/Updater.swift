import SwiftUI
import Sparkle

/// Sparkle auto-updates, feed-gated: with no SUFeedURL in Info.plist the
/// updater never starts and the menu item hides — so development and
/// unsigned builds carry zero update surface, and flipping releases on
/// is one plist key + the appcast.
@MainActor
final class UpdaterModel: ObservableObject {
    static let shared = UpdaterModel()

    let controller: SPUStandardUpdaterController?

    var isEnabled: Bool { controller != nil }

    private init() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        if let feed, !feed.isEmpty {
            controller = SPUStandardUpdaterController(startingUpdater: true,
                                                      updaterDelegate: nil,
                                                      userDriverDelegate: nil)
        } else {
            controller = nil
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

struct CheckForUpdatesCommand: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if UpdaterModel.shared.isEnabled {
                Button("Check for Updates…") {
                    UpdaterModel.shared.checkForUpdates()
                }
            }
        }
    }
}
