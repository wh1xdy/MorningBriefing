import SwiftUI
import Charts

struct PriceChartView: View {
    let prices: [HourPrice]
    let currentHour: Int

    @State private var animatedDomain: Int = 0
    @State private var pulseScale: CGFloat = 1.0

    private var maxY: Double { (prices.map(\.priceOreKwh).max() ?? 100) * 1.15 }
    private var currentPrice: Double? { prices.first(where: { $0.hour == currentHour })?.priceOreKwh }

    var body: some View {
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

            // Current-hour pulse dot
            if let cp = currentPrice, currentHour <= animatedDomain {
                PointMark(
                    x: .value("h", currentHour),
                    y: .value("öre", cp)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(36)

                PointMark(
                    x: .value("h", currentHour),
                    y: .value("öre", cp)
                )
                .foregroundStyle(Color.accentColor.opacity(0.25))
                .symbolSize(36 * pulseScale)
            }
        }
        .chartXScale(domain: 0...23)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)h").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .chartYScale(domain: 0...maxY)
        .frame(height: 100)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.1)) {
                animatedDomain = prices.map(\.hour).max() ?? 23
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseScale = 2.2
            }
        }
    }
}
