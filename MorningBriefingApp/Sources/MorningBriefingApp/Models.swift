import Foundation

struct HourPrice: Identifiable, Codable {
    var id: Int { hour }
    let hour: Int
    let priceOreKwh: Double

    enum CodingKeys: String, CodingKey {
        case hour
        case priceOreKwh = "price_ore_kwh"
    }
}

struct ElprisData: Codable {
    let prices: [HourPrice]
    let tomorrowPrices: [HourPrice]?
    let avgPrice, minPrice, maxPrice: Double

    enum CodingKeys: String, CodingKey {
        case prices
        case tomorrowPrices = "tomorrow_prices"
        case avgPrice = "avg_price"
        case minPrice = "min_price"
        case maxPrice = "max_price"
    }
}

struct CoreData: Codable {
    let recommendation: String
    let cheapestWindowStart, cheapestWindowEnd: Int
    let cheapestWindowAvg, dailyAvg: Double

    enum CodingKeys: String, CodingKey {
        case recommendation
        case cheapestWindowStart = "cheapest_window_start"
        case cheapestWindowEnd   = "cheapest_window_end"
        case cheapestWindowAvg   = "cheapest_window_avg"
        case dailyAvg            = "daily_avg"
    }
}

struct ReaktorData: Codable {
    let count: Int
    let plants: [String]
    let totalUnavailMw: Int?

    enum CodingKeys: String, CodingKey {
        case count, plants
        case totalUnavailMw = "total_unavail_mw"
    }
}

// Wrapper structs matching the plugin JSON envelope
struct PluginEnvelope<T: Codable>: Codable {
    let summary: String
    let data: T?
}

struct BriefingPlugins: Codable {
    let elpris:        PluginEnvelope<ElprisData>?
    let core:          PluginEnvelope<CoreData>?
    let reaktorstatus: PluginEnvelope<ReaktorData>?
}

struct BriefingResult: Codable {
    let briefing:    String
    let generatedAt: String
    let summaries:   [String]
    let plugins:     BriefingPlugins

    enum CodingKeys: String, CodingKey {
        case briefing, summaries, plugins
        case generatedAt = "generated_at"
    }
}

struct StatusResult: Codable {
    let stage: String
    let error: String?
    let ts:    String
}
