//
//  Extensions.swift
//  SloppyClient
//
//  Created by Vladislav Prusakov on 12.07.2026.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

enum HapticImpactStyle: Sendable {
    case light
    case medium
    case heavy
    case soft
    case rigid
}

enum HapticNotificationType: Sendable {
    case success
    case warning
    case error
}

struct HapticFeedback: Sendable {
    @MainActor
    func impact(_ style: HapticImpactStyle = .medium, intensity: CGFloat = 1) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: style.uiKitStyle)
        generator.prepare()
        generator.impactOccurred(intensity: min(max(intensity, 0), 1))
        #endif
    }

    @MainActor
    func selection() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }

    @MainActor
    func notification(_ type: HapticNotificationType) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type.uiKitType)
        #endif
    }
}

private struct HapticFeedbackKey: EnvironmentKey {
    static let defaultValue = HapticFeedback()
}

extension EnvironmentValues {
    var hapticFeedback: HapticFeedback {
        get { self[HapticFeedbackKey.self] }
        set { self[HapticFeedbackKey.self] = newValue }
    }
}

#if os(iOS)
private extension HapticImpactStyle {
    var uiKitStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light: .light
        case .medium: .medium
        case .heavy: .heavy
        case .soft: .soft
        case .rigid: .rigid
        }
    }
}

private extension HapticNotificationType {
    var uiKitType: UINotificationFeedbackGenerator.FeedbackType {
        switch self {
        case .success: .success
        case .warning: .warning
        case .error: .error
        }
    }
}
#endif
