import SwiftUI

// MARK: - Numeric bridging

public extension BinaryFloatingPoint {
    var cg: CGFloat { CGFloat(Double(self)) }
}

public extension View {
    @_disfavoredOverload
    func frame(
        minWidth: Float? = nil,
        maxWidth: Float? = nil,
        minHeight: Float? = nil,
        maxHeight: Float? = nil,
        alignment: Alignment = .center
    ) -> some View {
        frame(
            minWidth: minWidth.map { CGFloat($0) },
            maxWidth: maxWidth.map { CGFloat($0) },
            minHeight: minHeight.map { CGFloat($0) },
            maxHeight: maxHeight.map { CGFloat($0) },
            alignment: alignment
        )
    }

    @_disfavoredOverload
    func frame(width: Float, height: Float? = nil, alignment: Alignment = .center) -> some View {
        if let height {
            frame(width: CGFloat(width), height: CGFloat(height), alignment: alignment)
        } else {
            frame(width: CGFloat(width), alignment: alignment)
        }
    }

    func border(_ color: Color, lineWidth: CGFloat) -> some View {
        overlay {
            Rectangle()
                .strokeBorder(color, lineWidth: lineWidth)
        }
    }

    func onTap(_ action: @escaping @MainActor () -> Void) -> some View {
        onTapGesture(perform: action)
    }

    func opacity(_ value: Float) -> some View {
        opacity(Double(value))
    }
}

// MARK: - Glass effect

public enum GlassPreset: Sendable {
    case material
    case none

    public func tint(_ color: Color) -> GlassEffect {
        GlassEffect(style: self, tint: color)
    }
}

public struct GlassEffect: Sendable {
    let style: GlassPreset
    let tint: Color?

    public static var regular: GlassEffect { GlassEffect(style: .material, tint: nil) }
    public static var identity: GlassEffect { GlassEffect(style: .none, tint: nil) }

    public func tint(_ color: Color) -> GlassEffect {
        GlassEffect(style: style, tint: color)
    }
}

public enum GlassShape {
    case rect(cornerRadius: CGFloat)
    case capsule

    @ViewBuilder
    func backgroundMaterial<Content: View>(_ content: Content, tint: Color?) -> some View {
        switch self {
        case .rect(let radius):
            if let tint {
                content.background {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(tint)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
                }
            } else {
                content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            }
        case .capsule:
            if let tint {
                content.background {
                    Capsule()
                        .fill(tint)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            } else {
                content.background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}

public extension View {
    @ViewBuilder
    func glassEffect(_ effect: GlassEffect, in shape: GlassShape) -> some View {
        switch effect.style {
        case .none:
            self
        case .material:
            shape.backgroundMaterial(self, tint: effect.tint)
        }
    }

    @ViewBuilder
    func glassEffect<S: InsettableShape>(_ effect: GlassEffect, in shape: S) -> some View {
        switch effect.style {
        case .none:
            self
        case .material:
            if let tint = effect.tint {
                background {
                    shape.fill(tint)
                        .background(.ultraThinMaterial, in: shape)
                }
            } else {
                background(.ultraThinMaterial, in: shape)
            }
        }
    }

    func glassEffect(_ effect: GlassPreset, in shape: GlassShape) -> some View {
        glassEffect(GlassEffect(style: effect, tint: nil), in: shape)
    }
}

public enum UIClipboard {
    public static func setString(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = value
        #endif
    }
}

// MARK: - Overlay alignment

public extension View {
    func overlay(
        anchor: Alignment,
        @ViewBuilder content: () -> some View
    ) -> some View {
        overlay(alignment: anchor, content: content)
    }
}

// MARK: - Navigation chrome

public extension View {
    func navigationBarLeadingItems<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .navigation) {
                content()
            }
        }
    }

    func navigationBarTrailingItems<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                content()
            }
        }
    }

    func navigationTitlePosition(_ position: NavigationTitlePosition) -> some View {
        switch position {
        case .leading:
            toolbarTitleDisplayMode(.inline)
        case .center:
            toolbarTitleDisplayMode(.automatic)
        }
    }
}

public enum NavigationTitlePosition: Sendable {
    case leading
    case center
}

// MARK: - Scroll helpers

public extension ScrollViewProxy {
    func isNearBottom(threshold: Float) -> Bool {
        _ = threshold
        return true
    }
}

// MARK: - Screen / idiom

public enum UserInterfaceIdiom: Sendable {
    case phone
    case pad
    case desktop
}

private struct UserInterfaceIdiomKey: EnvironmentKey {
    static let defaultValue: UserInterfaceIdiom = {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone ? .phone : .pad
        #else
        return .desktop
        #endif
    }()
}

public extension EnvironmentValues {
    var userInterfaceIdiom: UserInterfaceIdiom {
        get { self[UserInterfaceIdiomKey.self] }
        set { self[UserInterfaceIdiomKey.self] = newValue }
    }
}

public enum Screen {
    public static var main: ScreenMetrics? {
        #if os(macOS)
        guard let frame = NSScreen.main?.frame else { return nil }
        return ScreenMetrics(width: Float(frame.width), height: Float(frame.height))
        #elseif os(iOS)
        let bounds = UIScreen.main.bounds
        return ScreenMetrics(width: Float(bounds.width), height: Float(bounds.height))
        #else
        return nil
        #endif
    }
}

public struct ScreenMetrics: Sendable {
    public var size: CGSize

    public init(width: Float, height: Float) {
        size = CGSize(width: CGFloat(width), height: CGFloat(height))
    }
}

// MARK: - Safe area

private struct SafeAreaInsetsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}

public extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        get { self[SafeAreaInsetsKey.self] }
        set { self[SafeAreaInsetsKey.self] = newValue }
    }
}

public struct SafeAreaReader: ViewModifier {
    public func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SafeAreaInsetsPreferenceKey.self, value: proxy.safeAreaInsets)
            }
        }
        .onPreferenceChange(SafeAreaInsetsPreferenceKey.self) { _ in }
    }
}

private struct SafeAreaInsetsPreferenceKey: PreferenceKey {
    static let defaultValue = EdgeInsets()

    static func reduce(value: inout EdgeInsets, nextValue: () -> EdgeInsets) {
        value = nextValue()
    }
}

public struct SafeAreaInsetsInjector: ViewModifier {
    @State private var insets = EdgeInsets()

    public func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { insets = proxy.safeAreaInsets }
                        .onChange(of: proxy.safeAreaInsets) { _, newValue in
                            insets = newValue
                        }
                }
            }
            .environment(\.safeAreaInsets, insets)
    }
}

public extension View {
    func injectSafeAreaInsets() -> some View {
        modifier(SafeAreaInsetsInjector())
    }
}

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
