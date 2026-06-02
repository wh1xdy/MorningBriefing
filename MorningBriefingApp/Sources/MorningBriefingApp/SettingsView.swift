import SwiftUI

struct SettingsView: View {
    @Binding var isShowing: Bool
    @AppStorage("appLanguage") private var language: String = "sv"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) { isShowing = false }
                } label: {
                    Image(systemName: "chevron.left")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()
                Text(language == "sv" ? "Inställningar" : "Settings")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                // Balance spacer
                Color.clear.frame(width: 28, height: 28)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)

            Divider().opacity(0.3)

            ScrollView {
                VStack(spacing: 1) {
                    // Language
                    settingRow {
                        HStack(spacing: 12) {
                            iconTile("globe", color: .blue)
                            Text(language == "sv" ? "Språk" : "Language")
                                .font(.body)
                            Spacer()
                            Picker("", selection: $language) {
                                Text("🇸🇪 SV").tag("sv")
                                Text("🇬🇧 EN").tag("en")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 110)
                            .labelsHidden()
                        }
                    }

                    // Sources section header
                    sectionHeader(language == "sv" ? "DATAKÄLLOR" : "DATA SOURCES")

                    sourceRow(
                        icon: "chart.line.uptrend.xyaxis",
                        color: .orange,
                        name: "Nord Pool – Day Ahead",
                        detail: language == "sv" ? "SE3 spotpriser (15-min)" : "SE3 spot prices (15-min)",
                        url: "dataportal-api.nordpoolgroup.com"
                    )
                    sourceRow(
                        icon: "bolt.fill",
                        color: .yellow,
                        name: "Nord Pool – UMM API",
                        detail: language == "sv" ? "Kärnkraft driftstörningar" : "Nuclear outage messages",
                        url: "ummapi.nordpoolgroup.com"
                    )
                    sourceRow(
                        icon: "cloud.sun.fill",
                        color: .teal,
                        name: "Open-Meteo",
                        detail: language == "sv" ? "Väder, Stockholm" : "Weather, Stockholm",
                        url: "api.open-meteo.com"
                    )
                    sourceRow(
                        icon: "cpu",
                        color: .purple,
                        name: "Mistral 7B Instruct v0.3",
                        detail: language == "sv" ? "Lokal MLX-inferens" : "Local MLX inference",
                        url: "mlx-community (4-bit)"
                    )

                    sectionHeader(language == "sv" ? "APP" : "APPLICATION")

                    // Quit
                    Button {
                        exit(0)
                    } label: {
                        settingRowContent {
                            HStack(spacing: 12) {
                                iconTile("power", color: .red)
                                Text(language == "sv" ? "Avsluta MorningBriefing" : "Quit MorningBriefing")
                                    .font(.body)
                                    .foregroundStyle(.red)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .imageScale(.small)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 340, height: 520)
    }

    // MARK: – Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            Spacer()
        }
        .padding(.horizontal, 4).padding(.top, 12).padding(.bottom, 2)
    }

    @ViewBuilder
    private func settingRow<C: View>(@ViewBuilder content: () -> C) -> some View {
        settingRowContent(content: content)
    }

    @ViewBuilder
    private func settingRowContent<C: View>(@ViewBuilder content: () -> C) -> some View {
        content()
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sourceRow(icon: String, color: Color, name: String, detail: String, url: String) -> some View {
        settingRowContent {
            HStack(spacing: 12) {
                iconTile(icon, color: color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.callout.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(url)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.top, 1)
    }

    @ViewBuilder
    private func iconTile(_ systemName: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(color)
                .frame(width: 28, height: 28)
            Image(systemName: systemName)
                .imageScale(.small)
                .foregroundStyle(.white)
        }
    }
}
