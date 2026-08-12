import SwiftUI
import SloppyClientCore
import SloppyClientUI

@MainActor
struct AuthenticationScreen: View {
    let baseURL: URL
    let challenge: AuthChallenge
    let initialMessage: String?
    let onAuthenticated: (URL) -> Void
    let onChooseServer: () -> Void

    @State private var login = ""
    @State private var password = ""
    @State private var token = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.theme) private var theme

    private var usesIdentityLogin: Bool {
        challenge.mode == "login_password"
    }

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: sp.xl) {
                VStack(alignment: .leading, spacing: sp.s) {
                    SloppyAssets.projectLogo
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .foregroundColor(c.textMuted)

                    Text(usesIdentityLogin ? "Sign in to Sloppy" : "Authenticate with Sloppy")
                        .font(.system(size: ty.title, weight: .semibold))
                        .foregroundColor(c.textPrimary)

                    Text("\(baseURL.host ?? baseURL.absoluteString):\(baseURL.port ?? 25101)")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)
                }

                if challenge.bootstrapRequired {
                    Text("The first administrator must be created in the Sloppy Dashboard before this client can sign in.")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.statusWarning)
                        .padding(sp.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .backportGlassEffect(
                            .regular.tint(c.statusWarning.opacity(0.15)),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                } else if usesIdentityLogin {
                    VStack(spacing: sp.m) {
                        authenticationField("Login", text: $login)
                            .textContentType(.username)
                        secureAuthenticationField("Password", text: $password)
                            .textContentType(.password)
                    }
                } else {
                    secureAuthenticationField("Access token", text: $token)
                }

                if let message = errorMessage ?? initialMessage {
                    Text(message)
                        .font(.system(size: ty.caption))
                        .foregroundColor(errorMessage == nil ? c.textSecondary : c.statusBlocked)
                }

                Button {
                    submit()
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isSubmitting ? "SIGNING IN…" : "SIGN IN")
                            .font(.system(size: ty.body, weight: .semibold))
                    }
                    .foregroundColor(c.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, sp.m)
                }
                .buttonStyle(.plain)
                .backportGlassEffect(.regular.interactive().tint(c.accentCyan), in: .capsule)
                .disabled(!canSubmit)
                .keyboardShortcut(.defaultAction)

                Button("Choose another server", action: onChooseServer)
                    .buttonStyle(.plain)
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.accentCyan)
                    .frame(maxWidth: .infinity)
            }
            .padding(sp.xxl)
            .frame(width: 420)
            .backportGlassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onSubmit(submit)
    }

    private var canSubmit: Bool {
        guard !isSubmitting, !challenge.bootstrapRequired else { return false }
        if usesIdentityLogin {
            return !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
        }
        return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func authenticationField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, theme.spacing.m)
            .backportGlassEffect(.regular, in: .capsule)
    }

    private func secureAuthenticationField(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, theme.spacing.m)
            .backportGlassEffect(.regular, in: .capsule)
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil

        Task { @MainActor in
            let apiClient = SloppyAPIClient(baseURL: baseURL)
            do {
                if usesIdentityLogin {
                    _ = try await apiClient.loginIdentityUser(login: login, password: password)
                } else {
                    await apiClient.installStaticAuthToken(token)
                    do {
                        try await apiClient.validateCurrentAuthToken()
                    } catch {
                        await apiClient.logout()
                        throw error
                    }
                }
                password = ""
                token = ""
                isSubmitting = false
                onAuthenticated(baseURL)
            } catch {
                isSubmitting = false
                errorMessage = "Could not sign in. Check your credentials and try again."
            }
        }
    }
}
