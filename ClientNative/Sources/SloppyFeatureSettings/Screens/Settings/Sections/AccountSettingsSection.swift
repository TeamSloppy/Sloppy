import SwiftUI
import SloppyClientCore
import SloppyClientUI

@MainActor
struct AccountSettingsSection: View {
    let apiClient: SloppyAPIClient
    let onLogout: @MainActor () -> Void

    @State private var user: AuthUserProfile?
    @State private var name = ""
    @State private var avatar = ""
    @State private var profileDescription = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmedPassword = ""
    @State private var recoveryCodes: [String] = []
    @State private var applicationTokens: [AuthApplicationToken] = []
    @State private var newTokenName = ""
    @State private var revealedToken: String?
    @State private var statusText = "Loading account…"
    @State private var isWorking = false

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            if let user {
                profileSection(user)
                passwordSection
                recoveryCodesSection
                applicationTokensSection
                logoutSection
            } else {
                SettingsSectionSurface {
                    VStack(alignment: .leading, spacing: theme.spacing.m) {
                        ProgressView()
                        Text(statusText)
                            .foregroundColor(theme.colors.textSecondary)
                        Button("Retry", action: loadAccount)
                    }
                }
            }
        }
        .task {
            guard user == nil else { return }
            loadAccount()
        }
    }

    private func profileSection(_ user: AuthUserProfile) -> some View {
        SettingsSectionSurface {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                sectionTitle("Profile", subtitle: "Your Sloppy identity on this Core server.")

                HStack(spacing: theme.spacing.m) {
                    Text(initials(for: name.isEmpty ? user.login : name))
                        .font(.system(size: theme.typography.heading, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .background(theme.colors.accent, in: Circle())

                    VStack(alignment: .leading, spacing: theme.spacing.xs) {
                        Text(user.login)
                            .font(.system(size: theme.typography.heading, weight: .semibold))
                            .foregroundColor(theme.colors.textPrimary)
                        Text("\(user.role.capitalized) • \((user.status ?? "active").capitalized)")
                            .font(.system(size: theme.typography.caption))
                            .foregroundColor(theme.colors.textMuted)
                    }
                }

                profileField("Name", text: $name)
                profileField("Avatar URL", text: $avatar)
                profileField("About", text: $profileDescription)

                HStack {
                    Text(statusText)
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.textMuted)
                    Spacer()
                    Button("Save Profile", action: saveProfile)
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || normalizedName.isEmpty)
                }
            }
        }
    }

    private var passwordSection: some View {
        SettingsSectionSurface {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                sectionTitle("Password", subtitle: "Changing it signs out other sessions and keeps this device connected.")
                secureField("Current password", text: $currentPassword)
                    .textContentType(.password)
                secureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
                secureField("Confirm new password", text: $confirmedPassword)
                    .textContentType(.newPassword)

                HStack {
                    if !confirmedPassword.isEmpty, newPassword != confirmedPassword {
                        Text("Passwords do not match")
                            .font(.system(size: theme.typography.caption))
                            .foregroundColor(theme.colors.statusBlocked)
                    }
                    Spacer()
                    Button("Change Password", action: changePassword)
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || currentPassword.isEmpty || newPassword.isEmpty || newPassword != confirmedPassword)
                }
            }
        }
    }

    private var recoveryCodesSection: some View {
        SettingsSectionSurface {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                sectionTitle(
                    "Recovery Codes",
                    subtitle: "Generate a new one-time set and store it somewhere safe. Existing codes stop working."
                )

                if !recoveryCodes.isEmpty {
                    VStack(alignment: .leading, spacing: theme.spacing.xs) {
                        ForEach(recoveryCodes, id: \.self) { code in
                            Text(code)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(theme.spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.colors.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                }

                Button(recoveryCodes.isEmpty ? "Generate Recovery Codes" : "Replace Recovery Codes", action: generateRecoveryCodes)
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
            }
        }
    }

    private var applicationTokensSection: some View {
        SettingsSectionSurface {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                sectionTitle("Application Tokens", subtitle: "Long-lived credentials for integrations.")

                if let revealedToken {
                    VStack(alignment: .leading, spacing: theme.spacing.s) {
                        Text("Copy this token now. It will not be shown again.")
                            .font(.system(size: theme.typography.caption, weight: .semibold))
                            .foregroundColor(theme.colors.statusWarning)
                        Text(revealedToken)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(theme.spacing.m)
                    .background(theme.colors.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                }

                HStack(spacing: theme.spacing.m) {
                    TextField("Token name", text: $newTokenName)
                        .textFieldStyle(.roundedBorder)
                    Button("Create Token", action: createApplicationToken)
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || normalizedTokenName.isEmpty)
                }

                if applicationTokens.isEmpty {
                    Text("No application tokens")
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.textMuted)
                } else {
                    ForEach(applicationTokens) { token in
                        HStack(spacing: theme.spacing.m) {
                            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                                Text(token.name)
                                    .foregroundColor(theme.colors.textPrimary)
                                Text("\(token.tokenPrefix) • expires \(token.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.system(size: theme.typography.caption))
                                    .foregroundColor(theme.colors.textMuted)
                            }
                            Spacer()
                            Button("Revoke", role: .destructive) { revokeApplicationToken(token) }
                                .disabled(isWorking)
                        }
                        Divider()
                    }
                }
            }
        }
    }

    private var logoutSection: some View {
        SettingsSectionSurface {
            HStack {
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text("Sign Out")
                        .font(.system(size: theme.typography.heading, weight: .semibold))
                    Text("Remove this server session from the device.")
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.textMuted)
                }
                Spacer()
                Button("Sign Out", role: .destructive, action: onLogout)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var normalizedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var normalizedTokenName: String { newTokenName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(title)
                .font(.system(size: theme.typography.heading, weight: .semibold))
                .foregroundColor(theme.colors.textPrimary)
            Text(subtitle)
                .font(.system(size: theme.typography.caption))
                .foregroundColor(theme.colors.textMuted)
        }
    }

    private func profileField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(title)
                .font(.system(size: theme.typography.caption, weight: .medium))
                .foregroundColor(theme.colors.textSecondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(title)
                .font(.system(size: theme.typography.caption, weight: .medium))
                .foregroundColor(theme.colors.textSecondary)
            SecureField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func initials(for value: String) -> String {
        let initials = value.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
        return initials.isEmpty ? "SU" : String(initials).uppercased()
    }

    private func loadAccount() {
        isWorking = true
        statusText = "Loading account…"
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let loadedUser = try await apiClient.fetchCurrentAuthUser()
                user = loadedUser
                name = loadedUser.name
                avatar = loadedUser.avatar ?? ""
                profileDescription = loadedUser.description ?? ""
                applicationTokens = try await apiClient.fetchIdentityApplicationTokens()
                statusText = "Account loaded"
            } catch {
                statusText = "Account management requires login/password authentication."
            }
        }
    }

    private func saveProfile() {
        guard user != nil else { return }
        isWorking = true
        statusText = "Saving profile…"
        Task { @MainActor in
            defer { isWorking = false }
            do {
                self.user = try await apiClient.updateCurrentAuthUser(
                    name: normalizedName,
                    avatar: avatar.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: profileDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                statusText = "Profile saved"
            } catch {
                statusText = "Could not save the profile"
            }
        }
    }

    private func changePassword() {
        isWorking = true
        statusText = "Changing password…"
        Task { @MainActor in
            defer { isWorking = false }
            do {
                _ = try await apiClient.changeIdentityPassword(currentPassword: currentPassword, newPassword: newPassword)
                currentPassword = ""
                newPassword = ""
                confirmedPassword = ""
                statusText = "Password changed"
            } catch {
                statusText = "Could not change the password"
            }
        }
    }

    private func generateRecoveryCodes() {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                recoveryCodes = try await apiClient.generateIdentityRecoveryCodes().codes
                statusText = "Recovery codes replaced"
            } catch {
                statusText = "Could not generate recovery codes"
            }
        }
    }

    private func createApplicationToken() {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let created = try await apiClient.createIdentityApplicationToken(name: normalizedTokenName)
                revealedToken = created.token
                newTokenName = ""
                applicationTokens = try await apiClient.fetchIdentityApplicationTokens()
                statusText = "Application token created"
            } catch {
                statusText = "Could not create the application token"
            }
        }
    }

    private func revokeApplicationToken(_ token: AuthApplicationToken) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await apiClient.revokeIdentityApplicationToken(id: token.id)
                applicationTokens.removeAll { $0.id == token.id }
                statusText = "Application token revoked"
            } catch {
                statusText = "Could not revoke the application token"
            }
        }
    }
}
