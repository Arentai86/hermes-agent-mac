import SwiftUI

/// Very first wizard step: shows the 11 supported languages by their native name so the user
/// can always recognize their language, regardless of which one is currently active.
struct LanguageStep: View {
    @ObservedObject var coordinator: WizardCoordinator
    @ObservedObject private var localization = AppLocalization.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Choose your language"))
                    .font(.system(size: 28, weight: .semibold))
                Text(L("Language"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(AppLocalization.supportedLanguages) { language in
                        Button {
                            localization.setLanguage(language.code)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: language.code == localization.languageCode ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(language.code == localization.languageCode ? Color.accentColor : .secondary)
                                    .frame(width: 18)
                                Text(language.nativeName)
                                    .font(.title3)
                                Spacer()
                                Text(language.code.uppercased())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(language.code == localization.languageCode ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(language.code == localization.languageCode ? Color.accentColor.opacity(0.08) : Color.clear)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(language.nativeName)
                    }
                }
            }
            .frame(minHeight: 240)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(L("Continue")) {
                    localization.setLanguage(localization.languageCode)
                    coordinator.next()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
    }
}
