import AppKit
import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class UpdateManager: NSObject {
    #if canImport(Sparkle)
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    #endif

    static var configurationProblem: String? {
        guard let feedURLString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: feedURLString),
              feedURL.scheme?.lowercased() == "https" else {
            return "Sparkle feed URL is missing or is not HTTPS."
        }

        guard let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              publicKey.isEmpty == false,
              publicKey != "REPLACE_WITH_SPARKLE_PUBLIC_EDDSA_KEY",
              Data(base64Encoded: publicKey) != nil else {
            return "Sparkle public EdDSA key is not configured."
        }

        return nil
    }

    var isConfigured: Bool {
        Self.configurationProblem == nil
    }

    func checkForUpdates() {
        guard isConfigured else {
            let message = Self.configurationProblem ?? "Sparkle is not configured."
            NSLog("Hermes Agent updates disabled: \(message)")
            let alert = NSAlert()
            alert.messageText = "Updates are not configured"
            alert.informativeText = "Hermes Agent can run normally, but automatic updates need a real Sparkle EdDSA public key before release."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        #if canImport(Sparkle)
        updaterController.checkForUpdates(nil)
        #else
        NSLog("Sparkle is not linked. Resolve Swift Package dependencies to enable updates.")
        #endif
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            guard isConfigured else { return false }
            #if canImport(Sparkle)
            return updaterController.updater.automaticallyChecksForUpdates
            #else
            return false
            #endif
        }
        set {
            guard isConfigured else {
                NSLog("Hermes Agent automatic updates disabled: \(Self.configurationProblem ?? "Sparkle is not configured.")")
                return
            }
            #if canImport(Sparkle)
            updaterController.updater.automaticallyChecksForUpdates = newValue
            #endif
        }
    }
}
