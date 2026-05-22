import SwiftUI

struct MainPopoverView: View {
    @ObservedObject var briefingVM: BriefingViewModel
    @ObservedObject var chatVM:     ChatViewModel
    var onExpand: () -> Void
    var isDetached: Bool = false

    @State private var showingBriefing = true
    @State private var appeared        = false
    @State private var chatInput       = ""
    @State private var showSettings    = false
    @FocusState private var chatFocused: Bool

    var body: some View {
        Group {
            if isDetached {
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mainContent
                    .frame(width: 340, height: 520)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
        .onChange(of: showingBriefing) { _, isNowBriefing in
            if !isNowBriefing { chatFocused = true }
            appeared = false
            withAnimation(.easeOut(duration: 0.25)) { appeared = true }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            GradientBackground()
            VStack(spacing: 0) {
                header
                Divider().opacity(0.3)
                Group {
                    if showingBriefing {
                        briefingContent
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal:   .opacity
                            ))
                    } else {
                        chatContent
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal:   .opacity
                            ))
                    }
                }
                .animation(.easeOut(duration: 0.25), value: showingBriefing)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : -10)
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
                Text(briefingVM.stage.label).font(.caption).foregroundStyle(.secondary)
            }

            Button {
                withAnimation(.easeOut(duration: 0.25)) { showingBriefing.toggle() }
            } label: {
                Image(systemName: showingBriefing ? "bubble.left" : "doc.text")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help(showingBriefing ? "Öppna chat" : "Visa briefing")

            Button { briefingVM.triggerBriefing() } label: {
                Image(systemName: "arrow.clockwise").imageScale(.small)
            }
            .buttonStyle(.plain).help("Uppdatera briefing")

            // Expand button only in popover mode — native close button handles detached mode
            if !isDetached {
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").imageScale(.small)
                }
                .buttonStyle(.plain).help("Expandera")
            }

            Button { showSettings = true } label: {
                Image(systemName: "gearshape").imageScale(.small)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: – Briefing mode

    @ViewBuilder
    private var briefingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let text = briefingVM.result?.briefing {
                    AnimatedBriefingText(text: text)
                } else {
                    HStack(spacing: 8) {
                        if briefingVM.stage != .idle { ProgressView().scaleEffect(0.7) }
                        Text(briefingVM.stage == .idle
                             ? "Tryck ↺ för att generera dagens briefing."
                             : briefingVM.stage.label)
                            .font(.body).foregroundStyle(.secondary)
                    }
                }

                if let prices = briefingVM.result?.plugins.elpris?.data?.prices, !prices.isEmpty {
                    chartSection(prices: prices, elpris: briefingVM.result?.plugins.elpris?.data)
                }
                if let core = briefingVM.result?.plugins.core?.data {
                    recommendationCard(core)
                }
                if let r = briefingVM.result?.plugins.reaktorstatus?.data, r.count > 0 {
                    reaktorCard(r)
                }
                Spacer(minLength: 12)
            }
            .padding(16)
        }
    }

    private func chartSection(prices: [HourPrice], elpris: ElprisData?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("SE3 Spot", systemImage: "bolt.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            let combined = combinedPrices(today: prices, tomorrow: elpris?.tomorrowPrices)
            PriceChartView(prices: combined, currentHour: Calendar.current.component(.hour, from: .now))
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

    private func combinedPrices(today: [HourPrice], tomorrow: [HourPrice]?) -> [HourPrice] {
        guard let t = tomorrow, !t.isEmpty else { return today }
        return today + t.map { HourPrice(hour: $0.hour + 24, priceOreKwh: $0.priceOreKwh) }
    }

    private func statPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

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
        .offset(y: appeared ? 0 : 16).opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.4, bounce: 0.2).delay(0.25), value: appeared)
    }

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

    // MARK: – Chat mode

    @ViewBuilder
    private var chatContent: some View {
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
                                    Spacer()
                                    Text(msg.text)
                                        .font(.body)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(Color.accentColor.opacity(0.15),
                                                    in: RoundedRectangle(cornerRadius: 12))
                                }
                            } else {
                                Text(msg.text)
                                    .font(.body)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(.quaternary.opacity(0.5),
                                                in: RoundedRectangle(cornerRadius: 12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(.opacity)
                            }
                        }

                        if chatVM.isLoading {
                            if chatVM.streamingText.isEmpty {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.65)
                                    Text("Tänker…").font(.callout).foregroundStyle(.secondary)
                                }
                            } else {
                                Text(chatVM.streamingText)
                                    .font(.body)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(.quaternary.opacity(0.5),
                                                in: RoundedRectangle(cornerRadius: 12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if let err = chatVM.error {
                            Text("Fel: \(err)").font(.caption).foregroundStyle(.red)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(14)
                    .animation(.easeOut(duration: 0.2), value: chatVM.messages.count)
                }
                .onAppear {
                    DispatchQueue.main.async { proxy.scrollTo("bottom") }
                }
                .onChange(of: chatVM.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onChange(of: chatVM.isLoading) { _, _ in
                    withAnimation { proxy.scrollTo("bottom") }
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
