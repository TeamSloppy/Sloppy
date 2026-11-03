#if os(macOS)
import SwiftUI
import SloppyClientUI

@MainActor
struct WorkspaceDeviceSetupView: View {
    @Bindable var session: WorkspaceDeviceSession
    @State private var androidAddress = ""
    @State private var bridgeAddress = "http://127.0.0.1:3200"
    @State private var showsBridge = false
    @State private var showsHelp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Devices").font(.title2.weight(.semibold))
                    Text("Open a device beside your chat. Interact with its screen, then capture a frame to annotate.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                    ForEach(DevicePlatform.allCases) { platform in
                        DevicePlatformCard(platform: platform) {
                            session.platform = platform
                            session.start()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("iOS requires Xcode and Apple Silicon. Android uses your local emulators and connected ADB devices.")
                    Text("Local previews require Node.js 20+. Android also requires SDK Platform-Tools.")
                }
                .font(.caption).foregroundStyle(.secondary)

                Divider()
                networkConnection
                Divider()
                existingBridge
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var networkConnection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Android over network", systemImage: "network")
                .font(.headline)
            Text("Connect an emulator or device on the same network. No local emulator required.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Device address").font(.callout.weight(.medium))
                TextField("192.168.3.172:55555", text: $androidAddress)
                    .appTextField()
                    .accessibilityLabel("Android ADB device address")
                    .accessibilityIdentifier("workspace.devices.android.address")
                    .onSubmit(connectAndroid)
                Text("Use the ADB connection port exposed by the device or emulator host.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Connect Android", action: connectAndroid)
                .appPrimaryButton()
                .disabled(androidAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("workspace.devices.android.connect")

            DisclosureGroup("Connection help", isExpanded: $showsHelp) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enable ADB over TCP/IP on the remote device, and allow this Mac to debug it. Check the host's forwarded port and firewall if the connection is refused.")
                    Text("For Android Wireless debugging, pair this Mac in Terminal first using the pairing address and code shown on the device:")
                    Text("adb pair <host>:<pairing-port>").font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Then enter the separate connection address above. The pairing port and a web preview URL are different from the ADB connection port.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }
            .font(.callout)
        }
    }

    private var existingBridge: some View {
        DisclosureGroup("Existing local bridge", isExpanded: $showsBridge) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Already running a preview bridge on this Mac? Connect to its HTTP URL here.")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("Platform", selection: $session.platform) {
                    ForEach(DevicePlatform.allCases) { Text($0.rawValue).tag($0) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bridge URL").font(.callout.weight(.medium))
                    TextField("http://127.0.0.1:3200", text: $bridgeAddress).appTextField()
                        .accessibilityLabel("Local preview bridge URL")
                }
                Button("Connect bridge") { session.connect(bridgeAddress) }.appSecondaryButton()
                Text("Run in Terminal:").font(.caption).foregroundStyle(.secondary)
                Text("npx --yes \(session.platform.package) --host 127.0.0.1 --codec auto --panes none")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 12)
        }
        .font(.callout)
    }

    private func connectAndroid() {
        guard !androidAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session.connectAndroid(androidAddress)
    }
}

private struct DevicePlatformCard: View {
    let platform: DevicePlatform
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    if platform == .iOS {
                        Image(systemName: "apple.logo").font(.system(size: 32, weight: .medium))
                    } else {
                        AndroidDeviceLogo().fill(Color.fromHex(colorScheme == .dark ? 0xc8e2ae : 0x466e36), style: FillStyle(eoFill: true))
                            .frame(width: 42, height: 34)
                    }
                }
                .frame(height: 36, alignment: .leading).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(platform == .iOS ? "iOS Simulator" : "Android").font(.headline)
                    Text(platform == .iOS ? "Simulators on this Mac" : "Emulators & ADB devices")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack {
                    Text("Open \(platform.rawValue)")
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                }.font(.callout.weight(.medium))
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .desktopPanel(isSelected: isHovered || isFocused)
        .onHover { isHovered = $0 }
        .focused($isFocused)
        .accessibilityLabel("Open \(platform.rawValue) devices")
        .accessibilityIdentifier("workspace.devices.start.\(platform.id)")
    }
}

/// Android's familiar robot head, drawn as a scalable mark with transparent eyes.
private struct AndroidDeviceLogo: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 3, y: 76))
        path.addCurve(to: CGPoint(x: 97, y: 76), control1: CGPoint(x: 3, y: 12), control2: CGPoint(x: 97, y: 12))
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: 25, y: 51, width: 7, height: 7))
        path.addEllipse(in: CGRect(x: 68, y: 51, width: 7, height: 7))
        for x in [25.0, 75.0] {
            let direction = x < 50 ? -1.0 : 1.0
            path.move(to: CGPoint(x: x, y: 39))
            path.addLine(to: CGPoint(x: x + direction * 12, y: 17))
            path.addQuadCurve(to: CGPoint(x: x + direction * 16, y: 19),
                              control: CGPoint(x: x + direction * 16, y: 14))
            path.addLine(to: CGPoint(x: x + direction * 4, y: 41))
            path.closeSubpath()
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 100, y: rect.height / 85)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}
#endif
