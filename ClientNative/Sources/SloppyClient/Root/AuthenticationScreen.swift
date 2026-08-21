import SwiftUI
import SloppyClientCore
import SloppyClientUI

@MainActor
struct AuthenticationScreen: View {
    let baseURL: URL
    let challenge: AuthChallenge
    let initialMessage: String?
    let onAuthenticated: (URL) -> Void
    let onScannedCode: (URL) -> Void
    let onChooseServer: () -> Void

    @State private var authenticationMethod: AuthenticationMethod
    @State private var login = ""
    @State private var password = ""
    @State private var token = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.theme) private var theme

    private enum AuthenticationMethod: String, CaseIterable, Identifiable {
        case loginPassword
        case qrCode
        case dashboardToken

        var id: String { rawValue }

        var title: String {
            switch self {
            case .loginPassword: "Login"
            case .qrCode: "QR"
            case .dashboardToken: "Token"
            }
        }
    }

    init(
        baseURL: URL,
        challenge: AuthChallenge,
        initialMessage: String?,
        onAuthenticated: @escaping (URL) -> Void,
        onScannedCode: @escaping (URL) -> Void,
        onChooseServer: @escaping () -> Void
    ) {
        self.baseURL = baseURL
        self.challenge = challenge
        self.initialMessage = initialMessage
        self.onAuthenticated = onAuthenticated
        self.onScannedCode = onScannedCode
        self.onChooseServer = onChooseServer
        self._authenticationMethod = State(
            initialValue: challenge.mode == "login_password" ? .loginPassword : .dashboardToken
        )
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

                    Text("Sign in to Sloppy")
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
                } else {
                    Picker("Authentication method", selection: $authenticationMethod) {
                        ForEach(AuthenticationMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("authentication.method")

                    authenticationMethodContent
                }

                if let message = errorMessage ?? initialMessage {
                    Text(message)
                        .font(.system(size: ty.caption))
                        .foregroundColor(errorMessage == nil ? c.textSecondary : c.statusBlocked)
                }

                if authenticationMethod != .qrCode || challenge.bootstrapRequired {
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
                }

                Button("Choose another server", action: onChooseServer)
                    .buttonStyle(.plain)
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.accentCyan)
                    .frame(maxWidth: .infinity)
            }
            .padding(sp.xxl)
            .frame(maxWidth: 420)
            .padding(.horizontal, sp.m)
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
        switch authenticationMethod {
        case .loginPassword:
            return !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
        case .dashboardToken:
            return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .qrCode:
            return false
        }
    }

    @ViewBuilder
    private var authenticationMethodContent: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        switch authenticationMethod {
        case .loginPassword:
            VStack(spacing: sp.m) {
                authenticationField("Login", text: $login)
                    .textContentType(.username)
                    .accessibilityIdentifier("authentication.login")
                secureAuthenticationField("Password", text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("authentication.password")
            }
        case .qrCode:
            VStack(alignment: .leading, spacing: sp.m) {
                Text("In Dashboard, open Settings → Connect Client and scan the short-lived code. It signs in as the Dashboard user without putting a password in the QR code.")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textSecondary)
                #if os(iOS)
                QRCodeScannerButton(onScannedCode: onScannedCode)
                #else
                Text("Scan the code with an iPhone or iPad running Sloppy, or open the temporary pairing link on this device.")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                #endif
            }
        case .dashboardToken:
            VStack(alignment: .leading, spacing: sp.s) {
                secureAuthenticationField("Dashboard access token", text: $token)
                    .accessibilityIdentifier("authentication.dashboardToken")
                Text("Use the legacy dashboard token configured for this Sloppy Core.")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
            }
        }
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
                switch authenticationMethod {
                case .loginPassword:
                    _ = try await apiClient.loginIdentityUser(login: login, password: password)
                case .dashboardToken:
                    await apiClient.installStaticAuthToken(token)
                    do {
                        try await apiClient.validateCurrentAuthToken()
                    } catch {
                        await apiClient.logout()
                        throw error
                    }
                case .qrCode:
                    return
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
