import SwiftUI
import Charts

struct PriceChartView: View {
    let prices: [HourPrice]
    let currentHour: Int

    @State private var animatedDomain: Int = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var hoverHour: Int? = nil      // nil = no hover

    private var maxHour: Int { prices.map(\.hour).max() ?? 23 }
    private var has48h: Bool { maxHour > 23 }
    private var domainEnd: Int { has48h ? 47 : 23 }
    private var maxY: Double { (prices.map(\.priceOreKwh).max() ?? 100) * 1.15 }
    private var currentPrice: Double? { prices.first(where: { $0.hour == currentHour })?.priceOreKwh }
    private var hoverPrice: Double? {
        guard let h = hoverHour else { return nil }
        return prices.first(where: { $0.hour == h })?.priceOreKwh
    }

    private var xAxisValues: [Int] {
        has48h ? [0, 6, 12, 18, 24, 30, 36, 42, 47] : [0, 6, 12, 18, 23]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Hover tooltip — fixed height so the chart doesn't jump
            HStack(spacing: 4) {
                if let h = hoverHour, let p = hoverPrice {
                    Text(h >= 24 ? "\(h - 24):00 (imorgon)" : "\(h):00")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(String(format: "%.1f öre/kWh", p))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                } else {
                    Text(" ").font(.caption2)   // invisible placeholder, keeps height
                }
            }
            .animation(.easeInOut(duration: 0.1), value: hoverHour)

            Chart {
                ForEach(prices.filter { $0.hour <= animatedDomain }) { p in
                    AreaMark(
                        x: .value("h", p.hour),
                        yStart: .value("base", 0),
                        yEnd:   .value("öre", p.priceOreKwh)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("h", p.hour),
                        y: .value("öre", p.priceOreKwh)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }

                // Today/tomorrow separator
                if has48h && animatedDomain >= 24 {
                    RuleMark(x: .value("sep", 24))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Imorgon")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .offset(x: 3, y: -2)
                        }
                }

                // Hover crosshair
                if let h = hoverHour, let p = hoverPrice {
                    RuleMark(x: .value("hover", h))
                        .foregroundStyle(Color.primary.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    PointMark(x: .value("h", h), y: .value("öre", p))
                        .foregroundStyle(Color.primary)
                        .symbolSize(28)
                }

                // Current-hour pulse dot (hide when hover is nearby)
                if let cp = currentPrice, currentHour <= animatedDomain,
                   hoverHour.map({ abs($0 - currentHour) > 1 }) ?? true {
                    PointMark(x: .value("h", currentHour), y: .value("öre", cp))
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(36)
                    PointMark(x: .value("h", currentHour), y: .value("öre", cp))
                        .foregroundStyle(Color.accentColor.opacity(0.25))
                        .symbolSize(36 * pulseScale)
                }
            }
            .chartXScale(domain: 0...domainEnd)
            .chartXAxis {
                AxisMarks(values: xAxisValues) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel {
                        let h = v.as(Int.self) ?? 0
                        Text(h >= 24 ? "\(h - 24)h" : "\(h)h")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel {
                        Text("\(v.as(Int.self) ?? 0)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .chartYScale(domain: 0...maxY)
            .frame(height: 100)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    let x = v.location.x - geo[proxy.plotAreaFrame].origin.x
                                    if let h: Int = proxy.value(atX: x) {
                                        hoverHour = max(0, min(domainEnd, h))
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.2)) { hoverHour = nil }
                                }
                        )
                        .onHover { hovering in
                            if !hovering {
                                withAnimation(.easeOut(duration: 0.2)) { hoverHour = nil }
                            }
                        }
                }
            }
            .onAppear {
                withAnimation(.spring(duration: 0.6, bounce: 0.1)) { animatedDomain = maxHour }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulseScale = 2.2 }
            }
        }
    }
}
