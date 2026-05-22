import AppKit
import SwiftUI

private let panelWidth:  CGFloat = 400
private let panelHeight: CGFloat = 600

final class BriefingPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible == true }

    func closeIfVisible() {
        guard let p = panel, p.isVisible else { return }
        Self.fadeClose(p)
    }

    func show(briefingVM: BriefingViewModel, chatVM: ChatViewModel) {
        if let existing = panel, existing.isVisible {
            existing.orderFront(nil)
            return
        }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask:   [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        p.titlebarAppearsTransparent = true
        p.titleVisibility            = .hidden
        p.isReleasedWhenClosed       = false
        p.isOpaque                   = false
        p.backgroundColor            = .clear
        p.hasShadow                  = true
        p.isMovableByWindowBackground = true
        p.delegate                   = self

        let hosting = NSHostingController(
            rootView: MainPopoverView(
                briefingVM: briefingVM,
                chatVM: chatVM,
                onExpand: {},       // native close button is used
                isDetached: true
            )
        )
        hosting.view.wantsLayer           = true
        hosting.view.layer?.cornerRadius  = 16
        hosting.view.layer?.masksToBounds = true

        p.contentViewController = hosting
        centerOnScreen(p)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        panel = p

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration        = 0.22
            ctx.timingFunction  = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }
    }

    // Called when user clicks the native red close button
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let p = sender as? NSPanel else { return true }
        Self.fadeClose(p)
        return false
    }

    private static func fadeClose(_ p: NSPanel) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
            p.alphaValue = 1
        })
    }

    private func centerOnScreen(_ p: NSPanel) {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        p.setFrameOrigin(NSPoint(
            x: frame.midX - panelWidth  / 2,
            y: frame.midY - panelHeight / 2
        ))
    }
}
