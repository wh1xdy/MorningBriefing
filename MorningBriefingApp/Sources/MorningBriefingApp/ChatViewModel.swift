import Foundation

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

        let historyPayload: [[String: String]] = messages.map { msg in
            ["role": msg.role == .user ? "user" : "assistant", "content": msg.text]
        }
        let historyJSON = (try? JSONSerialization.data(withJSONObject: historyPayload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        messages.append(ChatMessage(role: .user, text: question))
        streamingText = ""
        error         = nil
        isLoading     = true

        let task       = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.executableURL  = URL(fileURLWithPath: pythonPath)
        task.arguments      = [chatPath, "--question", question, "--history", historyJSON]
        task.standardOutput = stdoutPipe
        task.standardError  = stderrPipe

        // Stream tokens as they arrive
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.streamingText += chunk
            }
        }

        task.terminationHandler = { [weak self] p in
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                self.isLoading = false
                if p.terminationStatus != 0 {
                    self.error = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Okänt fel"
                    self.streamingText = ""
                } else if !self.streamingText.isEmpty {
                    self.messages.append(ChatMessage(role: .assistant, text: self.streamingText))
                    self.streamingText = ""
                } else {
                    self.error = "Inget svar mottaget"
                }
            }
        }

        try? task.run()
    }
}
