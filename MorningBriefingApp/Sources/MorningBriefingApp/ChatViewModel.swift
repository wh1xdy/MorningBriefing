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
    @Published var messages:   [ChatMessage] = []
    @Published var isLoading = false
    @Published var error: String?

    func send(_ question: String) {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Capture history BEFORE appending new user message
        let historyPayload: [[String: String]] = messages.map { msg in
            ["role": msg.role == .user ? "user" : "assistant", "content": msg.text]
        }
        let historyJSON = (try? JSONSerialization.data(withJSONObject: historyPayload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        messages.append(ChatMessage(role: .user, text: question))
        error     = nil
        isLoading = true

        let task = Process()
        let pipe = Pipe()
        task.executableURL  = URL(fileURLWithPath: pythonPath)
        task.arguments      = [chatPath, "--question", question, "--history", historyJSON]
        task.standardOutput = pipe
        task.standardError  = Pipe()

        task.terminationHandler = { [weak self] _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                guard
                    let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let answer = json["answer"] as? String
                else {
                    self.error = String(data: data, encoding: .utf8) ?? "Okänt fel"
                    return
                }
                if let err = json["error"] as? String, !err.isEmpty {
                    self.error = err
                } else {
                    self.messages.append(ChatMessage(role: .assistant, text: answer))
                }
            }
        }

        try? task.run()
    }
}
