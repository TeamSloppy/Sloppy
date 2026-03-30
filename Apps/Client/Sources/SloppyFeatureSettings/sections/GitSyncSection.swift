import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct GitSyncSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var enabled: Bool
    @State private var repository: String
    @State private var branch: String
    @State private var frequency: String
    @State private var conflictStrategy: String

    private let frequencies = ["manual", "daily", "weekdays"]
    private let conflictStrategies = ["remote_wins", "local_wins", "manual"]

    init(config: SloppyConfig, onSave: @escaping (SloppyConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        let g = config.gitSync
        self._enabled = State(initialValue: g.enabled)
        self._repository = State(initialValue: g.repository)
        self._branch = State(initialValue: g.branch)
        self._frequency = State(initialValue: g.schedule.frequency)
        self._conflictStrategy = State(initialValue: g.conflictStrategy)
    }

    private var hasChanges: Bool {
        let g = config.gitSync
        return enabled != g.enabled || repository != g.repository || branch != g.branch ||
            frequency != g.schedule.frequency || conflictStrategy != g.conflictStrategy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            SectionHeader("Git Sync", accentColor: Theme.accentCyan)

            SettingsSectionCard("Sync Settings") {
                SettingsToggleRow(label: "Enabled", value: enabled) {
                    enabled.toggle()
                }
                SettingsDivider()
                SettingsFieldRow("Repository", hint: "owner/repo or https://github.com/owner/repo.git", text: $repository)
                SettingsDivider()
                SettingsFieldRow("Branch", hint: "Default: main", text: $branch)
            }

            SettingsSectionCard("Schedule") {
                VStack(alignment: .leading, spacing: Theme.spacingXS) {
                    Text("FREQUENCY")
                        .font(.system(size: Theme.fontMicro))
                        .foregroundColor(Theme.textSecondary)
                    HStack(spacing: Theme.spacingS) {
                        ForEach(frequencies, id: \.self) { freq in
                            Button(freq.replacingOccurrences(of: "_", with: " ").capitalized) {
                                frequency = freq
                            }
                            .font(.system(size: Theme.fontCaption))
                            .foregroundColor(frequency == freq ? Theme.textPrimary : Theme.textMuted)
                            .padding(.vertical, Theme.spacingXS)
                            .padding(.horizontal, Theme.spacingS)
                            .background(frequency == freq ? Theme.surfaceRaised : Color.clear)
                            .border(frequency == freq ? Theme.borderBold : Theme.border, lineWidth: Theme.borderThin)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, Theme.spacingM)
                .padding(.vertical, Theme.spacingS)
            }

            SettingsSectionCard("Conflict Strategy") {
                VStack(alignment: .leading, spacing: Theme.spacingXS) {
                    ForEach(conflictStrategies, id: \.self) { strategy in
                        Button(action: { conflictStrategy = strategy }) {
                            HStack {
                                Text(strategy.replacingOccurrences(of: "_", with: " ").uppercased())
                                    .font(.system(size: Theme.fontCaption))
                                    .foregroundColor(conflictStrategy == strategy ? Theme.textPrimary : Theme.textSecondary)
                                Spacer()
                                if conflictStrategy == strategy {
                                    Text("✓")
                                        .font(.system(size: Theme.fontCaption))
                                        .foregroundColor(Theme.statusDone)
                                }
                            }
                            .padding(.horizontal, Theme.spacingM)
                            .padding(.vertical, Theme.spacingS)
                            .background(conflictStrategy == strategy ? Theme.surfaceRaised : Color.clear)
                        }
                        if strategy != conflictStrategies.last {
                            SettingsDivider()
                        }
                    }
                }
            }

            SettingsSaveBar(
                hasChanges: hasChanges,
                statusText: hasChanges ? "Unsaved changes" : "Saved",
                onSave: { save() },
                onCancel: { reset() }
            )
        }
    }

    private func reset() {
        let g = config.gitSync
        enabled = g.enabled
        repository = g.repository
        branch = g.branch
        frequency = g.schedule.frequency
        conflictStrategy = g.conflictStrategy
    }

    private func save() {
        var updated = config
        updated.gitSync.enabled = enabled
        updated.gitSync.repository = repository
        updated.gitSync.branch = branch
        updated.gitSync.schedule.frequency = frequency
        updated.gitSync.conflictStrategy = conflictStrategy
        onSave(updated)
    }
}
