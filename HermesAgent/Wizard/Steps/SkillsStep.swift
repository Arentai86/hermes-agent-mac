import SwiftUI

struct SkillsStep: View {
    @ObservedObject var coordinator: WizardCoordinator
    @State private var skills: [OfficialSkill] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isInstalling = false
    @State private var errorMessage: String?
    @State private var summaryMessage: String?

    private let installer = OfficialSkillInstaller()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Official Skills"))
                    .font(.system(size: 28, weight: .semibold))
                Text(L("Choose which official Hermes Agent skills to install. You can install all of them or only the ones you need."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button(L("Select All")) {
                    selectedIDs = Set(skills.map(\.id))
                }
                Button(L("Clear Selection")) {
                    selectedIDs.removeAll()
                }
                Spacer()
                Text(LF("%d selected", selectedIDs.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            skillsList

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let summaryMessage {
                Label(summaryMessage, systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(L("Existing custom skills with the same folder name are kept and skipped."), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            WizardFooter(
                canGoBack: !isInstalling,
                canContinue: !isInstalling,
                continueTitle: continueTitle,
                onBack: coordinator.back,
                onContinue: installAndContinue
            )
        }
        .padding(28)
        .onAppear(perform: loadSkills)
    }

    private var skillsList: some View {
        Group {
            if skills.isEmpty, errorMessage == nil {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(L("Loading official skills..."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(skills) { skill in
                            skillRow(skill)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func skillRow(_ skill: OfficialSkill) -> some View {
        Button {
            toggle(skill.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selectedIDs.contains(skill.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selectedIDs.contains(skill.id) ? Color.accentColor : .secondary)
                    .frame(width: 20)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.name)
                        .font(.headline)
                    Text(skill.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedIDs.contains(skill.id) ? Color.accentColor.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(skill.name)
    }

    private var continueTitle: String {
        if isInstalling {
            return L("Installing...")
        }
        return selectedIDs.isEmpty ? L("Continue without Skills") : L("Install Skills & Continue")
    }

    private func loadSkills() {
        guard skills.isEmpty else { return }
        do {
            skills = try installer.availableSkills()
            selectedIDs = Set(skills.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func installAndContinue() {
        errorMessage = nil
        summaryMessage = nil
        isInstalling = true
        defer { isInstalling = false }

        do {
            let summary = try installer.install(skillIDs: selectedIDs)
            coordinator.markSkillsInstalled(selectedIDs)
            summaryMessage = LF("%d skills installed, %d skipped.", summary.installed, summary.skipped)
            coordinator.next()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
