import SwiftUI

// Stub — expand in a later phase
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Inställningar")
                .font(.title2.weight(.semibold))
            Text("Kommer snart.")
                .foregroundStyle(.secondary)
            Button("Stäng") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(32)
        .frame(width: 300, height: 200)
    }
}
