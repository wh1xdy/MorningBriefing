import SwiftUI

/// Auto-triggered briefing popover (shown on wake, once per day).
/// Three animated sections: AI briefing text, price chart, recommendation block.
struct PopoverView: View {
    @ObservedObject var vm: BriefingViewModel
    @State private var appeared  = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            GradientBackground()
            VStack(alignment: .leading, spacing: 0) {
                toolbar
                Divider().opacity(0.3)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        briefingSection
                        if let prices = vm.result?.plugins.elpris?.data?.prices, !prices.isEmpty {
                            chartSection(prices: prices, elpris: vm.result?.plugins.elpris?.data)
                        }
                        if let core = vm.result?.plugins.core?.data {
                            recommendationSection(core: core)
                        }
                        if let r = vm.result?.plugins.reaktorstatus?.data, r.count > 0 {
                            reaktorSection(r)
                        }
                        Spacer(minLength: 12)
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 340)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .onAppear { appeared = true }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    // MARK: – Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("MorningBriefing")
                .font(.system(.headline, design: .default, weight: .semibold))
            Spacer()
            if vm.stage != .ready && vm.stage != .idle {
                Text(vm.stage.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Button { vm.triggerBriefing() } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help("Uppdatera briefing")
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help("Inställningar")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: – Briefing text

    @ViewBuilder
    private var briefingSection: some View {
        if let text = vm.result?.briefing {
            AnimatedBriefingText(text: text)
        } else {
            HStack(spacing: 8) {
                if vm.stage != .idle { ProgressView().scaleEffect(0.7) }
                Text(vm.stage == .idle
                     ? "Tryck ↺ för att generera dagens briefing."
                     : vm.stage.label)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: – Chart

    private func chartSection(prices: [HourPrice], elpris: ElprisData?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("SE3 Spot", systemImage: "bolt.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            PriceChartView(
                prices: prices,
                currentHour: Calendar.current.component(.hour, from: .now)
            )
            .opacity(appeared ? 1 : 0)
            .animation(.easeIn(duration: 0.2).delay(0.1), value: appeared)

            if let e = elpris {
                HStack(spacing: 8) {
                    statPill("Snitt", String(format: "%.1f öre", e.avgPrice))
                    statPill("Min",   String(format: "%.1f öre", e.minPrice))
                    statPill("Max",   String(format: "%.1f öre", e.maxPrice))
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: – Recommendation

    private func recommendationSection(core: CoreData) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.badge.checkmark.fill")
                .foregroundStyle(.green)
                .font(.title3)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Kör tunga jobb")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(String(format: "%02d:00 – %02d:00", core.cheapestWindowStart, core.cheapestWindowEnd))
                    .font(.title3.monospacedDigit().weight(.semibold))
                Text(String(format: "%.1f öre/kWh  (%d%% under dagsnitt)",
                            core.cheapestWindowAvg,
                            Int(((core.dailyAvg - core.cheapestWindowAvg) / max(core.dailyAvg, 0.01)) * 100)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.green.opacity(0.2)))
        .offset(y: appeared ? 0 : 16)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.4, bounce: 0.2).delay(0.25), value: appeared)
    }

    // MARK: – Reaktor alert

    private func reaktorSection(_ r: ReaktorData) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Nukleär UMM aktiv")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(r.plants.joined(separator: ", "))
                    .font(.callout.weight(.medium))
                if let mw = r.totalUnavailMw {
                    Text("\(mw) MW otillgängliga")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.orange.opacity(0.2)))
    }
}
