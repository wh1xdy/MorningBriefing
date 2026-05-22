import AppKit
import SwiftUI

private let panelWidth:  CGFloat = 560
private let panelHeight: CGFloat = 640

final class BriefingPanelController {
    private var panel: NSPanel?

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
            rootView: ExpandedView(briefingVM: briefingVM, chatVM: chatVM) {
                p.close()
            }
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

private struct ExpandedView: View {
    @ObservedObject var briefingVM: BriefingViewModel
    @ObservedObject var chatVM:     ChatViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GradientBackground()

            HStack(spacing: 0) {
                PopoverView(vm: briefingVM)
                    .frame(width: 360)
                Divider().opacity(0.25)
                ChatView(
                    vm: chatVM,
                    briefingVM: briefingVM,
                    onExpand: { /* already expanded */ }
                )
                .frame(width: 200)
            }

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .frame(width: panelWidth, height: panelHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .background(WindowDragArea())
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ v: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
