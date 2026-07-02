import AppKit
import SwiftUI
import UserNotifications

extension Notification.Name {
    static let mbPopoverWillOpen = Notification.Name("MBPopoverWillOpen")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover:    NSPopover!
    private var briefingVM: BriefingViewModel!
    private var chatVM:     ChatViewModel!
    private var appNapToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appNapToken = ProcessInfo.processInfo.beginActivity(
            options: [.background, .latencyCritical],
            reason: "MorningBriefing menubar app"
        )
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            briefingVM = BriefingViewModel()
            chatVM     = ChatViewModel()
            buildStatusItem()
            buildPopover()
            briefingVM.loadCachedIfAvailable()
        }
        observeWake()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    // MARK: – Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let btn = statusItem.button else { return }
        btn.image   = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "MorningBriefing")
        btn.action  = #selector(statusItemClicked)
        btn.target  = self
        btn.toolTip = "MorningBriefing"

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

    // MARK: – Popover

    private func buildPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 520)   // initial; overridden by content
        popover.behavior    = .transient
        popover.animates    = false   // our content spring replaces this; native scale + spring = flicker
        let host = NSHostingController(
            rootView: ContentView(briefingVM: briefingVM, chatVM: chatVM)
        )
        // Let the popover follow SwiftUI's intrinsic height so a short briefing
        // doesn't leave dead space at the bottom (width stays pinned at 340).
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    @objc private func statusItemClicked() {
        guard let btn = statusItem.button else { return }
        if popover.isShown {
            popover.close()
        } else {
            NotificationCenter.default.post(name: .mbPopoverWillOpen, object: nil)
            MainActor.assumeIsolated { briefingVM.refreshIfStale() }
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
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

        // Only surface the popover unprompted on the first morning wake of the
        // day — otherwise it pops open every single time the Mac wakes.
        guard shouldAutoShowOnWake() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, let btn = self.statusItem.button else { return }
            NotificationCenter.default.post(name: .mbPopoverWillOpen, object: nil)
            self.popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        }
    }

    private func shouldAutoShowOnWake() -> Bool {
        let cal   = Calendar.current
        guard cal.component(.hour, from: Date()) < 12 else { return false }
        let today = ISO8601DateFormatter.dayKey(Date())
        let key   = "lastAutoShownDay"
        guard UserDefaults.standard.string(forKey: key) != today else { return false }
        UserDefaults.standard.set(today, forKey: key)
        return true
    }
}

private extension ISO8601DateFormatter {
    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar   = Calendar(identifier: .gregorian)
        return f.string(from: date)
    }
}
