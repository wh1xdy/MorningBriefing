import SwiftUI
import Charts

// MARK: – Fade-from-top helper

private extension View {
    func fadeFromTop(_ visible: Bool, delay: Double = 0) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : -8)
            .animation(.spring(duration: 0.35, bounce: 0.1).delay(delay), value: visible)
    }
}

// MARK: – iMessage-style bubble insertion modifier

private struct BubbleInsert: ViewModifier {
    let visible: Bool
    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.92, anchor: .bottom)
            .offset(y: visible ? 0 : 14)
    }
}

// MARK: – Liquid glass card helper

private extension View {
    // Uses native macOS 26 Liquid Glass. The rect shape must be passed explicitly
    // because DefaultGlassEffectShape (capsule) is wrong for rectangular cards.
    func glassCard(cornerRadius: CGFloat = 14) -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
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
            // No custom background — NSPopover on macOS 26 draws native Liquid Glass
            // (including the correctly-tinted arrow) when SwiftUI content is transparent.

            if showSettings {
                SettingsView(isShowing: $showSettings)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                mainContent
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: 340, height: 520)
        .background(.clear)
        .contentShape(Rectangle())   // keeps the view hit-testable with a clear bg
        .animation(.spring(duration: 0.35, bounce: 0.12), value: showSettings)
        .onAppear { animateIn() }
        .onReceive(NotificationCenter.default.publisher(for: .mbPopoverWillOpen)) { _ in
            if showSettings { showSettings = false }
            animateIn()
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .chat { chatFocused = true }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header.fadeFromTop(appeared, delay: 0.00)
            contentArea
        }
    }

    private func animateIn() {
        openToken = UUID()
        appeared  = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { appeared = true }
    }

    // MARK: – Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            // App icon + title — frame matches button frames so baseline aligns
            Image(systemName: "bolt.fill")
                .foregroundStyle(.yellow)
                .imageScale(.small)
                .frame(width: 16, height: 16)
            Text("MorningBriefing")
                .font(.system(.subheadline, weight: .semibold))

            Spacer()

            // Status cluster
            HStack(spacing: 4) {
                if let avg = briefingVM.result?.plugins.elpris?.data?.avgPrice {
                    Text(String(format: "snitt %.0f öre", avg))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Group {
                    if briefingVM.stage == .aggregating || briefingVM.stage == .generating {
                        ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                    } else if case .error = briefingVM.stage {
                        Image(systemName: "exclamationmark.circle.fill")
                            .imageScale(.small)
                            .foregroundStyle(.red.opacity(0.8))
                            .help(briefingVM.stage.label)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: briefingVM.stage == .ready)

            // Controls
            headerButton(icon: mode == .briefing ? "bubble.left" : "doc.text",
                         help: mode == .briefing ? "Öppna chat" : "Visa briefing") {
                withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                    mode = mode == .briefing ? .chat : .briefing
                }
            }
            headerButton(icon: "arrow.clockwise", help: "Uppdatera briefing") {
                briefingVM.triggerBriefing()
            }
            headerButton(icon: "gearshape", help: "Inställningar") {
                withAnimation(.spring(duration: 0.35, bounce: 0.12)) { showSettings = true }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder
    private func headerButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .imageScale(.small)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: – Content area (briefing / chat)

    @ViewBuilder
    private var contentArea: some View {
        ZStack {
            if mode == .briefing {
                briefingPane
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                chatPane
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.1), value: mode)
    }

    // MARK: – Briefing pane

    private var briefingPane: some View {
        ScrollView {
            // GlassEffectContainer groups all glass cards so they sample
            // the scene once and morph correctly when near each other.
            GlassEffectContainer {
                VStack(alignment: .leading, spacing: 14) {
                    briefingTextSection
                        .fadeFromTop(appeared, delay: 0.05)

                    if let elpris = briefingVM.result?.plugins.elpris?.data, !elpris.prices.isEmpty {
                        chartCard(elpris)
                            .fadeFromTop(appeared, delay: 0.10)
                    }

                    if let core = briefingVM.result?.plugins.core?.data {
                        recommendationCard(core)
                            .fadeFromTop(appeared, delay: 0.14)
                    }

                    if let r = briefingVM.result?.plugins.reaktorstatus?.data,
                       r.count > 0 || (r.upcomingCount ?? 0) > 0 {
                        reaktorCard(r)
                            .fadeFromTop(appeared, delay: 0.18)
                    }

                    if let vf = briefingVM.result?.plugins.vattenfall?.data,
                       !vf.offline.isEmpty {
                        forsmarkCard(vf)
                            .fadeFromTop(appeared, delay: 0.22)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var briefingTextSection: some View {
        if let text = briefingVM.result?.briefing {
            AnimatedBriefingText(text: text)
                .id(openToken)
        } else {
            HStack(spacing: 8) {
                if briefingVM.stage == .aggregating || briefingVM.stage == .generating {
                    ProgressView().scaleEffect(0.7)
                }
                let isError: Bool = { if case .error = briefingVM.stage { return true }; return false }()
                Text(briefingVM.stage == .idle
                     ? "Tryck ↺ för att generera dagens briefing."
                     : briefingVM.stage.label)
                    .font(.body)
                    .foregroundStyle(isError ? AnyShapeStyle(.red) : AnyShapeStyle(Color.secondary))
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            PriceChartView(
                prices: combined,
                currentHour: Calendar.current.component(.hour, from: .now)
            )

            HStack(spacing: 6) {
                statPill("Snitt", String(format: "%.1f öre", elpris.avgPrice))
                statPill("Min",   String(format: "%.1f öre", elpris.minPrice))
                statPill("Max",   String(format: "%.1f öre", elpris.maxPrice))
            }
        }
        .padding(12)
        .glassCard()
    }

    private func statPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: – Recommendation card

    private func recommendationCard(_ core: CoreData) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.badge.checkmark.fill")
                .foregroundStyle(.green)
                .font(.title3)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Kör tunga jobb")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(String(format: "%02d:00 – %02d:00",
                            core.cheapestWindowStart, core.cheapestWindowEnd))
                    .font(.title3.monospacedDigit().weight(.semibold))
                Text(String(format: "%.1f öre/kWh  (%d%% under dagsnitt)",
                            core.cheapestWindowAvg,
                            Int(((core.dailyAvg - core.cheapestWindowAvg)
                                 / max(core.dailyAvg, 0.01)) * 100)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.green.opacity(0.3), lineWidth: 0.8)
        )
    }

    // MARK: – Reaktor card

    private func reaktorCard(_ r: ReaktorData) -> some View {
        let hasActive = r.count > 0
        let color: Color = hasActive ? .orange : .yellow

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: hasActive ? "exclamationmark.triangle.fill" : "calendar.badge.exclamationmark")
                .foregroundStyle(color)
                .font(.title3)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(hasActive ? "Nukleär UMM pågår" : "Nukleär UMM planerad")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if hasActive {
                    Text(r.plants.joined(separator: ", "))
                        .font(.callout.weight(.medium))
                    if let mw = r.totalUnavailMw, mw > 0 {
                        Text("\(mw) MW otillgängliga")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let up = r.upcomingPlants, !up.isEmpty {
                    Text((hasActive ? "Planerad: " : "") + up.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(hasActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary.opacity(0.7)))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(color.opacity(0.35), lineWidth: 0.8)
        )
    }

    // MARK: – Forsmark production card

    private func forsmarkCard(_ vf: VattenfallData) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "atom")
                .foregroundStyle(.red)
                .font(.title3)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Forsmark – nere för underhåll")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(vf.blocks, id: \.block) { b in
                        VStack(spacing: 1) {
                            Text(b.block)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(b.offline ? .red : .secondary)
                            Text(b.offline ? "offline" : "\(b.productionMw) MW")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(b.offline ? .red : .primary)
                        }
                    }
                }
                Text("Källa: Vattenfall realtidsdata")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.red.opacity(0.3), lineWidth: 0.8))
    }

    // MARK: – Chat pane

    private var chatPane: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if chatVM.messages.isEmpty && !chatVM.isLoading {
                            Text("Ställ en fråga om elmarknaden eller dagens briefing.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.top, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ForEach(chatVM.messages) { msg in
                            chatBubble(msg)
                                .transition(.asymmetric(
                                    insertion: .modifier(
                                        active:   BubbleInsert(visible: false),
                                        identity: BubbleInsert(visible: true)
                                    ),
                                    removal: .opacity
                                ))
                        }

                        if chatVM.isLoading {
                            if chatVM.streamingText.isEmpty {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.65)
                                    Text("Tänker…").font(.callout).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14)
                            } else {
                                assistantBubble(chatVM.streamingText)
                            }
                        } else if let err = chatVM.error {
                            Text(err)
                                .font(.caption).foregroundStyle(.red)
                                .padding(.horizontal, 14)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 10)
                }
                .scrollIndicators(.hidden)
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

            Divider().opacity(0.2)

            // Input bar
            HStack(spacing: 8) {
                TextField("Fråga om elmarknaden…", text: $chatInput)
                    .font(.body)
                    .textFieldStyle(.plain)
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

    @ViewBuilder
    private func chatBubble(_ msg: ChatMessage) -> some View {
        if msg.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(msg.text)
                    .font(.body)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 8)
        } else {
            assistantBubble(msg.text)
        }
    }

    @ViewBuilder
    private func assistantBubble(_ text: String) -> some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .glassCard(cornerRadius: 16)
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 8)
    }

    private func submitChat() {
        let q = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !chatVM.isLoading else { return }
        chatInput = ""
        chatVM.send(q)
    }
}
