#if os(macOS)
import CoreImage.CIFilterBuiltins
import QuartzCore
import WebKit

@MainActor
final class BrowserToolbarBackdrop {
    private static let fadeHeight: CGFloat = 32
    private weak var webView: WKWebView?
    private let blurLayer = CALayer()
    private let fade = CAGradientLayer()
    private let previousFilterRendering: Bool
    private var boundsObservation: NSKeyValueObservation?
    private var toolbarHeight: CGFloat = 0

    static func unobscuredContentInset(for toolbarHeight: CGFloat) -> CGFloat {
        guard toolbarHeight > 0 else { return 0 }
        return toolbarHeight + fadeHeight + 8
    }

    init(webView: WKWebView) {
        self.webView = webView
        previousFilterRendering = webView.layerUsesCoreImageFilters
        webView.wantsLayer = true
        webView.layerUsesCoreImageFilters = true
        let blur = CIFilter.gaussianBlur()
        blur.radius = 12
        let clamp = CIFilter.affineClamp()
        clamp.transform = .identity
        blurLayer.backgroundFilters = [clamp, blur]
        blurLayer.masksToBounds = true
        blurLayer.zPosition = 1000
        blurLayer.mask = fade
        fade.colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 0)]
        webView.layer?.addSublayer(blurLayer)
        boundsObservation = webView.layer?.observe(\.bounds, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.layout() }
        }
    }

    func update(toolbarHeight: CGFloat, enabled: Bool) {
        self.toolbarHeight = max(0, toolbarHeight)
        blurLayer.isHidden = !enabled || toolbarHeight <= 0
        layout()
    }

    func detach() {
        boundsObservation?.invalidate()
        boundsObservation = nil
        blurLayer.removeFromSuperlayer()
        webView?.layerUsesCoreImageFilters = previousFilterRendering
    }

    private func layout() {
        guard let host = webView?.layer else { return }
        let height = min(host.bounds.height, toolbarHeight + Self.fadeHeight)
        let flipped = host.isGeometryFlipped
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        blurLayer.frame = CGRect(x: host.bounds.minX, y: flipped ? host.bounds.minY : host.bounds.maxY - height,
                                 width: host.bounds.width, height: height)
        fade.frame = blurLayer.bounds
        fade.startPoint = CGPoint(x: 0.5, y: flipped ? 0 : 1)
        fade.endPoint = CGPoint(x: 0.5, y: flipped ? 1 : 0)
        fade.locations = [0, NSNumber(value: Double(toolbarHeight / max(1, height))), 1]
        CATransaction.commit()
    }
}
#endif
