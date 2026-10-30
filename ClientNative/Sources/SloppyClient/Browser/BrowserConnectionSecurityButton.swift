#if os(macOS)
import Foundation
import SwiftUI
import SecurityInterface

@MainActor
struct BrowserConnectionSecurityButton: View {
    let page: WorkspaceWebViewModel?
    let requestedURL: URL?
    @State private var isPresented = false
    @State private var openedByHover = false
    @State private var isIconHovered = false
    @State private var isPopoverHovered = false
    @State private var dismissTask: Task<Void, Never>?
    @State private var windowHandle = BrowserCertificateWindowAnchor.Handle()
    @State private var certificatePanel: SFCertificatePanel?

    private var security: BrowserConnectionSecurity { page?.connectionSecurity(for: requestedURL) ?? .empty }

    var body: some View {
        Button {
            dismissTask?.cancel()
            if isPresented && openedByHover { openedByHover = false }
            else { openedByHover = false; isPresented.toggle() }
        } label: {
            Image(systemName: security.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(BrowserCertificateWindowAnchor(handle: windowHandle).allowsHitTesting(false).accessibilityHidden(true))
        .disabled(requestedURL == nil)
        .accessibilityLabel("Connection information")
        .accessibilityValue(security.label)
        .accessibilityIdentifier("browser-connection-security")
        .onHover { hovered in
            isIconHovered = hovered
            if hovered, requestedURL != nil {
                dismissTask?.cancel()
                if !isPresented { openedByHover = true; isPresented = true }
            }
            else { scheduleDismissal() }
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            BrowserCertificatePopover(host: requestedURL?.host ?? "", security: security,
                                      certificate: page?.certificateInfo(for: requestedURL),
                                      onShowDetails: { certificate in
                                          if let window = windowHandle.window {
                                              certificatePanel = certificate.showDetails(in: window)
                                          }
                                          isPresented = false
                                      })
                .onHover { hovered in
                    isPopoverHovered = hovered
                    if hovered { dismissTask?.cancel() } else { scheduleDismissal() }
                }
        }
        .onChange(of: requestedURL) { _, _ in isPresented = false }
        .onChange(of: page.map(ObjectIdentifier.init)) { _, _ in isPresented = false }
        .onChange(of: page?.isLoading) { _, loading in if loading == true { isPresented = false } }
        .onDisappear { dismissTask?.cancel() }
    }

    private func scheduleDismissal() {
        dismissTask?.cancel()
        guard openedByHover else { return }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, openedByHover, !isIconHovered, !isPopoverHovered else { return }
            isPresented = false
        }
    }
}

@MainActor
struct BrowserCertificatePopover: View {
    let host: String
    let security: BrowserConnectionSecurity
    let certificate: BrowserCertificateInfo?
    let onShowDetails: (BrowserCertificateInfo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(host, systemImage: security.symbol).font(.headline)
            Text(security.label).font(.callout).foregroundStyle(.secondary)
            if let certificate {
                Divider()
                detail("Issued to", value: certificate.subject)
                if let issuer = certificate.issuer { detail("Issued by", value: issuer) }
                if let date = certificate.validFrom { detail("Valid from", value: date.formatted(date: .abbreviated, time: .omitted)) }
                if let date = certificate.validUntil { detail("Valid until", value: date.formatted(date: .abbreviated, time: .omitted)) }
                Text("SHA-256").font(.caption).foregroundStyle(.secondary)
                Text(certificate.sha256).font(.system(size: 10, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Button("Show Certificate…") { onShowDetails(certificate) }
                    .accessibilityIdentifier("browser-show-certificate")
            } else {
                Text(security == .notSecure ? "This page uses HTTP and has no TLS certificate." : "Certificate details are not available for this page.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-certificate-popover")
    }

    private func detail(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
            Text(value).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
}

@MainActor
private struct BrowserCertificateWindowAnchor: NSViewRepresentable {
    final class Handle { weak var window: NSWindow? }
    let handle: Handle

    func makeNSView(context: Context) -> AnchorView { AnchorView(handle: handle) }
    func updateNSView(_ view: AnchorView, context: Context) { handle.window = view.window }

    final class AnchorView: NSView {
        let handle: Handle
        init(handle: Handle) { self.handle = handle; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            handle.window = window
        }
    }
}
#endif
