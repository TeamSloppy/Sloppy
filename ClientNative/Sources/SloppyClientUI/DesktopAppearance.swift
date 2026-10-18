import SwiftUI

/// Shared desktop surfaces. Mobile and spatial controls keep their native treatment.
public extension View {
    @ViewBuilder
    func appSurface<S: InsettableShape>(_ glass: Glass = .regular, in shape: S) -> some View {
#if os(macOS)
        modifier(DesktopPanelSurface(shape: shape))
#else
        backportGlassEffect(glass, in: shape)
#endif
    }

    @ViewBuilder
    func desktopPanel(cornerRadius: CGFloat = 12, isSelected: Bool = false) -> some View {
#if os(macOS)
        modifier(DesktopPanelSurface(shape: RoundedRectangle(cornerRadius: cornerRadius), isSelected: isSelected))
#else
        self
#endif
    }

    @ViewBuilder
    func desktopContentWidth(_ width: CGFloat = 1120) -> some View {
#if os(macOS)
        frame(maxWidth: width, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
#else
        self
#endif
    }

    @ViewBuilder
    func desktopScreenStyle() -> some View {
#if os(macOS)
        modifier(DesktopScreenStyle())
#else
        self
#endif
    }

    @ViewBuilder
    func appPrimaryButton(glass: Bool = false) -> some View {
#if os(macOS)
        buttonStyle(DesktopPrimaryButtonStyle())
#else
        if glass {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
#endif
    }

    @ViewBuilder
    func appSecondaryButton() -> some View {
#if os(macOS)
        buttonStyle(.bordered)
#else
        buttonStyle(.glass)
#endif
    }
}

private struct DesktopPanelSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var isSelected = false
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .background(isSelected ? theme.colors.surfaceRaised : theme.colors.surface, in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? theme.colors.borderBold : theme.colors.border, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct DesktopScreenStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(theme.colors.textPrimary)
            .tint(theme.colors.accent)
            .accentColor(theme.colors.accent)
            .background(theme.colors.background)
    }
}

private struct DesktopPrimaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(theme.colors.background)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                configuration.role == .destructive ? theme.colors.statusBlocked : theme.colors.textPrimary,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
