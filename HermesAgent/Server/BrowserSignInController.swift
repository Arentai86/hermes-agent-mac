import AppKit
import Foundation
import SwiftUI

/// Drives the "open the browser, wait for the CLI session to appear" flow that backs the
/// account-style auth methods (Codex, Claude, Gemini, GitHub, ...).
///
/// Plain OAuth/PKCE with a localhost callback would require a client_id registered for every
/// provider, which is not workable for a free distribution. Instead we rely on the provider's
/// own CLI / desktop app: the user signs in once in the browser (or via `codex login`,
/// `gh auth login`, `gcloud auth login`, etc.), the CLI persists a credential file, and we
/// pick it up via `CLISessionDetector`.
@MainActor
final class BrowserSignInController: ObservableObject {
    enum Status: Equatable {
        case idle
        case waitingForCLI(providerID: String, since: Date)
        case detected(CLISessionDetector.Session)
        case notFound
        case timedOut
        case cancelled
    }

    @Published private(set) var status: Status = .idle

    private var pollTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 2
    private let timeout: TimeInterval = 240 // 4 minutes
    private let detector = CLISessionDetector()

    /// Opens the provider's sign-in URL in the user's default browser and starts polling
    /// for a CLI / desktop-app credential file. Completion is reported through `status`.
    func startSignIn(providerID: String, signInURL: URL) {
        cancelPolling()

        // If the session is already there, jump straight to "detected".
        if let session = detector.detect(providerID: providerID) {
            status = .detected(session)
            return
        }

        NSWorkspace.shared.open(signInURL)
        status = .waitingForCLI(providerID: providerID, since: Date())

        pollTask = Task { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(self.timeout)
            while !Task.isCancelled {
                if let session = self.detector.detect(providerID: providerID) {
                    self.status = .detected(session)
                    return
                }
                if Date() >= deadline {
                    self.status = .timedOut
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
            }
        }
    }

    /// Runs a one-shot detection without opening the browser. Used by the "I already signed
    /// in elsewhere" button so existing CLI users don't have to re-do the dance.
    func detectExisting(providerID: String) {
        cancelPolling()
        if let session = detector.detect(providerID: providerID) {
            status = .detected(session)
        } else {
            status = .notFound
        }
    }

    func cancelPolling() {
        pollTask?.cancel()
        pollTask = nil
        if case .waitingForCLI = status {
            status = .cancelled
        }
    }

    func reset() {
        cancelPolling()
        status = .idle
    }

    /// Convenience for the UI: returns the detected session, if any.
    var detectedSession: CLISessionDetector.Session? {
        if case let .detected(session) = status { return session }
        return nil
    }
}
