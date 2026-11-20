import Foundation

struct Place: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String
    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
}

struct Forecast: Codable {
    let properties: Properties
    struct Properties: Codable { let timeseries: [Point] }
    struct Point: Codable, Identifiable {
        var id: Date { time }
        let time: Date
        let data: Data
    }
    struct Data: Codable {
        let instant: Instant
        let next1Hours: Interval?
        let next6Hours: Interval?
        let next12Hours: Interval?
        enum CodingKeys: String, CodingKey {
            case instant
            case next1Hours = "next_1_hours", next6Hours = "next_6_hours", next12Hours = "next_12_hours"
        }
        var symbol: String? { next1Hours?.summary?.symbolCode ?? next6Hours?.summary?.symbolCode ?? next12Hours?.summary?.symbolCode }
    }
    struct Instant: Codable { let details: Details }
    struct Details: Codable {
        let airTemperature: Double?
        let relativeHumidity: Double?
        let windSpeed: Double?
        let windFromDirection: Double?
        let windSpeedOfGust: Double?
        let airPressureAtSeaLevel: Double?
        let cloudAreaFraction: Double?
        enum CodingKeys: String, CodingKey {
            case airTemperature = "air_temperature", relativeHumidity = "relative_humidity", windSpeed = "wind_speed"
            case windFromDirection = "wind_from_direction", windSpeedOfGust = "wind_speed_of_gust"
            case airPressureAtSeaLevel = "air_pressure_at_sea_level", cloudAreaFraction = "cloud_area_fraction"
        }
    }
    struct Interval: Codable {
        let summary: Summary?
        let details: IntervalDetails?
    }
    struct Summary: Codable {
        let symbolCode: String?
        enum CodingKeys: String, CodingKey { case symbolCode = "symbol_code" }
    }
    struct IntervalDetails: Codable {
        let precipitationAmount: Double?
        let probabilityOfPrecipitation: Double?
        enum CodingKeys: String, CodingKey {
            case precipitationAmount = "precipitation_amount", probabilityOfPrecipitation = "probability_of_precipitation"
        }
    }
}

struct ForecastDay: Identifiable {
    let date: Date
    let points: [Forecast.Point]
    var id: Date { date }
    var minimum: Double? { points.compactMap { $0.data.instant.details.airTemperature }.min() }
    var maximum: Double? { points.compactMap { $0.data.instant.details.airTemperature }.max() }
    var symbol: String? { points.min(by: { abs($0.time.timeIntervalSince(date.addingTimeInterval(12 * 3600))) < abs($1.time.timeIntervalSince(date.addingTimeInterval(12 * 3600))) })?.data.symbol }
}

func forecastDays(_ points: [Forecast.Point], timeZone: TimeZone) -> [ForecastDay] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let groups = Dictionary(grouping: points) { calendar.startOfDay(for: $0.time) }
    return groups.keys.sorted().prefix(9).map { ForecastDay(date: $0, points: groups[$0] ?? []) }
}

enum WeatherDisplay {
    static func temperature(_ value: Double?, fahrenheit: Bool) -> String {
        guard let value else { return "—" }
        return "\(Int((fahrenheit ? value * 9 / 5 + 32 : value).rounded()))°"
    }
    // MET Norway reports the direction the wind comes from, clockwise from north.
    static func windDirection(_ degrees: Double) -> String? {
        guard degrees.isFinite, (0...360).contains(degrees) else { return nil }
        let directions = ["Север", "Северо-восток", "Восток", "Юго-восток", "Юг", "Юго-запад", "Запад", "Северо-запад"]
        let index = Int((degrees / 45).rounded()) % directions.count
        return directions[index]
    }
    static func icon(_ code: String?) -> String {
        guard let code else { return "cloud" }
        let night = code.contains("night")
        if code.contains("thunder") { return "cloud.bolt.rain.fill" }
        if code.contains("snow") || code.contains("sleet") { return "cloud.snow.fill" }
        if code.contains("rain") { return "cloud.rain.fill" }
        if code.contains("fog") { return "cloud.fog.fill" }
        if code.contains("partlycloudy") || code.contains("fair") { return night ? "cloud.moon.fill" : "cloud.sun.fill" }
        if code.contains("cloudy") { return "cloud.fill" }
        if code.contains("clearsky") { return night ? "moon.stars.fill" : "sun.max.fill" }
        return "cloud.fill"
    }
    static func description(_ code: String?) -> String {
        guard let code else { return "Нет описания" }
        return code.replacingOccurrences(of: "_day", with: "").replacingOccurrences(of: "_night", with: "").replacingOccurrences(of: "_polartwilight", with: "").replacingOccurrences(of: "_", with: " ").capitalized
    }
}
