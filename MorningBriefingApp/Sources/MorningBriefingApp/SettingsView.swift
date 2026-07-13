import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @Binding var isShowing: Bool
    @AppStorage("appLanguage") private var language: String = "sv"
    @AppStorage("priceAlertsEnabled") private var priceAlertsEnabled: Bool = true
    @State private var launchAtLogin: Bool = SettingsView.isRegisteredAtLogin

    /// Login-item registration only exists for a real .app bundle; the bare
    /// SPM debug binary has no bundle identifier to register.
    private static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    private static var isRegisteredAtLogin: Bool {
        guard isBundled else { return false }
        return SMAppService.mainApp.status == .enabled
    }

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
                .accessibilityLabel(language == "sv" ? "Tillbaka" : "Back")
                .help(language == "sv" ? "Tillbaka" : "Back")

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
                                Text("Svenska").tag("sv")
                                Text("English").tag("en")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 150)
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
                        icon: "building.2.fill",
                        color: .indigo,
                        name: "Vattenfall",
                        detail: language == "sv" ? "Forsmark F1–F3, live produktion" : "Forsmark F1–F3, live output",
                        url: "karnkraft.vattenfall.se"
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
                        detail: language == "sv" ? "Chatt – lokal MLX-inferens" : "Chat – local MLX inference",
                        url: "mlx-community (4-bit)"
                    )

                    sectionHeader(language == "sv" ? "APP" : "APPLICATION")

                    // Price alerts (delivery requires the bundled .app;
                    // BriefingViewModel gates the actual scheduling)
                    settingRow {
                        HStack(spacing: 12) {
                            iconTile("bell.badge", color: .green)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(language == "sv" ? "Prisavisering" : "Price alert")
                                    .font(.body)
                                Text(language == "sv" ? "När billigaste fönstret börjar"
                                                      : "When the cheapest window starts")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $priceAlertsEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }
                    }

                    if Self.isBundled {
                        settingRow {
                            HStack(spacing: 12) {
                                iconTile("arrow.up.forward.app", color: .blue)
                                Text(language == "sv" ? "Starta vid inloggning" : "Launch at login")
                                    .font(.body)
                                Spacer()
                                Toggle("", isOn: $launchAtLogin)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .labelsHidden()
                                    .onChange(of: launchAtLogin) { _, enable in
                                        do {
                                            if enable { try SMAppService.mainApp.register() }
                                            else      { try SMAppService.mainApp.unregister() }
                                        } catch {
                                            launchAtLogin = Self.isRegisteredAtLogin
                                        }
                                    }
                            }
                        }
                    }

                    // Quit — no chevron: this is an action, not navigation
                    Button {
                        if Self.isBundled {
                            NSApp.terminate(nil)
                        } else {
                            // NSApplication.terminate is silently swallowed in a
                            // bare SPM binary without a bundle.
                            exit(0)
                        }
                    } label: {
                        settingRowContent {
                            HStack(spacing: 12) {
                                iconTile("power", color: .red)
                                Text(language == "sv" ? "Avsluta MorningBriefing" : "Quit MorningBriefing")
                                    .font(.body)
                                    .foregroundStyle(.red)
                                Spacer()
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
                    Text(name).font(.callout.weight(.medium)).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
        }
        // The endpoint lives in a tooltip — inline it crowded the row until
        // the source names wrapped.
        .help(url)
        .padding(.top, 1)
    }

    @ViewBuilder
    private func iconTile(_ systemName: String, color: Color) -> some View {
        // Tinted, not saturated — filled iOS-style tiles made Settings the
        // loudest screen in the app.
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.16))
                .frame(width: 28, height: 28)
            Image(systemName: systemName)
                .imageScale(.small)
                .foregroundStyle(color)
        }
    }
}
