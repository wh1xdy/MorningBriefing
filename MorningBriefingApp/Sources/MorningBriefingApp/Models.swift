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
    let date: String?
    let prices: [HourPrice]
    let tomorrowPrices: [HourPrice]?
    let avgPrice, minPrice, maxPrice: Double

    enum CodingKeys: String, CodingKey {
        case date
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
    let upcomingCount: Int?
    let upcomingPlants: [String]?

    enum CodingKeys: String, CodingKey {
        case count, plants
        case totalUnavailMw  = "total_unavail_mw"
        case upcomingCount   = "upcoming_count"
        case upcomingPlants  = "upcoming_plants"
    }
}

struct VaderData: Codable {
    let currentTempC:    Double?
    let currentWindMs:   Double?
    let currentCloudPct: Double?
    let dailyAvgTempC:   Double?
    let dailyAvgWindMs:  Double?
    let windNote:        String?
    let location:        String?

    enum CodingKeys: String, CodingKey {
        case currentTempC    = "current_temp_c"
        case currentWindMs   = "current_wind_ms"
        case currentCloudPct = "current_cloud_pct"
        case dailyAvgTempC   = "daily_avg_temp_c"
        case dailyAvgWindMs  = "daily_avg_wind_ms"
        case windNote        = "wind_note"
        case location
    }
}

struct VattenfallBlock: Codable {
    let block: String
    let productionMw: Int
    let capacityMw: Int
    let percent: Double
    let offline: Bool

    enum CodingKeys: String, CodingKey {
        case block
        case productionMw = "production_mw"
        case capacityMw   = "capacity_mw"
        case percent, offline
    }
}

struct VattenfallData: Codable {
    let plant: String
    let blocks: [VattenfallBlock]
    let offline: [String]
    let totalMw: Int
    let totalCapMw: Int

    enum CodingKeys: String, CodingKey {
        case plant, blocks, offline
        case totalMw    = "total_mw"
        case totalCapMw = "total_cap_mw"
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
    let vader:         PluginEnvelope<VaderData>?
    let vattenfall:    PluginEnvelope<VattenfallData>?
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
