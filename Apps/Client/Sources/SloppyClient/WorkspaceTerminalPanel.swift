@_spi(AdaEngine) import AdaEngine
import SloppyClientUI

extension WorkspaceTerminalSession {
    func pasteClipboard() {
        guard let text = UIClipboard.getString() else { return }
        send((terminal.bracketedPasteMode ? "\u{1b}[200~" : "") + text + (terminal.bracketedPasteMode ? "\u{1b}[201~" : ""))
    }
}

struct WorkspaceTerminalPanel: View {
    let session: WorkspaceTerminalSession
    let projectPath: String?
    @State private var directory = ""
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 8) {
                Text("Local shell · \(session.isRunning ? "Running" : "Stopped")").font(.system(size: 12))
                TextField("Working directory", text: $directory).font(.system(size: 13)).padding(.horizontal, 6).frame(height: 34)
                    .background(theme.colors.surfaceRaised).disabled(session.isRunning)
                HStack(spacing: 8) {
                    WorkspaceAction(title: session.isRunning ? "Restart" : "Start", icon: .terminal) {
                        session.stop()
                        session.start(in: URL(fileURLWithPath: directory, isDirectory: true))
                    }
                    WorkspaceAction(title: "Stop") { session.stop() }.disabled(!session.isRunning)
                    WorkspaceAction(title: "Paste") { session.pasteClipboard() }
                    WorkspaceAction(title: "Copy") { UIClipboard.setString(session.terminal.selectionText(session.selection)) }
                }
                if let error = session.error { Text(error).font(.system(size: 12)).foregroundColor(theme.colors.statusBlocked) }
                WorkspaceTerminalSurface(session: session)
                    .frame(width: geometry.size.width, height: max(100, geometry.size.height - 125 - (session.error == nil ? 0 : 35)))
                    .accessibilityIdentifier("workspace.terminal.surface")
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }.sloppyTextInputStyle(theme.colors)
            .onAppear {
                if directory.isEmpty {
                    let path = projectPath ?? FileManager.default.currentDirectoryPath
                    directory = FileManager.default.fileExists(atPath: path) ? path : FileManager.default.currentDirectoryPath
                }
            }
    }
}
