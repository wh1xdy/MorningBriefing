import Foundation
import AppKit
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
        switch self {
        case .idle:             return "Väntar…"
        case .aggregating:      return "Hämtar data…"
        case .generating:       return "Genererar…"
        case .ready:            return "Klar"
        case .error(let e):     return "Fel: \(e)"
        }
    }
}

@MainActor
final class BriefingViewModel: ObservableObject {
    @Published var result: BriefingResult?
    @Published var stage:  BriefingStage = .idle

    @Published var currentPriceLabel: String?

    private var fileSource:   DispatchSourceFileSystemObject?
    private var statusTimer:  Timer?
    private var minuteTimer:  Timer?

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
                if p.terminationStatus != 0, case .ready = self.stage { return }
                if p.terminationStatus != 0 {
                    self.stage = .error("bridge.py exited \(p.terminationStatus)")
                    self.stopStatusPolling()
                }
            }
        }
        watchOutputFile()
        try? task.run()
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

        result = decoded
        stage  = .ready
        fileSource?.cancel()
        fileSource = nil
        stopStatusPolling()
        stampToday()
        updateCurrentHourPrice()
        scheduleMinutelyPriceTick()
        postBriefingReadyNotification(decoded)
    }

    // MARK: – Price badge (60-second tick)

    private func updateCurrentHourPrice() {
        guard let prices = result?.plugins.elpris?.data?.prices else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        if let hp = prices.first(where: { $0.hour == hour }) {
            currentPriceLabel = String(format: "%.0f", hp.priceOreKwh)
        } else if let avg = result?.plugins.elpris?.data?.avgPrice {
            currentPriceLabel = String(format: "%.0f", avg)
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
        let content = UNMutableNotificationContent()
        content.title = "MorningBriefing klar"
        if let avg = r.plugins.elpris?.data?.avgPrice {
            content.body = String(format: "SE3 snitt idag: %.0f öre/kWh", avg)
        } else {
            content.body = "Dagens briefing är redo."
        }
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    // MARK: – Output file polling

    private var outputTimer: Timer?

    private func startOutputPolling() {
        outputTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    self.outputTimer?.invalidate(); self.outputTimer = nil
                    self.watchOutputFile()
                    self.parseOutputFile()
                }
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
        case "error":               stage = .error(s.error ?? "okänt fel")
        default: break
        }
    }
}
