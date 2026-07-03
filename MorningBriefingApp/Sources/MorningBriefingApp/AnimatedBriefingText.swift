import SwiftUI

/// Splits briefing text into sentences and fades each in with a 0.15s stagger.
struct AnimatedBriefingText: View {
    let text: String
    @State private var visibleCount = 0

    private var sentences: [String] {
        // Split on ". " only when followed by an uppercase letter to avoid
        // splitting decimal numbers like "45.2 öre".
        var result: [String] = []
        var current = ""
        let chars  = Array(text)
        for i in chars.indices {
            current.append(chars[i])
            let isFullStop   = chars[i] == "."
            let nextIsSpace  = i + 1 < chars.count && chars[i + 1] == " "
            let afterIsUpper = i + 2 < chars.count && chars[i + 2].isUppercase
            if isFullStop && nextIsSpace && afterIsUpper && current.count > 20 {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(current.trimmingCharacters(in: .whitespaces))
        }
        return result.isEmpty ? [text] : result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(sentences.enumerated()), id: \.offset) { idx, sentence in
                Text(sentence)
                    .font(.system(.body, design: .default, weight: .regular))
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(idx < visibleCount ? 1 : 0)
                    .offset(y: idx < visibleCount ? 0 : 4)
                    .animation(
                        .easeInOut(duration: 0.3).delay(Double(idx) * 0.15),
                        value: visibleCount
                    )
            }
        }
        .onAppear { visibleCount = sentences.count }
        // The text can change in place while the view is alive (refresh button,
        // live file watcher) — reset and replay the reveal for the new sentences.
        .onChange(of: text) { _, _ in
            visibleCount = 0
            DispatchQueue.main.async { visibleCount = sentences.count }
        }
    }
}
