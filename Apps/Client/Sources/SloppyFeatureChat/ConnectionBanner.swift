import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct ConnectionBanner: View {
    public let state: ConnectionState

    public init(state: ConnectionState) {
        self.state = state
    }

    @Environment(\.theme) private var theme

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        let (label, color): (String, Color) = switch state {
        case .disconnected: ("CONNECTION LOST", c.statusBlocked)
        case .reconnecting: ("RECONNECTING...", c.statusWarning)
        case .connected:    ("CONNECTED", c.statusDone)
        }

        return HStack(spacing: sp.s) {
            Color.clear
                .frame(width: 6, height: 6)
                .background(color)
            Text(label)
                .font(.system(size: ty.micro))
                .foregroundColor(color)
        }
        .padding(.horizontal, sp.m)
        .padding(.vertical, sp.xs)
        .background(color.opacity(0.1 as Float))
        .border(color.opacity(0.3 as Float), lineWidth: 1)
    }
}
