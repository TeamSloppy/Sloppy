#if os(macOS)
import Foundation
import AppKit
import SwiftUI
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyFeatureChat

@Suite("Tool approval card layout", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct ToolApprovalCardLayoutTests {
    @Test("short commands keep the approval card compact")
    func compactCommand() {
        _ = NSApplication.shared
        let approval = PendingToolApprovalRecord(id: "short", status: "pending", tool: "runtime.exec",
            arguments: ["command": .string("git"), "arguments": .array([.string("status"), .string("--short")])],
            updatedAt: Date())
        let controller = NSHostingController(rootView:
            ChatToolApprovalCard(approval: approval, isResolving: false, errorMessage: nil, decide: { _, _ in })
                .environment(\.theme, .sloppyDark).frame(width: 760))
        let size = controller.sizeThatFits(in: NSSize(width: 760, height: 10_000))
        #expect(size.height < 280)
        #expect(size.height > 80)
    }

    @Test("the full script stays inspectable and actions keep their scopes", arguments: [CGFloat(360), 760])
    func fullCommandAndActions(width: CGFloat) async throws {
        _ = NSApplication.shared
        AppKitTestAccessibility.enable()
        let script = (0..<50).map { "echo line-\($0)" }.joined(separator: "\n") + "\necho APPROVAL_SCRIPT_END"
        let approval = PendingToolApprovalRecord(id: "command", status: "pending", tool: "runtime.exec",
            arguments: ["command": .string("/bin/bash"), "arguments": .array([.string("-lc"), .string(script)]),
                        "cwd": .string("/work/My Project")], reason: "Inspect the project", updatedAt: Date())
        var choices: [(Bool, ClientToolApprovalDecisionScope)] = []
        let content = ChatToolApprovalCard(approval: approval, isResolving: false, errorMessage: nil) {
            choices.append(($0, $1))
        }
        .environment(\.theme, .sloppyDark)
        .preferredColorScheme(.dark)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 480)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        if let directory = ProcessInfo.processInfo.environment["SLOPPY_TOOL_APPROVAL_PROOF_DIR"] {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("approval-\(Int(width)).png"))
        }
        let command = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.tool-approval.command"))
        let label = attribute("accessibilityValue", of: command) as? String
            ?? attribute("accessibilityLabel", of: command) as? String ?? ""
        #expect(label.contains("/bin/bash -lc"))
        #expect(label.contains("APPROVAL_SCRIPT_END"))
        let cwd = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.tool-approval.cwd")
                               ?? textElement(in: host.accessibilityChildren() ?? [], containing: "Working directory: /work/My Project"))
        let cwdLabel = attribute("accessibilityLabel", of: cwd) as? String
            ?? attribute("accessibilityValue", of: cwd) as? String ?? ""
        #expect(cwdLabel.contains("/work/My Project"))
        let contentFrame = window.convertToScreen(host.convert(host.bounds, to: nil))
        let cwdFrame = try #require(AppKitTestAccessibility.frame(of: cwd))
        #expect(cwdFrame.minY >= contentFrame.minY && cwdFrame.maxY <= contentFrame.maxY)
        let fitted = host.fittingSize
        #expect(fitted.height > 180 && fitted.height < 480)
        #expect(fitted.width <= width + 1)

        let scroll = try #require(nestedScroll(in: host))
        let document = try #require(scroll.documentView)
        let originalHeight = document.frame.height
        #expect(originalHeight > scroll.contentSize.height * 2)
        for fraction: CGFloat in [1, 0, 1, 0] {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, originalHeight - scroll.contentSize.height) * fraction))
            scroll.reflectScrolledClipView(scroll.contentView)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            #expect(abs(document.frame.height - originalHeight) <= 1)
        }

        for (identifier, scope) in [("once", ClientToolApprovalDecisionScope.once), ("session", .session), ("always", .always)] {
            let button = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.tool-approval.\(identifier)"))
            let frame = try #require(AppKitTestAccessibility.frame(of: button))
            #expect(frame.width > 0 && frame.minX >= contentFrame.minX - 1 && frame.maxX <= contentFrame.maxX + 1)
            #expect(AppKitTestAccessibility.press(button))
            #expect(choices.last?.0 == true)
            #expect(choices.last?.1 == scope)
        }
        let deny = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.tool-approval.deny"))
        #expect(AppKitTestAccessibility.press(deny))
        #expect(choices.last?.0 == false)
        #expect(choices.count == 4)
    }

    private func attribute(_ name: String, of object: NSObject) -> Any? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    private func nestedScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.nestedScroll(in: $0) }.first
    }

    private func textElement(in elements: [Any], containing text: String) -> NSObject? {
        for case let element as NSObject in elements {
            if let child = textElement(in: attribute("accessibilityChildren", of: element) as? [Any] ?? [], containing: text) {
                return child
            }
            for name in ["accessibilityLabel", "accessibilityValue"] {
                if let value = attribute(name, of: element) as? String, value.contains(text) { return element }
            }
        }
        return nil
    }
}
#endif
