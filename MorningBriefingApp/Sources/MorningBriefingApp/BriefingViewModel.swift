import Foundation
import AppKit
import Network
import UserNotifications

private let home            = FileManager.default.homeDirectoryForCurrentUser
private let outputURL       = home.appendingPathComponent(".morningbriefing/latest.json")
private let statusURL       = home.appendingPathComponent(".morningbriefing/status.json")
private let lastBriefingURL = home.appendingPathComponent(".morningbriefing/last_briefing")
private let projectRoot     = home.appendingPathComponent("Developer/MorningBriefing")
private let pythonPath      = projectRoot.appendingPathComponent(".venv/bin/python").path
private let bridgePath      = projectRoot.appendingPathComponent("bridge.py").path

enum BriefingStage: Equatable {
    case idle, aggregating, generating, ready, error(String)

    var label: String {
        let sv = UserDefaults.standard.string(forKey: "appLanguage") != "en"
        switch self {
        case .idle:             return sv ? "Väntar…"      : "Waiting…"
        case .aggregating:      return sv ? "Hämtar data…" : "Fetching data…"
        case .generating:       return sv ? "Genererar…"   : "Generating…"
        case .ready:            return sv ? "Klar"         : "Ready"
        case .error(let e):     return (sv ? "Fel: " : "Error: ") + e
        }
    }
}

@MainActor
final class BriefingViewModel: ObservableObject {
    @Published var result: BriefingResult?
    @Published var stage:  BriefingStage = .idle

    @Published var currentPriceLabel: String?
    @Published var isOffline: Bool = false

    private var fileSource:   DispatchSourceFileSystemObject?
    private var statusTimer:  Timer?
    private var minuteTimer:  Timer?
    private let pathMonitor = NWPathMonitor()

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOffline = path.status != .satisfied }
        }
        pathMonitor.start(queue: DispatchQueue(label: "mb.network.monitor"))
    }

    // MARK: – Public

    func triggerBriefingIfNeeded() {
        guard !hasBriefedToday() else { return }
        triggerBriefing()
    }

    func triggerBriefing() {
        switch stage {
        case .aggregating, .generating: return   // already running
        default: break
        }
        stage = .aggregating
        startStatusPolling()
        launchBridge()
    }

    func loadCachedIfAvailable() {
        guard FileManager.default.fileExists(atPath: outputURL.path) else { return }
        parseOutputFile()
        watchOutputFile()   // keep watching so inject_fixture / bridge writes are picked up live
    }

    /// Re-runs the full pipeline only when today's data is missing.
    /// If latest.json contains today's elpris date we leave it alone — avoids
    /// triggering a heavy pipeline (and showing an error) just because the file
    /// was written >30 min ago while the user is offline.
    func refreshIfStale() {
        // If we already have in-memory data for today, nothing to do.
        if let dateStr = result?.plugins.elpris?.data?.date {
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            if let d = fmt.date(from: dateStr), Calendar.current.isDateInToday(d) { return }
        }
        // Fall back to file mtime: only refresh if the file is from a previous day.
        if let attrs    = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
           let modified = attrs[.modificationDate] as? Date,
           Calendar.current.isDateInToday(modified) { return }
        triggerBriefing()
    }

    // MARK: – Once-per-day

    private func hasBriefedToday() -> Bool {
        guard let data  = try? Data(contentsOf: lastBriefingURL),
              let str   = String(data: data, encoding: .utf8)?
                              .trimmingCharacters(in: .whitespacesAndNewlines),
              let stored = ISO8601DateFormatter().date(from: str)
        else { return false }
        return Calendar.current.isDateInToday(stored)
    }

    private func stampToday() {
        try? ISO8601DateFormatter()
            .string(from: Date())
            .data(using: .utf8)?
            .write(to: lastBriefingURL)
    }

    // MARK: – Bridge launch

    private func launchBridge() {
        let task = Process()
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "sv"
        task.executableURL = URL(fileURLWithPath: pythonPath)
        task.arguments     = [bridgePath, "--language", lang]
        task.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self else { return }
                guard p.terminationStatus != 0 else { return }
                switch self.stage {
                case .ready, .error: return   // briefing landed / error already surfaced
                default: break
                }
                // bridge.py writes a friendly, localized message to status.json just
                // before exiting 1 — prefer it over the raw exit code.
                if let data = try? Data(contentsOf: statusURL),
                   let s    = try? JSONDecoder().decode(StatusResult.self, from: data),
                   s.stage == "error", let msg = s.error, !msg.isEmpty {
                    self.stage = .error(msg)
                } else {
                    self.stage = .error("bridge.py exited \(p.terminationStatus)")
                }
                self.stopStatusPolling()
            }
        }
        watchOutputFile()
        do {
            try task.run()
        } catch {
            // If the process never starts (missing .venv/python/bridge.py) there is
            // no terminationHandler to fall back on — surface it instead of spinning
            // on "Fetching data…" forever.
            let sv = UserDefaults.standard.string(forKey: "appLanguage") != "en"
            stage = .error(sv ? "Kunde inte starta bridge.py – kontrollera .venv och sökväg."
                              : "Could not launch bridge.py – check .venv and path.")
            stopStatusPolling()
        }
    }

    // MARK: – File watcher

    private func watchOutputFile() {
        try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            startOutputPolling(); return
        }
        let fd = open(outputURL.path, O_EVTONLY)
        guard fd >= 0 else { startOutputPolling(); return }
        fileSource?.cancel()
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend], queue: .main
        )
        src.setEventHandler { [weak self] in self?.parseOutputFile() }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileSource = src
    }

    private func parseOutputFile() {
        guard
            let data    = try? Data(contentsOf: outputURL),
            let decoded = try? JSONDecoder().decode(BriefingResult.self, from: data),
            !decoded.briefing.isEmpty
        else { return }

        // Only the first parse of the day is a genuinely new briefing worth a
        // notification; later writes (inject_fixture, manual refresh) update the
        // UI live without re-alerting.
        let isFirstToday = !hasBriefedToday()

        result = decoded
        stage  = .ready
        // Keep the watcher alive so subsequent bridge / inject_fixture writes are
        // picked up live, as loadCachedIfAvailable() promises.
        stopStatusPolling()
        stampToday()
        updateCurrentHourPrice()
        scheduleMinutelyPriceTick()
        if isFirstToday {
            postBriefingReadyNotification(decoded)
        }
        schedulePriceAlert(decoded)
    }

    // MARK: – Price alert

    /// Local notification at the start of today's cheapest window. Uses a fixed
    /// identifier so a re-parse replaces the pending request instead of stacking
    /// duplicates; a window already underway schedules nothing.
    private func schedulePriceAlert(_ r: BriefingResult) {
        guard Bundle.main.bundleIdentifier != nil else { return }   // notifications need a real bundle
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "priceAlertsEnabled") as? Bool ?? true
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["mb.cheapWindow"])
        guard enabled,
              let core = r.plugins.core?.data,
              let start = core.cheapestWindowStart,
              let end = core.cheapestWindowEnd,
              let avg = core.cheapestWindowAvg else { return }

        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = start
        comps.minute = 0
        guard let fireDate = Calendar.current.date(from: comps), fireDate > Date() else { return }

        let sv = defaults.string(forKey: "appLanguage") != "en"
        let price = String(format: "%.1f", avg)
            .replacingOccurrences(of: ".", with: sv ? "," : ".")
        let until = String(format: "%02d:00", end)
        let content = UNMutableNotificationContent()
        content.title = sv ? "Billigaste fönstret börjar nu" : "Cheapest window starts now"
        content.body  = sv ? "Kör tunga jobb till \(until) – \(price) öre/kWh."
                           : "Run heavy loads until \(until) – \(price) öre/kWh."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: "mb.cheapWindow",
                                         content: content, trigger: trigger)) { _ in }
    }

    // MARK: – Price badge (60-second tick)

    private func updateCurrentHourPrice() {
        guard let prices = result?.plugins.elpris?.data?.prices else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        if let hp = prices.first(where: { $0.hour == hour }) {
            currentPriceLabel = String(format: "%.0f öre", hp.priceOreKwh)
        } else if let avg = result?.plugins.elpris?.data?.avgPrice {
            currentPriceLabel = String(format: "%.0f öre", avg)
        }
    }

    private func scheduleMinutelyPriceTick() {
        minuteTimer?.invalidate()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateCurrentHourPrice() }
        }
    }

    // MARK: – Notification

    private func postBriefingReadyNotification(_ r: BriefingResult) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let sv = UserDefaults.standard.string(forKey: "appLanguage") != "en"
        let content = UNMutableNotificationContent()
        content.title = sv ? "MorningBriefing klar" : "MorningBriefing ready"
        if let avg = r.plugins.elpris?.data?.avgPrice {
            content.body = String(format: sv ? "SE3 snitt idag: %.0f öre/kWh"
                                              : "SE3 avg today: %.0f öre/kWh", avg)
        } else {
            content.body = sv ? "Dagens briefing är redo." : "Today's briefing is ready."
        }
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    // MARK: – Output file polling

    private var outputTimer: Timer?

    private func startOutputPolling() {
        outputTimer?.invalidate()   // re-entry (e.g. retry after failure) must not orphan the old poll
        outputTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard FileManager.default.fileExists(atPath: outputURL.path) else { return }
            // Invalidate the timer that actually fired — outputTimer may have been
            // reassigned since this one was scheduled.
            timer.invalidate()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.outputTimer = nil
                self.watchOutputFile()
                self.parseOutputFile()
            }
        }
    }

    // MARK: – Status polling

    private func startStatusPolling() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollStatus() }
        }
    }

    private func stopStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    private func pollStatus() {
        guard let data = try? Data(contentsOf: statusURL),
              let s    = try? JSONDecoder().decode(StatusResult.self, from: data)
        else { return }
        switch s.stage {
        case "aggregating":         stage = .aggregating
        case "generating_briefing": stage = .generating
        case "ready":
            // bridge.py writes latest.json before this stage, so the parse should
            // succeed; if it's rejected (unreadable/empty briefing) surface an error
            // instead of spinning on "Genererar…" with the poll running forever.
            parseOutputFile()
            if stage != .ready {
                let sv = UserDefaults.standard.string(forKey: "appLanguage") != "en"
                stage = .error(sv ? "Kunde inte läsa briefingen." : "Could not read the briefing.")
                stopStatusPolling()
            }
        case "error":
            let sv = UserDefaults.standard.string(forKey: "appLanguage") != "en"
            stage = .error(s.error ?? (sv ? "okänt fel" : "unknown error"))
        default: break
        }
    }
}
