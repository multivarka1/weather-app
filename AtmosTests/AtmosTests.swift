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
    func testEmptyAndUnits() {
        XCTAssertTrue(forecastDays([], timeZone: .gmt).isEmpty)
        XCTAssertEqual(WeatherDisplay.temperature(0, fahrenheit: true), "32°")
        XCTAssertEqual(WeatherDisplay.temperature(nil, fahrenheit: false), "—")
        XCTAssertEqual(WeatherDisplay.icon("clearsky_night"), "moon.stars.fill")
    }
}
