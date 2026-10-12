import Foundation
import SwiftUI
import SloppyClientCore

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

#if os(macOS)
@MainActor
final class AppKitHostedTranscriptItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("chat.native-transcript.hosted-item")
    private var hostingController: NSHostingController<AnyView>?
    private var hostingConstraints: [NSLayoutConstraint] = []
    private var measuredHeight: CGFloat = 0
    private var measuredWidth: CGFloat?
    private var measurementKey: String?
    private var measurementGeneration: UInt = 0
    private var needsSynchronousMeasurement = true
    private(set) var synchronousMeasurementPasses = 0
    var onHeightMeasured: (@MainActor (CGFloat) -> Void)?
    var onHeightChange: (@MainActor () -> Void)?

    override func loadView() {
        view = NSView()
    }

    func configure(
        rootView: AnyView,
        measurementKey: String? = nil,
        cachedHeight: CGFloat? = nil,
        requiresMeasurement: Bool = false
    ) {
        let changedItem = measurementKey != nil && measurementKey != self.measurementKey
        if measurementKey == nil || changedItem || requiresMeasurement {
            self.measurementKey = measurementKey
            if changedItem || measurementKey == nil { measuredHeight = 0 }
            measuredWidth = nil
            needsSynchronousMeasurement = true
        }
        if let cachedHeight, cachedHeight.isFinite, cachedHeight > 0 {
            measuredHeight = cachedHeight
            measuredWidth = nil
            needsSynchronousMeasurement = false
        }
        measurementGeneration &+= 1
        let generation = measurementGeneration
        let measuredRoot = AnyView(rootView.onGeometryChange(for: CGFloat.self) { geometry in
            ceil(geometry.size.height)
        } action: { [weak self] height in
            guard let self, self.measurementGeneration == generation,
                  height.isFinite, height > 0 else { return }
            self.needsSynchronousMeasurement = false
            let heightChanged = abs(self.measuredHeight - height) > 0.5
            self.measuredHeight = height
            self.onHeightMeasured?(height)
            guard heightChanged else { return }
            // Geometry callbacks run inside SwiftUI layout; invalidate on the next turn.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.measurementGeneration == generation else { return }
                if let onHeightChange = self.onHeightChange {
                    onHeightChange()
                } else {
                    let context = NSCollectionViewLayoutInvalidationContext()
                    if let indexPath = self.collectionView?.indexPath(for: self) {
                        context.invalidateItems(at: [indexPath])
                        self.collectionView?.collectionViewLayout?.invalidateLayout(with: context)
                    }
                }
            }
        })
        if let hostingController, !changedItem {
            hostingController.rootView = measuredRoot
            return
        }
        if let hostingController {
            NSLayoutConstraint.deactivate(hostingConstraints)
            hostingController.view.removeFromSuperview()
            hostingController.removeFromParent()
        }
        let hostingController = NSHostingController(rootView: measuredRoot)
        // The collection owns row sizing. Avoid an independent Auto Layout
        // intrinsic-size measurement on every SwiftUI geometry change.
        hostingController.sizingOptions = []
        addChild(hostingController)
        let hostingView = hostingController.view
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        hostingConstraints = [
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
        NSLayoutConstraint.activate(hostingConstraints)
        self.hostingController = hostingController
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: NSCollectionViewLayoutAttributes
    ) -> NSCollectionViewLayoutAttributes {
        guard let attributes = layoutAttributes.copy() as? NSCollectionViewLayoutAttributes else {
            return layoutAttributes
        }
        let widthChanged = measuredWidth.map { abs($0 - attributes.size.width) > 0.5 } ?? false
        if !needsSynchronousMeasurement, !widthChanged, measuredHeight > 0 {
            measuredWidth = attributes.size.width
            attributes.size.height = measuredHeight
            return attributes
        }
        guard let hostingController else { return layoutAttributes }
        synchronousMeasurementPasses += 1
        let height = ceil(hostingController.sizeThatFits(in: NSSize(
            width: max(attributes.size.width, 1), height: CGFloat.greatestFiniteMagnitude
        )).height)
        if height.isFinite && height > 0 {
            measuredHeight = height
            measuredWidth = attributes.size.width
            needsSynchronousMeasurement = false
            attributes.size.height = height
            onHeightMeasured?(height)
        }
        return attributes
    }
}
#endif
