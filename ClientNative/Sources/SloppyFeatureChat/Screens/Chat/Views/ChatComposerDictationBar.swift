import Foundation
import Observation
import SwiftUI
import SloppyClientUI
import SloppyClientCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif


struct DictationComposerBar: View {
    let phase: ChatComposerDictationPhase
    let levels: [CGFloat]
    let elapsed: TimeInterval
    let stop: @MainActor () -> Void

    @Environment(\.theme) private var theme

    private let elapsedTextWidth: CGFloat = 64
    private let stopButtonSize: CGFloat = 32

    private var trailingControlsWidth: CGFloat {
        elapsedTextWidth + theme.spacing.s + stopButtonSize
    }

    private var isRecording: Bool {
        phase == .recording
    }

    private var elapsedText: String {
        let totalSeconds = Int(elapsed.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: theme.spacing.s) {
            if isRecording {
                waveformViewport
                    .scaleEffect(x: -1)
            } else {
                Spacer(minLength: 0)
            }
            trailingControls
        }
        .padding(.trailing, theme.spacing.s)
        .padding(.leading, theme.spacing.m)
        .frame(
            maxWidth: .infinity,
            minHeight: ChatComposerView.panelHeight,
            maxHeight: ChatComposerView.panelHeight
        )
        .backportGlassEffect(
            .regular.tint(Color.fromHex(0x1C1C1E)),
            in: .capsule
        )
    }

    private var waveformViewport: some View {
        Color.clear
            .frame(maxWidth: .infinity, alignment: .trailing)
            .overlay(alignment: .trailing) {
                waveformView
                    .allowsHitTesting(false)
            }
            .clipped()
    }

    @ViewBuilder
    private var trailingControls: some View {
        if isRecording {
            HStack(spacing: theme.spacing.s) {
                Text(elapsedText)
                    .font(.system(size: theme.typography.body, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.fromHex(0xFF5A64))
                    .monospacedDigit()
                    .frame(width: elapsedTextWidth, alignment: .trailing)

                Button(action: stop) {
                    ZStack {
                        Circle()
                            .fill(Color.fromHex(0x8E2F35))
                        Icons.symbol(.stop, size: theme.typography.body)
                            .foregroundColor(Color.fromHex(0xFF7078))
                    }
                    .frame(
                        width: stopButtonSize,
                        height: stopButtonSize
                    )
                }
                .buttonStyle(.plain)
                
            }
            .frame(width: trailingControlsWidth, alignment: .trailing)
        } else {
            Text("Transcribing…")
                .font(.system(size: theme.typography.body, weight: .semibold))
                .foregroundColor(Color.fromHex(0xFF5A64))
        }
    }

    private var waveformView: some View {
        HStack(spacing: 3) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.fromHex(0xFF4D57).opacity(isRecording ? 0.92 : 0.38))
                    .frame(width: 3, height: 6 + levels[index] * 14)
            }
        }
        .animation(.easeOut(duration: 0.12), value: levels)
    }
}

extension BinaryFloatingPoint {
    func clamp(_ minValue: Self, _ maxValue: Self) -> Self {
        max(min(self, maxValue), minValue)
    }
}
