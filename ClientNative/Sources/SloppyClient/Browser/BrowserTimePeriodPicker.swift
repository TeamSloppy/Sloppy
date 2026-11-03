#if os(macOS)
import AppKit
import SwiftUI

/// SwiftUI's macOS segmented picker keeps its intrinsic width inside a ScrollView.
@MainActor
struct BrowserTimePeriodPicker: NSViewRepresentable {
    @Binding var week: Bool

    func makeCoordinator() -> Coordinator { Coordinator(week: $week) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ["Today", "This week"], trackingMode: .selectOne,
            target: context.coordinator, action: #selector(Coordinator.selectPeriod(_:)))
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setAccessibilityLabel("Period")
        control.setAccessibilityIdentifier("browser-time-period")
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.week = $week
        control.selectedSegment = week ? 1 : 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var week: Binding<Bool>

        init(week: Binding<Bool>) { self.week = week }

        @objc func selectPeriod(_ sender: NSSegmentedControl) {
            week.wrappedValue = sender.selectedSegment == 1
        }
    }
}
#endif
