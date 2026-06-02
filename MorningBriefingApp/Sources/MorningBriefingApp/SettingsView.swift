import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var language: String = "sv"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Inställningar")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            Divider()

            // Language row
            settingsRow(
                icon: "globe",
                iconColor: .blue,
                title: "Språk / Language"
            ) {
                Picker("", selection: $language) {
                    Text("🇸🇪 Svenska").tag("sv")
                    Text("🇬🇧 English").tag("en")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .labelsHidden()
            }

            Divider().padding(.leading, 44)

            // Quit row — full-width button so hit-testing is reliable
            Button {
                exit(0)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(Color.red)
                            .frame(width: 28, height: 28)
                        Image(systemName: "power")
                            .imageScale(.small)
                            .foregroundStyle(.white)
                    }
                    Text(language == "sv" ? "Avsluta MorningBriefing" : "Quit MorningBriefing")
                        .font(.body).foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(width: 340, height: 180)
    }

    @ViewBuilder
    private func settingsRow<Control: View>(
        icon: String,
        iconColor: Color,
        title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(iconColor)
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .imageScale(.small)
                    .foregroundStyle(.white)
            }
            Text(title).font(.body)
            Spacer()
            control()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
