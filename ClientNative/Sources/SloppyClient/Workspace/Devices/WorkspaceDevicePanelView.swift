#if os(macOS)
import SwiftUI
import SloppyClientUI
import SloppyFeatureChat
import WebKit

@MainActor
struct WorkspaceDevicePanelView: View {
    @Bindable var session: WorkspaceDeviceSession
    var onAnnotate: (@MainActor () -> (@MainActor (ChatComposerAttachment) -> Bool))?
    @Environment(\.theme) private var theme
    @State private var attachment: ChatComposerAttachment?
    @State private var receive: (@MainActor (ChatComposerAttachment) -> Bool)?
    @State private var isCapturing = false
    @State private var sources: [DeviceFrameSource] = []
    @State private var choosesCaptureSource = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(session.platform.rawValue, systemImage: "iphone.gen3")
                Text(session.androidAddress ?? "Local Mac").foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if session.baseURL != nil {
                    Button { capture() } label: { Label("Annotate", systemImage: "pencil.tip.crop.circle") }
                        .disabled(!session.isLoaded || onAnnotate == nil || isCapturing)
                        .help(onAnnotate == nil ? "Open a chat to attach a device screenshot" : "Annotate a frozen screenshot and add it to this chat")
                        .accessibilityIdentifier("workspace.devices.annotate")
                }
                if session.baseURL != nil || session.isStarting {
                    Button("Disconnect", systemImage: "xmark", action: session.stop).labelStyle(.iconOnly)
                        .help("Disconnect preview; keep the device running")
                }
            }
            .font(.system(size: 12)).buttonStyle(.plain).padding(12)
            Divider()
            if let error = session.errorMessage {
                Text(error).font(.callout).foregroundStyle(theme.colors.textSecondary)
                    .textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            if session.retainedCapture != nil {
                HStack {
                    Button("Review captured frame") {
                        receive = onAnnotate?()
                        attachment = session.retainedCapture
                    }.disabled(onAnnotate == nil)
                    Spacer()
                    Button("Discard capture") { session.retainedCapture = nil }
                }.font(.callout).padding(12)
            }
            if session.baseURL != nil {
                DeviceBridgeWebView(webView: session.webView)
            } else if session.isStarting {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(session.startupMessage)
                    Text("First launch downloads the device bridge and may take a few minutes.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Cancel", action: session.stop)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { WorkspaceDeviceSetupView(session: session) }
        }
        .background(theme.colors.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.devices")
        .confirmationDialog("Choose a device to annotate", isPresented: $choosesCaptureSource, titleVisibility: .visible) {
            ForEach(sources) { source in
                Button(source.name) { Task { await capture(source) } }
            }
        }
        .sheet(item: $attachment) { captured in
            ChatImageAnnotationEditor(attachment: captured, onSave: { edited in
                if receive?(edited) != true {
                    session.retainedCapture = edited
                    session.errorMessage = "The destination chat changed or cannot accept this image. Your capture is retained; review it to retry."
                } else { session.retainedCapture = nil }
            })
        }
    }

    private func capture() {
        receive = onAnnotate?()
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                sources = try await session.captureSources()
                if let source = sources.first, sources.count == 1 { await capture(source) }
                else if sources.isEmpty { session.errorMessage = "Connect a device in the preview before capturing a frame." }
                else { choosesCaptureSource = true }
            } catch is CancellationError { }
            catch { session.errorMessage = error.localizedDescription }
        }
    }

    private func capture(_ source: DeviceFrameSource) async {
        isCapturing = true
        defer { isCapturing = false }
        do {
            let captured = try await session.capture(source)
            session.retainedCapture = captured
            attachment = captured
        } catch is CancellationError { }
        catch { session.errorMessage = error.localizedDescription }
    }
}

private struct DeviceBridgeWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
