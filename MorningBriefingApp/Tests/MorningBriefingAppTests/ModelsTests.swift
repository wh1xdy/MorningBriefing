import XCTest
@testable import MorningBriefingApp

/// Regression coverage for the JSON contract with the Python pipeline.
/// The shapes here mirror what bridge.py / aggregator.py actually write.
final class ModelsTests: XCTestCase {

    // A failed plugin serializes as {"plugin": ..., "error": ..., "summary": ..., "data": {}}.
    // The tolerant PluginEnvelope decode must degrade that to data == nil instead
    // of failing the envelope (and with it the whole briefing document).
    func testEmptyDataObjectDecodesToNil() throws {
        let json = #"{"plugin": "vattenfall", "summary": "[vattenfall failed]", "data": {}}"#
        let env = try JSONDecoder().decode(PluginEnvelope<VattenfallData>.self, from: Data(json.utf8))
        XCTAssertNil(env.data)
        XCTAssertEqual(env.summary, "[vattenfall failed]")
    }

    func testMissingAndNullDataDecodeToNil() throws {
        for json in [#"{"summary": "s"}"#, #"{"summary": "s", "data": null}"#] {
            let env = try JSONDecoder().decode(PluginEnvelope<ElprisData>.self, from: Data(json.utf8))
            XCTAssertNil(env.data, "expected nil data for: \(json)")
        }
    }

    // One dead plugin must not take down the rest of the document.
    func testBriefingResultSurvivesOneFailedPlugin() throws {
        let json = """
        {
          "briefing": "Testbriefing.",
          "generated_at": "2026-07-03T05:00:00Z",
          "summaries": ["a", "b"],
          "plugins": {
            "elpris": {
              "summary": "ok",
              "data": {
                "date": "2026-07-03",
                "prices": [{"hour": 0, "price_ore_kwh": 41.5}],
                "avg_price": 41.5, "min_price": 41.5, "max_price": 41.5
              }
            },
            "vattenfall": {"plugin": "vattenfall", "error": "boom", "summary": "[vattenfall failed]", "data": {}}
          },
          "errors": {"vattenfall": "boom"}
        }
        """
        let result = try JSONDecoder().decode(BriefingResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.briefing, "Testbriefing.")
        XCTAssertNotNil(result.plugins.elpris?.data, "healthy plugin must still decode")
        XCTAssertNil(result.plugins.vattenfall?.data, "failed plugin degrades to nil data")
        XCTAssertEqual(result.errors?["vattenfall"], "boom")
    }

    // The errors dict is optional: older latest.json files without it must decode.
    func testErrorsKeyIsOptional() throws {
        let json = #"{"briefing": "b", "generated_at": "2026-07-03T05:00:00Z", "plugins": {}}"#
        let result = try JSONDecoder().decode(BriefingResult.self, from: Data(json.utf8))
        XCTAssertNil(result.errors)
    }

    // core.py omits the window fields entirely when it can't compute a window;
    // the rest of the core payload must still decode.
    func testCoreDataDecodesWithoutWindowFields() throws {
        let json = #"{"summary": "s", "data": {"recommendation": "Otillräcklig prisdata", "daily_avg": 55.0}}"#
        let env = try JSONDecoder().decode(PluginEnvelope<CoreData>.self, from: Data(json.utf8))
        XCTAssertNotNil(env.data)
        XCTAssertNil(env.data?.cheapestWindowStart)
        XCTAssertEqual(env.data?.dailyAvg, 55.0)
    }

    // Negative spot prices are legal in SE3 — the model layer must not lose the sign.
    func testNegativePricesRoundTrip() throws {
        let json = #"{"summary": "s", "data": {"prices": [{"hour": 3, "price_ore_kwh": -12.4}], "avg_price": -1.0, "min_price": -12.4, "max_price": 8.0}}"#
        let env = try JSONDecoder().decode(PluginEnvelope<ElprisData>.self, from: Data(json.utf8))
        XCTAssertEqual(env.data?.prices.first?.priceOreKwh, -12.4)
        XCTAssertEqual(env.data?.minPrice, -12.4)
    }
}
