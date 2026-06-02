import Foundation

// Hardcoded snapshot from 2026-05-22 pipeline run — used until real data loads.
extension BriefingResult {
    static let placeholder = BriefingResult(
        briefing: "Energiprisen i SE3 den 22:e maj var 90.23 öre/kWh med en spridning från 20.26 till 145.07 öre/kWh. Enheten Forsmark Block2 i Sverige är nedstängd med en total kapacitet på 1121 MW och kommer vara nedstängd till den 26:e juni. Vindproduktionen är begränsad på grund av svag vind. Baserat på prisanalysen rekommenderas tunga jobb att köras mellan 12:00 och 16:00 då priset ligger på 26.41 öre/kWh, 70.7% under dagsnittet.",
        generatedAt: "2026-05-22T09:32:30Z",
        summaries: [
            "SE3 snittpris 2026-05-22: 90.23 öre/kWh (min 20.26 / max 145.07).",
            "1 aktiv nukleär UMM i Norden. Berörda: Forsmark Block2. Totalt unavailable: 1121 MW.",
            "Billigaste 4h: 12–16 @ 26.41 öre/kWh. Dagsnitt 90.23, spread 20.26–145.07 öre/kWh.",
            "Stockholm nu: 16.8°C, vind 4.2 m/s. Svag vind – begränsad vindproduktion.",
        ],
        plugins: BriefingPlugins(
            elpris: PluginEnvelope(
                summary: "SE3 snittpris: 90.23 öre/kWh",
                data: ElprisData(
                    prices: [
                        HourPrice(hour: 0,  priceOreKwh: 97.13),
                        HourPrice(hour: 1,  priceOreKwh: 95.15),
                        HourPrice(hour: 2,  priceOreKwh: 94.22),
                        HourPrice(hour: 3,  priceOreKwh: 93.17),
                        HourPrice(hour: 4,  priceOreKwh: 92.84),
                        HourPrice(hour: 5,  priceOreKwh: 121.95),
                        HourPrice(hour: 6,  priceOreKwh: 139.02),
                        HourPrice(hour: 7,  priceOreKwh: 140.95),
                        HourPrice(hour: 8,  priceOreKwh: 129.67),
                        HourPrice(hour: 9,  priceOreKwh: 96.61),
                        HourPrice(hour: 10, priceOreKwh: 50.55),
                        HourPrice(hour: 11, priceOreKwh: 38.87),
                        HourPrice(hour: 12, priceOreKwh: 30.51),
                        HourPrice(hour: 13, priceOreKwh: 27.20),
                        HourPrice(hour: 14, priceOreKwh: 20.26),
                        HourPrice(hour: 15, priceOreKwh: 27.67),
                        HourPrice(hour: 16, priceOreKwh: 61.45),
                        HourPrice(hour: 17, priceOreKwh: 89.60),
                        HourPrice(hour: 18, priceOreKwh: 118.64),
                        HourPrice(hour: 19, priceOreKwh: 137.19),
                        HourPrice(hour: 20, priceOreKwh: 145.07),
                        HourPrice(hour: 21, priceOreKwh: 132.87),
                        HourPrice(hour: 22, priceOreKwh: 96.80),
                        HourPrice(hour: 23, priceOreKwh: 88.03),
                    ],
                    tomorrowPrices: nil,
                    avgPrice: 90.23, minPrice: 20.26, maxPrice: 145.07
                )
            ),
            core: PluginEnvelope(
                summary: "Billigaste 4h: 12–16 @ 26.41 öre/kWh",
                data: CoreData(
                    recommendation: "Kör tunga jobb 12:00–16:00 (26.41 öre/kWh, 70.7% under dagsnitt)",
                    cheapestWindowStart: 12, cheapestWindowEnd: 16,
                    cheapestWindowAvg: 26.41, dailyAvg: 90.23
                )
            ),
            reaktorstatus: PluginEnvelope(
                summary: "1 aktiv nukleär UMM: Forsmark Block2",
                data: ReaktorData(count: 1, plants: ["Forsmark Block2"], totalUnavailMw: 1121,
                                  upcomingCount: nil, upcomingPlants: nil)
            ),
            vader: PluginEnvelope(
                summary: "Stockholm nu: 16.8°C, vind 4.2 m/s.",
                data: VaderData(
                    currentTempC: 16.8, currentWindMs: 4.2, currentCloudPct: 55,
                    dailyAvgTempC: 15.5, dailyAvgWindMs: 3.3,
                    windNote: "Svag vind – begränsad vindproduktion.",
                    location: "Stockholm"
                )
            )
        )
    )
}
