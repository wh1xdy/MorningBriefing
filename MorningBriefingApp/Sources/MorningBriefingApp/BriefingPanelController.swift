import AppKit
import SwiftUI

private let panelWidth:  CGFloat = 400
private let panelHeight: CGFloat = 600

final class BriefingPanelController {
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible == true }

    func closeIfVisible() {
        panel?.close()
    }

    func show(briefingVM: BriefingViewModel, chatVM: ChatViewModel) {
        if let existing = panel, existing.isVisible {
            existing.orderFront(nil)
            return
        }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask:   [.nonactivatingPanel, .borderless],
            backing:     .buffered,
            defer:       false
        )
        p.level                       = .floating
        p.isReleasedWhenClosed        = false
        p.isOpaque                    = false
        p.backgroundColor             = .clear
        p.hasShadow                   = true
        p.isMovableByWindowBackground = true

        let hosting = NSHostingController(
            rootView: MainPopoverView(
                briefingVM: briefingVM,
                chatVM: chatVM,
                onExpand: { p.close() }
            )
        )
        hosting.view.wantsLayer           = true
        hosting.view.layer?.cornerRadius  = 16
        hosting.view.layer?.masksToBounds = true

        p.contentViewController = hosting
        centerOnScreen(p)
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    private func centerOnScreen(_ p: NSPanel) {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        p.setFrameOrigin(NSPoint(
            x: frame.midX - panelWidth  / 2,
            y: frame.midY - panelHeight / 2
        ))
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ v: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
