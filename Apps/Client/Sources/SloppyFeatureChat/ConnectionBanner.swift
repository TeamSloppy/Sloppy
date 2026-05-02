import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct ConnectionBanner: View {
    public let state: ConnectionState
    public let endpoint: String?
    public let message: String?

    public init(state: ConnectionState, endpoint: String? = nil, message: String? = nil) {
        self.state = state
        self.endpoint = endpoint
        self.message = message
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

        return VStack(alignment: .leading, spacing: sp.xs) {
            HStack(spacing: sp.s) {
                Color.clear
                    .frame(width: 6, height: 6)
                    .background(color)
                Text(label)
                    .font(.system(size: ty.micro))
                    .foregroundColor(color)
            }

            if let endpoint {
                Text(endpoint)
                    .font(.system(size: ty.micro))
                    .foregroundColor(c.textMuted)
            }

            if let message {
                Text(message)
                    .font(.system(size: ty.micro))
                    .foregroundColor(c.textSecondary)
            }
        }
        .padding(.horizontal, sp.m)
        .padding(.vertical, sp.xs)
        .background(color.opacity(0.1 as Float))
        .border(color.opacity(0.3 as Float), lineWidth: 1)
    }
}
