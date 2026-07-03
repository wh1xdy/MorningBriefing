import Foundation
import SwiftUI

private let home       = FileManager.default.homeDirectoryForCurrentUser
private let pythonPath = home.appendingPathComponent("Developer/MorningBriefing/.venv/bin/python").path
private let chatPath   = home.appendingPathComponent("Developer/MorningBriefing/chat.py").path

struct ChatMessage: Identifiable {
    let id   = UUID()
    let role: Role
    let text: String
    enum Role { case user, assistant }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages:      [ChatMessage] = []
    @Published var streamingText: String        = ""
    @Published var isLoading = false
    @Published var error: String?

    func send(_ question: String) {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Build history from complete user/assistant pairs only.
        // This guarantees strict alternation and prevents the MLX
        // "Conversation roles must alternate" error caused by orphaned
        // user messages from previous failed turns.
        var historyPayload: [[String: String]] = []
        var i = 0
        while i + 1 < messages.count {
            let a = messages[i], b = messages[i + 1]
            if a.role == .user && b.role == .assistant {
                historyPayload.append(["role": "user",      "content": a.text])
                historyPayload.append(["role": "assistant", "content": b.text])
                i += 2
            } else {
                i += 1
            }
        }
        let historyJSON = (try? JSONSerialization.data(withJSONObject: historyPayload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
            messages.append(ChatMessage(role: .user, text: question))
        }
        streamingText = ""
        error         = nil
        isLoading     = true

        let task       = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.executableURL  = URL(fileURLWithPath: pythonPath)
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "sv"
        task.arguments      = [chatPath, "--question", question, "--history", historyJSON, "--language", lang]
        task.standardOutput = stdoutPipe
        task.standardError  = stderrPipe

        // Accumulate both pipes off the main thread. stderr must be drained
        // while the process runs — if chat.py writes more than the ~64 KB pipe
        // buffer (e.g. Hugging Face download progress on a model cache miss)
        // an unread pipe blocks its writes and the process never exits.
        let bufferLock   = NSLock()
        var stdoutBuffer = Data()
        var stderrBuffer = Data()

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            bufferLock.lock()
            stdoutBuffer.append(data)
            let text = String(decoding: stdoutBuffer, as: UTF8.self)
            bufferLock.unlock()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isLoading else { return }
                self.streamingText = text
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            bufferLock.lock()
            stderrBuffer.append(data)
            bufferLock.unlock()
        }

        task.terminationHandler = { [weak self] p in
            // Stop the readability handlers first, then drain any remaining
            // bytes synchronously so finalization never races the last chunk.
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            bufferLock.lock()
            stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            let outText = String(decoding: stdoutBuffer, as: UTF8.self)
            let errText = String(decoding: stderrBuffer, as: UTF8.self)
            bufferLock.unlock()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isLoading = false
                let sv = UserDefaults.standard.string(forKey: "appLanguage") != "en"
                if p.terminationStatus != 0 {
                    let stderr = errText.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.error = stderr.isEmpty ? (sv ? "Okänt fel" : "Unknown error") : stderr
                    self.streamingText = ""
                } else if !outText.isEmpty {
                    self.messages.append(ChatMessage(role: .assistant, text: outText))
                    self.streamingText = ""
                } else {
                    self.error = sv ? "Inget svar mottaget" : "No response received"
                }
            }
        }

        do {
            try task.run()
        } catch {
            // Launch failed — the terminationHandler never fires, so release
            // the pipe read sources here to avoid leaking file handles.
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            let sv = UserDefaults.standard.string(forKey: "appLanguage") != "en"
            isLoading = false
            self.error = sv ? "Kunde inte starta chat.py – kontrollera .venv och sökväg."
                            : "Could not launch chat.py – check .venv and path."
        }
    }
}
