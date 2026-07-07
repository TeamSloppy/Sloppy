import ArgumentParser
import Foundation
import Protocols

struct AuthCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Manage login/password authentication.",
        subcommands: [
            AuthChallengeCommand.self,
            AuthEnableLoginPasswordCommand.self,
            AuthLoginCommand.self,
            AuthLogoutCommand.self,
            AuthStatusCommand.self,
        ]
    )
}

struct AuthChallengeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "challenge",
        abstract: "Show the authentication challenge expected by the server."
    )

    @Option(name: .long, help: "Sloppy server URL") var url: String?
    @Flag(name: .long, help: "Show detailed HTTP info") var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: "", verbose: verbose)
        do {
            let data = try await client.get("/v1/auth/challenge")
            CLIFormatters.printJSON(data)
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}

struct AuthEnableLoginPasswordCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable-login-password",
        abstract: "Irreversibly switch the server to login/password authentication."
    )

    @Option(name: .long, help: "Sloppy server URL") var url: String?
    @Option(name: .long, help: "Legacy dashboard/token auth token") var token: String?
    @Flag(name: .long, help: "Acknowledge that this cannot be reverted to token auth") var confirmIrreversible: Bool = false
    @Flag(name: .long, help: "Show detailed HTTP info") var verbose: Bool = false

    mutating func run() async throws {
        guard confirmIrreversible else {
            CLIStyle.error("This switches Sloppy to login/password auth and cannot be reverted. Re-run with --confirm-irreversible.")
            throw ExitCode.failure
        }
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let body = try client.encode(AuthModeUpdateRequest(mode: .loginPassword, confirmIrreversible: true))
            let data = try await client.post("/v1/auth/mode", body: body)
            CLIStyle.success("Login/password auth enabled.")
            CLIFormatters.printJSON(data)
            print(CLIStyle.dim("Next: create the first Admin with /v1/auth/bootstrap or use the Dashboard setup flow."))
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}

struct AuthLoginCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "login",
        abstract: "Login with username and password and store the local session in .sloppy/auth.json."
    )

    @Option(name: .long, help: "Sloppy server URL") var url: String?
    @Option(name: .long, help: "User login") var login: String
    @Option(name: .long, help: "User password") var password: String
    @Flag(name: .long, help: "Show detailed HTTP info") var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: "", verbose: verbose)
        do {
            let body = try client.encode(AuthLoginRequest(login: login, password: password))
            let data = try await client.post("/v1/auth/login", body: body)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(AuthSessionResponse.self, from: data)
            let session = SloppyCLILocalAuthSession(
                baseURL: client.baseURL,
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                accessTokenExpiresAt: response.accessTokenExpiresAt,
                refreshTokenExpiresAt: response.refreshTokenExpiresAt,
                user: response.user
            )
            try SloppyCLILocalAuthStore.save(session)
            CLIStyle.success("Logged in as \(response.user.login) (\(response.user.role.rawValue)).")
            print(CLIStyle.dim("Session stored in \(SloppyCLILocalAuthStore.relativePath)."))
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}

struct AuthLogoutCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logout",
        abstract: "Remove the local login/password session."
    )

    mutating func run() throws {
        do {
            try SloppyCLILocalAuthStore.clear()
            CLIStyle.success("Local auth session removed.")
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}

struct AuthStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show local login/password session status."
    )

    @Option(name: .long, help: "Sloppy server URL") var url: String?
    @Flag(name: .long, help: "Also query the server auth challenge") var challenge: Bool = false
    @Flag(name: .long, help: "Show detailed HTTP info") var verbose: Bool = false

    mutating func run() async throws {
        do {
            if let session = try SloppyCLILocalAuthStore.load() {
                let state = CLIStyle.green("present")
                print("Local session: \(state)")
                print("User: \(session.user.login) (\(session.user.role.rawValue))")
                print("Server: \(session.baseURL)")
                print("Access token expires: \(session.accessTokenExpiresAt)")
                print("Refresh token expires: \(session.refreshTokenExpiresAt)")
            } else {
                let state = CLIStyle.yellow("missing")
                print("Local session: \(state)")
                print(CLIStyle.dim("Run `sloppy auth login --login <name> --password <password>` after enabling login/password auth."))
            }

            guard challenge else { return }
            let client = SloppyCLIClient.resolve(url: url, token: "", verbose: verbose)
            let data = try await client.get("/v1/auth/challenge")
            CLIFormatters.printJSON(data)
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}
