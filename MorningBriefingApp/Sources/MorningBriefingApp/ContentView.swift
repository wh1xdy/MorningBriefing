import SwiftUI

// MARK: – Stagger helper

private extension View {
    func fadeFromTop(_ visible: Bool, delay: Double = 0) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : -10)
            .animation(.easeInOut(duration: 0.2).delay(delay), value: visible)
    }
}

// MARK: – ContentView

struct ContentView: View {
    @ObservedObject var briefingVM: BriefingViewModel
    @ObservedObject var chatVM:     ChatViewModel

    @State private var mode:         Mode   = .briefing
    @State private var appeared:     Bool   = false
    @State private var openToken:    UUID   = UUID()
    @State private var showSettings: Bool   = false
    @State private var chatInput:    String = ""
    @FocusState private var chatFocused: Bool

    enum Mode: Equatable { case briefing, chat }

    var body: some View {
        ZStack {
            GradientBackground()
            VStack(spacing: 0) {
                header
                    .fadeFromTop(appeared, delay: 0.00)
                Divider().opacity(0.3)
                    .fadeFromTop(appeared, delay: 0.02)
                Group {
                    if mode == .briefing {
                        briefingPane.transition(.opacity)
                    } else {
                        chatPane.transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: mode)
            }
        }
        .frame(width: 340, height: 520)
        .onAppear { animateIn() }
        .onReceive(NotificationCenter.default.publisher(for: .mbPopoverWillOpen)) { _ in
            animateIn()
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .chat { chatFocused = true }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private func animateIn() {
        openToken = UUID()   // force AnimatedBriefingText to recreate
        appeared  = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            appeared = true
        }
    }

    // MARK: – Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.yellow).imageScale(.small)
            Text("MorningBriefing")
                .font(.system(.subheadline, weight: .semibold))
            Spacer()
            if let avg = briefingVM.result?.plugins.elpris?.data?.avgPrice {
                Text(String(format: "%.0f öre", avg))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if briefingVM.stage != .ready && briefingVM.stage != .idle {
                Text(briefingVM.stage.label)
                    .font(.caption).foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    mode = mode == .briefing ? .chat : .briefing
                }
            } label: {
                Image(systemName: mode == .briefing ? "bubble.left" : "doc.text")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help(mode == .briefing ? "Öppna chat" : "Visa briefing")

            Button { briefingVM.triggerBriefing() } label: {
                Image(systemName: "arrow.clockwise").imageScale(.small)
            }
            .buttonStyle(.plain).help("Uppdatera briefing")

            Button { showSettings = true } label: {
                Image(systemName: "gearshape").imageScale(.small)
            }
            .buttonStyle(.plain).help("Inställningar")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: – Briefing pane

    private var briefingPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                briefingText
                    .fadeFromTop(appeared, delay: 0.05)

                if let elpris = briefingVM.result?.plugins.elpris?.data,
                   !elpris.prices.isEmpty {
                    chartCard(elpris)
                        .fadeFromTop(appeared, delay: 0.10)
                }
                if let core = briefingVM.result?.plugins.core?.data {
                    recommendationCard(core)
                        .fadeFromTop(appeared, delay: 0.14)
                }
                if let r = briefingVM.result?.plugins.reaktorstatus?.data, r.count > 0 {
                    reaktorCard(r)
                        .fadeFromTop(appeared, delay: 0.18)
                }
                Spacer(minLength: 16)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var briefingText: some View {
        if let text = briefingVM.result?.briefing {
            AnimatedBriefingText(text: text)
                .id(openToken)
        } else {
            HStack(spacing: 8) {
                if briefingVM.stage != .idle { ProgressView().scaleEffect(0.7) }
                Text(briefingVM.stage == .idle
                     ? "Tryck ↺ för att generera dagens briefing."
                     : briefingVM.stage.label)
                    .font(.body).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: – Chart card

    private func chartCard(_ elpris: ElprisData) -> some View {
        let tomorrow = elpris.tomorrowPrices ?? []
        let combined: [HourPrice] = tomorrow.isEmpty
            ? elpris.prices
            : elpris.prices + tomorrow.map { HourPrice(hour: $0.hour + 24, priceOreKwh: $0.priceOreKwh) }

        return VStack(alignment: .leading, spacing: 8) {
            Label("SE3 Spot", systemImage: "bolt.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            PriceChartView(
                prices: combined,
                currentHour: Calendar.current.component(.hour, from: .now)
            )
            HStack(spacing: 8) {
                statPill("Snitt", String(format: "%.1f öre", elpris.avgPrice))
                statPill("Min",   String(format: "%.1f öre", elpris.minPrice))
                statPill("Max",   String(format: "%.1f öre", elpris.maxPrice))
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

    // MARK: – Recommendation card

    private func recommendationCard(_ core: CoreData) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.badge.checkmark.fill")
                .foregroundStyle(.green).font(.title3).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Kör tunga jobb")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(String(format: "%02d:00 – %02d:00",
                            core.cheapestWindowStart, core.cheapestWindowEnd))
                    .font(.title3.monospacedDigit().weight(.semibold))
                Text(String(format: "%.1f öre/kWh  (%d%% under dagsnitt)",
                            core.cheapestWindowAvg,
                            Int(((core.dailyAvg - core.cheapestWindowAvg)
                                 / max(core.dailyAvg, 0.01)) * 100)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.08),  in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.green.opacity(0.2)))
    }

    // MARK: – Reaktor card

    private func reaktorCard(_ r: ReaktorData) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.title3).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Nukleär UMM aktiv")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(r.plants.joined(separator: ", ")).font(.callout.weight(.medium))
                if let mw = r.totalUnavailMw {
                    Text("\(mw) MW otillgängliga").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.orange.opacity(0.2)))
    }

    // MARK: – Chat pane

    private var chatPane: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if chatVM.messages.isEmpty && !chatVM.isLoading {
                            Text("Ställ en fråga om elmarknaden eller dagens briefing.")
                                .font(.callout).foregroundStyle(.secondary)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ForEach(chatVM.messages) { msg in
                            if msg.role == .user {
                                HStack {
                                    Spacer(minLength: 40)
                                    Text(msg.text)
                                        .font(.body)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(Color.accentColor.opacity(0.2),
                                                    in: RoundedRectangle(cornerRadius: 12))
                                }
                            } else {
                                Text(msg.text)
                                    .font(.body)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(.quaternary.opacity(0.5),
                                                in: RoundedRectangle(cornerRadius: 12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if chatVM.isLoading {
                            if chatVM.streamingText.isEmpty {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.65)
                                    Text("Tänker…").font(.callout).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                            } else {
                                Text(chatVM.streamingText)
                                    .font(.body)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(.quaternary.opacity(0.5),
                                                in: RoundedRectangle(cornerRadius: 12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if let err = chatVM.error {
                            Text(err)
                                .font(.caption).foregroundStyle(.red)
                                .padding(.horizontal, 12)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(14)
                }
                .scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo("bottom") }
                .onChange(of: chatVM.messages.count) { _, _ in
                    withAnimation(.smooth) { proxy.scrollTo("bottom") }
                }
                .onChange(of: chatVM.isLoading) { _, _ in
                    withAnimation(.smooth) { proxy.scrollTo("bottom") }
                }
                .onChange(of: chatVM.streamingText) { _, _ in
                    proxy.scrollTo("bottom")
                }
            }

            Divider().opacity(0.3)

            HStack(spacing: 8) {
                TextField("Fråga om elmarknaden…", text: $chatInput)
                    .font(.body).textFieldStyle(.plain)
                    .focused($chatFocused)
                    .onSubmit { submitChat() }
                Button(action: submitChat) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(
                            chatInput.isEmpty
                                ? AnyShapeStyle(.tertiary)
                                : AnyShapeStyle(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
                .disabled(chatInput.isEmpty || chatVM.isLoading)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private func submitChat() {
        let q = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !chatVM.isLoading else { return }
        chatInput = ""
        chatVM.send(q)
    }
}
