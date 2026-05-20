import Foundation
import SwiftUI

/// Active language selection for HermesAgent.
///
/// The class itself is intentionally NOT `@MainActor`: the global `L(_:)` / `LF(_:_:)` helpers
/// are called from any thread (e.g. ServerStatus.title from background callbacks), so the
/// lookup path must be nonisolated. Only `setLanguage(_:)` is `@MainActor` because it mutates
/// the `@Published` value which SwiftUI binds to.
///
/// The active language is persisted in `UserDefaults["selectedLanguage"]`, which is
/// thread-safe. `string(for:)` reads from UserDefaults directly so it can be called from any
/// actor without a Swift 6 isolation error. The `@Published var languageCode` exists purely
/// as a change-notification channel for SwiftUI; views observing it re-render when the user
/// picks a new language.
final class AppLocalization: ObservableObject {
    @MainActor
    static let shared = AppLocalization()

    /// 11 supported languages, listed in the order they appear in the picker. English first as
    /// the default, then the other ten requested by the user. `nativeName` is displayed in its
    /// own script so a user can always recognize their language even when the UI is in
    /// another one.
    static let supportedLanguages: [Language] = [
        Language(code: "en", nativeName: "English"),
        Language(code: "de", nativeName: "Deutsch"),
        Language(code: "fr", nativeName: "Français"),
        Language(code: "es", nativeName: "Español"),
        Language(code: "it", nativeName: "Italiano"),
        Language(code: "ru", nativeName: "Русский"),
        Language(code: "uk", nativeName: "Українська"),
        Language(code: "tr", nativeName: "Türkçe"),
        Language(code: "ar", nativeName: "العربية"),
        Language(code: "zh", nativeName: "中文"),
        Language(code: "ja", nativeName: "日本語")
    ]

    struct Language: Identifiable, Hashable {
        let code: String
        let nativeName: String
        var id: String { code }
    }

    @Published private(set) var languageCode: String

    private static let userDefaultsKey = "selectedLanguage"

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.userDefaultsKey),
           Self.supportedLanguages.contains(where: { $0.code == saved }) {
            self.languageCode = saved
        } else {
            self.languageCode = Self.detectSystemLanguage()
        }
    }

    /// True only when the user has explicitly picked a language. Used to decide whether to
    /// show the LanguageStep in the wizard. Reads UserDefaults directly so it is safe from
    /// any actor.
    var hasUserSelection: Bool {
        UserDefaults.standard.string(forKey: Self.userDefaultsKey) != nil
    }

    /// Changes the active language. `@MainActor` because writing `languageCode` triggers a
    /// `@Published` notification that SwiftUI needs on the main actor.
    @MainActor
    func setLanguage(_ code: String) {
        guard Self.supportedLanguages.contains(where: { $0.code == code }) else { return }
        UserDefaults.standard.set(code, forKey: Self.userDefaultsKey)
        if languageCode != code {
            languageCode = code
        }
    }

    @MainActor
    func resetSelectionToSystemLanguage() {
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
        let detected = Self.detectSystemLanguage()
        if languageCode != detected {
            languageCode = detected
        }
    }

    /// SwiftUI layout direction. Arabic is right-to-left; everything else is left-to-right.
    var layoutDirection: LayoutDirection {
        Self.layoutDirection(for: Self.activeLanguageCode)
    }

    /// Resolves a localization key into a string for the current language, falling back to
    /// the English source key if a translation is missing.
    func string(for key: String) -> String {
        Self.string(for: key)
    }

    /// Thread-safe accessor that does not touch the `@Published` storage. UserDefaults is
    /// safe to read from any thread.
    private static var activeLanguageCode: String {
        UserDefaults.standard.string(forKey: Self.userDefaultsKey)
            ?? Self.detectSystemLanguage()
    }

    /// Nonisolated lookup used by global `L(_:)` / `LF(_:_:)`. This intentionally avoids
    /// `AppLocalization.shared`, because Swift 6 treats ObservableObject state as main-actor
    /// UI state and global helpers are also called from nonisolated model code.
    static func string(for key: String) -> String {
        let code = activeLanguageCode
        if code == "en" { return key }
        if let table = AppTranslations.all[code], let value = table[key] {
            return value
        }
        return key
    }

    static var currentLayoutDirection: LayoutDirection {
        layoutDirection(for: activeLanguageCode)
    }

    private static func layoutDirection(for languageCode: String) -> LayoutDirection {
        languageCode == "ar" ? .rightToLeft : .leftToRight
    }

    private static func detectSystemLanguage() -> String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let lower = preferred.lowercased()
        // Match longest prefix first to handle e.g. "zh-Hant" → "zh".
        for language in supportedLanguages where language.code != "en" {
            if lower.hasPrefix(language.code) {
                return language.code
            }
        }
        return "en"
    }
}

/// Global helpers used everywhere in the UI. Both lookups go through the shared singleton so
/// changing the language live updates every view that observes AppLocalization (or AppState,
/// which mirrors the change via its objectWillChange publisher).
func L(_ key: String) -> String {
    AppLocalization.string(for: key)
}

func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: arguments)
}
