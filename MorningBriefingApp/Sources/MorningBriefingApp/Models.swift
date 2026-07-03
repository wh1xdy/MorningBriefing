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
    // core.py omits the window fields when there is too little price data to
    // compute one (daily stats and recommendation text are still present).
    let cheapestWindowStart, cheapestWindowEnd: Int?
    let cheapestWindowAvg: Double?
    let dailyAvg: Double

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

    enum CodingKeys: String, CodingKey { case summary, data }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        // A failed plugin serializes `data` as an empty object `{}`, which would
        // otherwise fail to decode into a struct with required fields and take the
        // entire briefing document down with it. Decode leniently so one dead
        // plugin degrades to nil instead of blanking the whole popover.
        data = try? c.decode(T.self, forKey: .data)
    }
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
    let plugins:     BriefingPlugins
    /// Per-plugin failure messages from the aggregator. Non-empty means the
    /// run succeeded but some cards are missing their source data.
    let errors:      [String: String]?

    enum CodingKeys: String, CodingKey {
        case briefing, plugins, errors
        case generatedAt = "generated_at"
    }
}

struct StatusResult: Codable {
    let stage: String
    let error: String?
    let ts:    String
}
