import XCTest
@testable import Atmos

final class AtmosTests: XCTestCase {
    func testDecodeAndDailyAggregation() throws {
        let json = """
        {"properties":{"timeseries":[
          {"time":"2026-01-01T23:00:00Z","data":{"instant":{"details":{"air_temperature":2}},"next_1_hours":{"summary":{"symbol_code":"clearsky_night"},"details":{"precipitation_amount":0}}}},
          {"time":"2026-01-02T01:00:00Z","data":{"instant":{"details":{"air_temperature":5}}}}
        ]}}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let forecast = try decoder.decode(Forecast.self, from: Data(json.utf8))
        XCTAssertEqual(forecast.properties.timeseries.first?.data.symbol, "clearsky_night")
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 2 * 3600))
        let days = forecastDays(forecast.properties.timeseries, timeZone: zone)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days.first?.minimum, 2)
        XCTAssertEqual(days.first?.maximum, 5)
    }
    func testWindDirection() {
        XCTAssertEqual(WeatherDisplay.windDirection(0), "Север")
        XCTAssertEqual(WeatherDisplay.windDirection(22.5), "Северо-восток")
        XCTAssertEqual(WeatherDisplay.windDirection(180), "Юг")
        XCTAssertEqual(WeatherDisplay.windDirection(337.5), "Север")
        XCTAssertEqual(WeatherDisplay.windDirection(360), "Север")
        XCTAssertNil(WeatherDisplay.windDirection(-1))
        XCTAssertNil(WeatherDisplay.windDirection(.nan))
    }
    func testEmptyAndUnits() {
        XCTAssertTrue(forecastDays([], timeZone: .gmt).isEmpty)
        XCTAssertEqual(WeatherDisplay.temperature(0, fahrenheit: true), "32°")
        XCTAssertEqual(WeatherDisplay.temperature(nil, fahrenheit: false), "—")
        XCTAssertEqual(WeatherDisplay.icon("clearsky_night"), "moon.stars.fill")
    }
}

private struct DelayedWeatherService: WeatherServing {
    func forecast(for place: Place, proxy: URL) async throws -> Forecast {
        try await Task.sleep(nanoseconds: 200_000_000)
        let json = """
        {"properties":{"timeseries":[{"time":"2026-01-01T23:00:00Z","data":{"instant":{"details":{"air_temperature":2}}}}]}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Forecast.self, from: Data(json.utf8))
    }
}

private struct EmptyCache: ForecastCaching {
    func load(for place: Place) -> CachedForecast? { nil }
    func save(_ forecast: Forecast, for place: Place) {}
}

extension AtmosTests {
    @MainActor
    func testRefreshSurvivesCallerCancellation() async throws {
        let previous = UserDefaults.standard.object(forKey: "proxyURL")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "proxyURL") }
            else { UserDefaults.standard.removeObject(forKey: "proxyURL") }
        }
        UserDefaults.standard.set("https://example.com", forKey: "proxyURL")
        let model = WeatherViewModel(service: DelayedWeatherService(), cache: EmptyCache())
        model.selected = Place(name: "Test", latitude: 0, longitude: 0, timeZoneIdentifier: "UTC")
        let caller = Task { await model.refresh() }
        try await Task.sleep(nanoseconds: 50_000_000)
        caller.cancel()
        await caller.value
        XCTAssertNil(model.error)
        XCTAssertEqual(model.forecast?.properties.timeseries.count, 1)
        XCTAssertFalse(model.loading)
    }
}
