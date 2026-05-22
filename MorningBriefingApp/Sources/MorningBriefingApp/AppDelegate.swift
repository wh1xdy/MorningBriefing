import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem:      NSStatusItem!
    private var popover:         NSPopover!
    private var panelController: BriefingPanelController!
    private var briefingVM:      BriefingViewModel!
    private var chatVM:          ChatViewModel!
    private var appNapToken:     NSObjectProtocol?

    /// Single source of truth for which popover is visible. Never set directly —
    /// use showPopover(_:) and closeActivePopover().
    private weak var activePopover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent App Nap so timers and file watchers stay accurate in the background
        appNapToken = ProcessInfo.processInfo.beginActivity(
            options: [.background, .latencyCritical],
            reason: "MorningBriefing menubar app"
        )
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            briefingVM      = BriefingViewModel()
            chatVM          = ChatViewModel()
            panelController = BriefingPanelController()
            buildStatusItem()
            buildPopovers()
            briefingVM.loadCachedIfAvailable()
        }
        observeWake()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: – Mutual exclusion

    /// Close whatever is open, then open `popover`. No-op if it is already shown.
    private func showPopover(_ popover: NSPopover) {
        panelController.closeIfVisible()
        guard let btn = statusItem.button else { return }
        if let active = activePopover, active !== popover {
            active.close()
        }
        guard !popover.isShown else { return }
        popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        activePopover = popover
    }

    private func closeActivePopover() {
        activePopover?.close()
        activePopover = nil
    }

    // MARK: – Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let btn = statusItem.button else { return }
        btn.image   = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "MorningBriefing")
        btn.action  = #selector(statusItemClicked)
        btn.target  = self

        Task { @MainActor [weak self] in
            guard let self else { return }
            for await label in self.briefingVM.$currentPriceLabel.values {
                await MainActor.run { self.updateBadge(label) }
            }
        }
    }

    private func updateBadge(_ price: String?) {
        guard let btn = statusItem.button else { return }
        if let p = price {
            btn.title = " \(p)"
            btn.imagePosition = .imageLeft
        } else {
            btn.title = ""
        }
    }

    // MARK: – Popovers

    private func buildPopovers() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 520)
        popover.behavior    = .transient
        popover.animates    = true
        popover.contentViewController = NSHostingController(
            rootView: MainPopoverView(
                briefingVM: briefingVM,
                chatVM: chatVM,
                onExpand: { [weak self] in self?.openPanel() }
            )
        )
    }

    @objc private func statusItemClicked() {
        if panelController.isVisible {
            panelController.closeIfVisible()
            return
        }
        if popover.isShown {
            closeActivePopover()
        } else {
            showPopover(popover)
        }
    }

    private func openPanel() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.closeActivePopover()
            self.panelController.show(briefingVM: self.briefingVM, chatVM: self.chatVM)
        }
    }

    // MARK: – Wake trigger

    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func didWake() {
        MainActor.assumeIsolated { briefingVM.triggerBriefingIfNeeded() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.showPopover(self.popover)
        }
    }
}
