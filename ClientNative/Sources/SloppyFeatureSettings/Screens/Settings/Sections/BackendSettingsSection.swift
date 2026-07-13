#if os(macOS)
import Observation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

@MainActor
@Observable
private final class BackendSettingsModel {
    enum State: Equatable {
        case idle(installed: Bool)
        case installing
        case installed(String)
        case failed(String)
    }

    var state: State = .idle(installed: BackendInstaller.isInstalled())
    var progress = 0.0
    var detail = ""
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    var logLines: [String] = []

    private let installer = BackendInstaller()
    private var installationTask: Task<Void, Never>?

    var isInstalled: Bool {
        switch state {
        case .idle(let installed): installed
        case .installed: true
        case .installing, .failed: BackendInstaller.isInstalled()
        }
    }

    func install() {
        installationTask?.cancel()
        progress = 0
        detail = "Preparing installation"
        downloadedBytes = nil
        totalBytes = nil
        logLines = []
        state = .installing
        installationTask = Task { [installer] in
            do {
                let version = try await installer.install { [weak self] update in
                    self?.receive(update)
                }
                guard !Task.isCancelled else { return }
                state = .installed(version)
            } catch is CancellationError {
                state = .idle(installed: BackendInstaller.isInstalled())
            } catch {
                guard !Task.isCancelled else { return }
                logLines.append("Error: \(error.localizedDescription)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        installationTask?.cancel()
        installationTask = nil
        state = .idle(installed: BackendInstaller.isInstalled())
    }

    private func receive(_ update: BackendInstallationProgress) {
        let phases: [BackendInstallationPhase] = [
            .resolvingRelease, .downloadingChecksum, .downloadingArchive, .verifyingArchive,
            .extractingArchive, .installingFiles, .creatingCommandLinks, .verifyingInstallation,
        ]
        guard let index = phases.firstIndex(of: update.phase) else { return }
        progress = (Double(index) + update.phaseFraction) / Double(phases.count)
        detail = update.detail
        downloadedBytes = update.downloadedBytes
        totalBytes = update.totalBytes
        if logLines.last != update.detail { logLines.append(update.detail) }
    }
}

struct BackendSettingsSection: View {
    @State private var model = BackendSettingsModel()
    @State private var showsLog = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            SettingsSectionCard("Installation") {
                VStack(alignment: .leading, spacing: theme.spacing.m) {
                    statusRow
                    SettingsDivider()
                    locationRow

                    switch model.state {
                    case .installing:
                        installationProgress
                    case .failed(let message):
                        resultView(message, icon: "exclamationmark.triangle", color: theme.colors.statusBlocked)
                    case .installed(let version):
                        resultView("Installed \(version)", icon: "checkmark.circle", color: theme.colors.statusDone)
                    case .idle:
                        EmptyView()
                    }

                    SettingsDivider()
                    HStack {
                        if !model.logLines.isEmpty {
                            Button(showsLog ? "Hide Installation Log" : "Show Installation Log") {
                                showsLog.toggle()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(theme.colors.textSecondary)
                        }
                        Spacer()
                        if model.state == .installing {
                            Button("Cancel") { model.cancel() }
                        } else {
                            Button(model.isInstalled ? "Reinstall Latest Version" : "Install Latest Version") {
                                model.install()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if showsLog, !model.logLines.isEmpty {
                        ScrollView {
                            Text(model.logLines.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(theme.colors.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 220)
                        .padding(theme.spacing.s)
                        .background(theme.colors.surfaceRaised.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(theme.spacing.m)
            }
            .padding(.horizontal, theme.spacing.m)

            SettingsSectionSurface {
                VStack(alignment: .leading, spacing: theme.spacing.s) {
                    Label("Release verification", systemImage: "checkmark.shield")
                        .font(.system(size: theme.typography.heading, weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                    Text("The matching macOS archive is downloaded from TeamSloppy/Sloppy, verified against SHA256SUMS.txt, and checked with sloppy --version after installation.")
                        .font(.system(size: theme.typography.body))
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: theme.spacing.m) {
            Image(systemName: model.isInstalled ? "checkmark.circle.fill" : "shippingbox")
                .font(.title2)
                .foregroundStyle(model.isInstalled ? theme.colors.statusDone : theme.colors.textMuted)
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(model.isInstalled ? "Backend installed" : "Backend not installed")
                    .font(.system(size: theme.typography.body, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                Text(model.isInstalled ? "Reinstall to fetch the latest release." : "Install the local backend required to run Sloppy agents.")
                    .font(.system(size: theme.typography.caption))
                    .foregroundStyle(theme.colors.textMuted)
            }
            Spacer()
        }
    }

    private var locationRow: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text("INSTALLATION LOCATION")
                .font(.system(size: theme.typography.micro))
                .foregroundStyle(theme.colors.textSecondary)
            Text(BackendInstaller.installedExecutableURL().path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.colors.textMuted)
                .textSelection(.enabled)
        }
    }

    private var installationProgress: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            ProgressView(value: model.progress)
            HStack {
                Text(model.detail).lineLimit(1)
                Spacer()
                Text(model.progress, format: .percent.precision(.fractionLength(0)))
            }
            .font(.system(size: theme.typography.caption))
            .foregroundStyle(theme.colors.textSecondary)
            if let downloaded = model.downloadedBytes, let total = model.totalBytes {
                Text("\(ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                    .font(.system(size: theme.typography.caption))
                    .foregroundStyle(theme.colors.textMuted)
            }
        }
    }

    private func resultView(_ message: String, icon: String, color: Color) -> some View {
        Label(message, systemImage: icon)
            .font(.system(size: theme.typography.caption))
            .foregroundStyle(color)
    }
}
#endif
