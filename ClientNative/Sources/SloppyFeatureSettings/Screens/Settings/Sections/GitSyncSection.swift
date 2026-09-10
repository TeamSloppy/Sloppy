import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct GitSyncSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var enabled: Bool
    @State private var authToken: String
    @State private var repository: String
    @State private var branch: String
    @State private var frequency: String
    @State private var syncTime: String
    @State private var conflictStrategy: String

    private let frequencies = ["manual", "daily", "weekdays"]
    private let conflictStrategies = ["remote_wins", "local_wins", "manual"]

    init(config: SloppyConfig, onSave: @escaping (SloppyConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        let g = config.gitSync
        self._enabled = State(initialValue: g.enabled)
        self._authToken = State(initialValue: g.authToken)
        self._repository = State(initialValue: g.repository)
        self._branch = State(initialValue: g.branch)
        self._frequency = State(initialValue: g.schedule.frequency)
        self._syncTime = State(initialValue: g.schedule.time)
        self._conflictStrategy = State(initialValue: g.conflictStrategy)
    }

    private var hasChanges: Bool {
        let g = config.gitSync
        return enabled != g.enabled || authToken != g.authToken || repository != g.repository || branch != g.branch ||
            frequency != g.schedule.frequency || syncTime != g.schedule.time || conflictStrategy != g.conflictStrategy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionCard("Sync Settings") {
                SettingsToggleRow(label: "Enabled", value: enabled) {
                    enabled.toggle()
                }
                SettingsDivider()
                SettingsFieldRow("Repository", hint: "owner/repo or https://github.com/owner/repo.git", text: $repository)
                SettingsDivider()
                SettingsFieldRow("Branch", hint: "Default: main", text: $branch)
                SettingsDivider()
                SettingsFieldRow("Auth Token", hint: "Optional GitHub PAT for private repositories", text: $authToken, isSecure: true)
            }

            SettingsSectionCard("Schedule") {
                Picker("Frequency", selection: $frequency) {
                    ForEach(frequencies, id: \.self) { frequency in
                        Text(frequency.capitalized).tag(frequency)
                    }
                }
                .pickerStyle(.segmented)
                .padding(16)
                SettingsDivider()
                SettingsFieldRow("Sync Time", hint: "UTC, HH:MM", text: $syncTime)
            }

            SettingsSectionCard("Conflict Strategy") {
                VStack(spacing: 8) {
                    ForEach(conflictStrategies, id: \.self) { strategy in
                        SettingsSelectionTile(
                            title: strategy.replacingOccurrences(of: "_", with: " ").capitalized,
                            subtitle: "", icon: "arrow.triangle.merge",
                            isSelected: conflictStrategy == strategy,
                            action: { conflictStrategy = strategy }
                        )
                    }
                }
                .padding(8)
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
        authToken = g.authToken
        repository = g.repository
        branch = g.branch
        frequency = g.schedule.frequency
        syncTime = g.schedule.time
        conflictStrategy = g.conflictStrategy
    }

    private func save() {
        var updated = config
        updated.gitSync.enabled = enabled
        updated.gitSync.authToken = authToken
        updated.gitSync.repository = repository
        updated.gitSync.branch = branch
        updated.gitSync.schedule.frequency = frequency
        updated.gitSync.schedule.time = syncTime
        updated.gitSync.conflictStrategy = conflictStrategy
        onSave(updated)
    }
}
