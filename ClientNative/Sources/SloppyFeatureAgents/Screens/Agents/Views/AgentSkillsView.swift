import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

private enum AgentSkillsSection: String, CaseIterable {
    case installed
    case catalog

    var title: String {
        switch self {
        case .installed: "Installed"
        case .catalog: "Catalog"
        }
    }
}

struct AgentSkillsView: View {
    let agent: APIAgentRecord
    let apiClient: SloppyAPIClient

    @Environment(\.theme) private var theme
    @State private var section: AgentSkillsSection = .installed
    @State private var installedSkills: [InstalledAgentSkill] = []
    @State private var catalogSkills: [SkillRegistryItem] = []
    @State private var catalogTotal = 0
    @State private var searchText = ""
    @State private var isLoadingInstalled = true
    @State private var isLoadingCatalog = true
    @State private var changingSkillID: String?
    @State private var pendingRemoval: InstalledAgentSkill?
    @State private var errorMessage: String?

    private var installedIDs: Set<String> {
        Set(installedSkills.map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            skillsToolbar
            Divider().overlay(theme.colors.border)

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.m) {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(theme.colors.statusWarning)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.colors.statusWarning.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    switch section {
                    case .installed:
                        installedContent
                    case .catalog:
                        catalogContent
                    }
                }
                .padding(theme.spacing.l)
            }
        }
        .task(id: agent.id) {
            await loadInstalled()
            await loadCatalog(search: searchText)
        }
        .task(id: searchText) {
            guard section == .catalog else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await loadCatalog(search: searchText)
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "skill")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove skill", role: .destructive) {
                guard let skill = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await uninstall(skill) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("The skill will be removed from \(agent.displayName). You can install it again later.")
        }
    }

    private var skillsToolbar: some View {
        HStack(spacing: theme.spacing.m) {
            HStack(spacing: 2) {
                ForEach(AgentSkillsSection.allCases, id: \.self) { item in
                    Button {
                        section = item
                    } label: {
                        Text(item == .installed ? "\(item.title) (\(installedSkills.count))" : item.title)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(section == item ? theme.colors.textPrimary : theme.colors.textSecondary)
                            .background(section == item ? theme.colors.surfaceRaised : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            if section == .catalog {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.colors.textMuted)
                    TextField("Search skills", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(minWidth: 160, maxWidth: 260)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(theme.colors.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(theme.colors.border, lineWidth: 1) }
            }
        }
        .padding(.horizontal, theme.spacing.l)
        .padding(.vertical, theme.spacing.s)
    }

    @ViewBuilder
    private var installedContent: some View {
        if isLoadingInstalled && installedSkills.isEmpty {
            ProgressView("Loading installed skills…")
                .frame(maxWidth: .infinity, minHeight: 240)
        } else if installedSkills.isEmpty {
            ContentUnavailableView(
                "No skills installed",
                systemImage: "sparkles",
                description: Text("Open the catalog to add capabilities to this agent.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            Button("Browse catalog") { section = .catalog }
                .buttonStyle(.borderedProminent)
                .tint(theme.colors.accent)
                .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: theme.spacing.m, alignment: .top)], spacing: theme.spacing.m) {
                ForEach(installedSkills) { skill in
                    InstalledSkillCard(
                        skill: skill,
                        isWorking: changingSkillID == skill.id,
                        onRemove: { pendingRemoval = skill }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var catalogContent: some View {
        if isLoadingCatalog && catalogSkills.isEmpty {
            ProgressView("Searching the catalog…")
                .frame(maxWidth: .infinity, minHeight: 240)
        } else if catalogSkills.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "Catalog unavailable" : "No matching skills",
                systemImage: searchText.isEmpty ? "wifi.exclamationmark" : "magnifyingglass",
                description: Text(searchText.isEmpty ? "Try refreshing the catalog later." : "Try a broader search term.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
        } else {
            Text("\(catalogTotal) skills available")
                .font(.caption)
                .foregroundStyle(theme.colors.textMuted)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: theme.spacing.m, alignment: .top)], spacing: theme.spacing.m) {
                ForEach(catalogSkills) { skill in
                    CatalogSkillCard(
                        skill: skill,
                        isInstalled: installedIDs.contains(skill.id),
                        isWorking: changingSkillID == skill.id,
                        onInstall: { Task { await install(skill) } }
                    )
                }
            }
        }
    }

    private func loadInstalled() async {
        isLoadingInstalled = true
        defer { isLoadingInstalled = false }
        do {
            installedSkills = try await apiClient.fetchAgentSkills(agentId: agent.id).skills
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Installed skills could not be loaded."
        }
    }

    private func loadCatalog(search: String) async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            let response = try await apiClient.fetchSkillsRegistry(search: search, limit: 60)
            catalogSkills = response.skills
            catalogTotal = response.total
        } catch is CancellationError {
            return
        } catch {
            catalogSkills = []
            catalogTotal = 0
            errorMessage = "The skills catalog could not be loaded."
        }
    }

    private func install(_ skill: SkillRegistryItem) async {
        guard changingSkillID == nil else { return }
        changingSkillID = skill.id
        errorMessage = nil
        defer { changingSkillID = nil }
        do {
            _ = try await apiClient.installAgentSkill(
                agentId: agent.id,
                request: AgentSkillInstallRequest(owner: skill.owner, repo: skill.repo)
            )
            await loadInstalled()
        } catch {
            errorMessage = "\(skill.name) could not be installed: \(error.localizedDescription)"
        }
    }

    private func uninstall(_ skill: InstalledAgentSkill) async {
        guard changingSkillID == nil else { return }
        changingSkillID = skill.id
        errorMessage = nil
        defer { changingSkillID = nil }
        do {
            try await apiClient.uninstallAgentSkill(agentId: agent.id, skillId: skill.id)
            await loadInstalled()
        } catch {
            errorMessage = "\(skill.name) could not be removed: \(error.localizedDescription)"
        }
    }
}

private struct InstalledSkillCard: View {
    let skill: InstalledAgentSkill
    let isWorking: Bool
    let onRemove: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(alignment: .top, spacing: theme.spacing.s) {
                SkillIcon(color: theme.colors.statusDone)
                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.name).font(.headline).foregroundStyle(theme.colors.textPrimary)
                    Text(repositoryLabel).font(.caption.monospaced()).foregroundStyle(theme.colors.textMuted)
                }
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "trash")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isWorking)
                .accessibilityLabel("Remove \(skill.name)")
            }

            Text(descriptionText)
                .font(.subheadline)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(3)

            HStack(spacing: 6) {
                if !skill.userInvocable {
                    SkillTag(text: "Model only")
                }
                if !skill.allowedTools.isEmpty {
                    SkillTag(text: "\(skill.allowedTools.count) tools")
                }
                if skill.context == "fork" {
                    SkillTag(text: "Fork")
                }
                Spacer()
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(theme.colors.statusDone)
            }
        }
        .padding(theme.spacing.m)
        .background(theme.colors.surfaceRaised.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.colors.border, lineWidth: 1) }
    }

    private var repositoryLabel: String {
        skill.owner.isEmpty || skill.repo.isEmpty ? skill.localPath : "\(skill.owner)/\(skill.repo)"
    }

    private var descriptionText: String {
        let value = skill.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "No description provided." : value
    }
}

private struct CatalogSkillCard: View {
    let skill: SkillRegistryItem
    let isInstalled: Bool
    let isWorking: Bool
    let onInstall: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(alignment: .top, spacing: theme.spacing.s) {
                SkillIcon(color: theme.colors.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.name).font(.headline).foregroundStyle(theme.colors.textPrimary)
                    Text("\(skill.owner)/\(skill.repo)").font(.caption.monospaced()).foregroundStyle(theme.colors.textMuted)
                }
                Spacer()
            }

            Text(descriptionText)
                .font(.subheadline)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)

            HStack {
                Label(skill.installs.formatted(.number.notation(.compactName)), systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(theme.colors.textMuted)
                Spacer()
                Button(action: onInstall) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(isInstalled ? "Installed" : "Install", systemImage: isInstalled ? "checkmark" : "plus")
                    }
                }
                .buttonStyle(.bordered)
                .tint(isInstalled ? theme.colors.statusDone : theme.colors.accent)
                .disabled(isInstalled || isWorking)
            }
        }
        .padding(theme.spacing.m)
        .background(theme.colors.surfaceRaised.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.colors.border, lineWidth: 1) }
    }

    private var descriptionText: String {
        let value = skill.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "No description provided." : value
    }
}

private struct SkillIcon: View {
    let color: Color

    var body: some View {
        Image(systemName: "sparkles")
            .font(.headline)
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SkillTag: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(theme.colors.surfaceGlow, in: Capsule())
    }
}
