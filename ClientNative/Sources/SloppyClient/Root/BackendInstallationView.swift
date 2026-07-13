#if os(macOS)
import Observation
import SwiftUI
import SloppyClientCore

@MainActor
@Observable
final class BackendInstallationModel {
    enum State: Equatable {
        case checking
        case offer
        case installing
        case failed(String)
        case finished(String)
        case dismissed
    }

    struct Step: Identifiable, Equatable {
        enum Status: Equatable { case pending, active, complete }
        let phase: BackendInstallationPhase
        let title: String
        var status: Status = .pending
        var detail: String?
        var id: String { title }
    }

    private static let declinedKey = "sloppy_backend_installation_declined"
    var state: State = .checking
    var progress = 0.0
    var currentDetail = "Checking for an existing Sloppy installation"
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    var showsDetails = false
    var logLines: [String] = []
    var steps = BackendInstallationModel.makeSteps()

    private let defaults: UserDefaults
    private let installer: BackendInstaller
    private var installationTask: Task<Void, Never>?
    private var didCheck = false

    init(defaults: UserDefaults = .standard, installer: BackendInstaller = BackendInstaller()) {
        self.defaults = defaults
        self.installer = installer
    }

    var blocksApp: Bool { state != .dismissed }
    var completedStepCount: Int { steps.filter { $0.status == .complete }.count }

    func checkIfNeeded() {
        guard !didCheck else { return }
        didCheck = true
        state = BackendInstaller.isInstalled() || defaults.bool(forKey: Self.declinedKey) ? .dismissed : .offer
    }

    func decline() {
        defaults.set(true, forKey: Self.declinedKey)
        state = .dismissed
    }

    func install() {
        installationTask?.cancel()
        steps = Self.makeSteps()
        logLines = []
        progress = 0
        state = .installing
        installationTask = Task { [installer] in
            do {
                let version = try await installer.install { [weak self] update in self?.receive(update) }
                guard !Task.isCancelled else { return }
                state = .finished(version)
            } catch is CancellationError {
                guard state == .installing else { return }
                state = .offer
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
        state = .offer
    }

    func continueToApp() { state = .dismissed }

    private func receive(_ update: BackendInstallationProgress) {
        currentDetail = update.detail
        downloadedBytes = update.downloadedBytes
        totalBytes = update.totalBytes
        if logLines.last != update.detail { logLines.append(update.detail) }
        guard let activeIndex = steps.firstIndex(where: { $0.phase == update.phase }) else { return }
        for index in steps.indices {
            if index < activeIndex || (index == activeIndex && update.phaseFraction >= 1) {
                steps[index].status = .complete
            } else if index == activeIndex {
                steps[index].status = .active
                steps[index].detail = update.detail
            } else {
                steps[index].status = .pending
            }
        }
        progress = (Double(activeIndex) + update.phaseFraction) / Double(steps.count)
    }

    private static func makeSteps() -> [Step] {
        [
            Step(phase: .resolvingRelease, title: "Find latest release"),
            Step(phase: .downloadingChecksum, title: "Download checksums"),
            Step(phase: .downloadingArchive, title: "Download Sloppy backend"),
            Step(phase: .verifyingArchive, title: "Verify SHA-256 checksum"),
            Step(phase: .extractingArchive, title: "Extract release archive"),
            Step(phase: .installingFiles, title: "Install backend and resources"),
            Step(phase: .creatingCommandLinks, title: "Create command links"),
            Step(phase: .verifyingInstallation, title: "Verify installation"),
        ]
    }
}

@MainActor
struct BackendInstallationView: View {
    let model: BackendInstallationModel

    var body: some View {
        Group {
            switch model.state {
            case .checking: ProgressView("Checking Sloppy backend…").controlSize(.large)
            case .offer: offer
            case .installing: installation
            case .failed(let message): failure(message)
            case .finished(let version): completion(version)
            case .dismissed: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var offer: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 56, weight: .light)).foregroundStyle(.tint)
            VStack(spacing: 10) {
                Text("Install Sloppy Backend").font(.system(size: 38, weight: .bold, design: .rounded))
                Text("Sloppy needs its local backend to run agents and serve your workspace. We’ll download the latest release from GitHub and verify it before installation.")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 680)
            }
            HStack(spacing: 12) {
                Button("Don’t Ask Again") { model.decline() }.buttonStyle(.bordered)
                Button("Install Sloppy") { model.install() }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
            Text("Installed privately for this app in Application Support")
                .font(.footnote).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(48)
    }

    private var installation: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(model.currentDetail).font(.headline).lineLimit(1)
                    Spacer()
                    Text("\(model.completedStepCount) of \(model.steps.count) steps").foregroundStyle(.secondary)
                }
                ProgressView(value: model.progress).progressViewStyle(.linear)
                if let downloaded = model.downloadedBytes, let total = model.totalBytes {
                    Text("\(ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            Divider()
            HSplitView {
                ScrollView {
                    LazyVStack(spacing: 8) { ForEach(model.steps) { stepRow($0) } }.padding(24)
                }
                .frame(minWidth: 420)
                if model.showsDetails {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Installation log").font(.headline)
                            Spacer()
                            Text("\(model.logLines.count) events").foregroundStyle(.secondary)
                        }
                        .padding(14)
                        Divider()
                        ScrollView {
                            Text(model.logLines.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        }
                    }
                    .frame(minWidth: 380)
                }
            }
            Divider()
            HStack {
                Button(model.showsDetails ? "Hide Details" : "Show Details", systemImage: "doc.text") { model.showsDetails.toggle() }
                    .buttonStyle(.plain)
                Spacer()
                Button("Cancel") { model.cancel() }.buttonStyle(.bordered)
            }
            .padding(18)
        }
    }

    private func stepRow(_ step: BackendInstallationModel.Step) -> some View {
        HStack(spacing: 14) {
            Group {
                switch step.status {
                case .pending: Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.tertiary)
                case .active: ProgressView().controlSize(.small)
                case .complete: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title).font(.body.weight(step.status == .active ? .semibold : .regular))
                if step.status == .active, let detail = step.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
        .foregroundStyle(step.status == .pending ? .tertiary : .primary)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(step.status == .active ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 10))
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 48)).foregroundStyle(.orange)
            Text("Installation Failed").font(.largeTitle.bold())
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 620)
            HStack {
                Button("Continue Without Backend") { model.continueToApp() }
                Button("Try Again") { model.install() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            if !model.logLines.isEmpty {
                ScrollView {
                    Text(model.logLines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 680, maxHeight: 180)
            }
        }
        .padding(48)
    }

    private func completion(_ version: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("Sloppy Is Ready").font(.largeTitle.bold())
            Text("Installed \(version) and verified the backend executable.").foregroundStyle(.secondary)
            Button("Continue") { model.continueToApp() }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
    }
}
#endif
