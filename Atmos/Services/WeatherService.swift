import Foundation

protocol WeatherServing {
    func forecast(for place: Place, proxy: URL) async throws -> Forecast
}

struct WeatherService: WeatherServing {
    func forecast(for place: Place, proxy: URL) async throws -> Forecast {
        guard var components = URLComponents(url: proxy, resolvingAgainstBaseURL: false), components.scheme == "https" else { throw WeatherError.configuration }
        components.queryItems = [URLQueryItem(name: "lat", value: String(place.latitude)), URLQueryItem(name: "lon", value: String(place.longitude))]
        guard let url = components.url else { throw WeatherError.configuration }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw WeatherError.response }
        guard (200..<300).contains(http.statusCode) else { throw WeatherError.http(http.statusCode) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Forecast.self, from: data)
    }
}

enum WeatherError: LocalizedError {
    case configuration, response, http(Int), empty
    var errorDescription: String? {
        switch self {
        case .configuration: return "Укажите HTTPS-адрес прокси в настройках."
        case .response: return "Не удалось прочитать ответ сервера."
        case .http(let code): return "Сервер погоды вернул ошибку \(code)."
        case .empty: return "Прогноз для этого места пока недоступен."
        }
    }
}

struct CachedForecast: Codable {
    let placeID: UUID
    let savedAt: Date
    let forecast: Forecast
}

protocol ForecastCaching {
    func load(for place: Place) -> CachedForecast?
    func save(_ forecast: Forecast, for place: Place)
}

struct WeatherCache: ForecastCaching {
    private let defaults = UserDefaults.standard
    func load(for place: Place) -> CachedForecast? {
        guard let data = defaults.data(forKey: "forecast.\(place.id.uuidString)") else { return nil }
        return try? JSONDecoder().decode(CachedForecast.self, from: data)
    }
    func save(_ forecast: Forecast, for place: Place) {
        let entry = CachedForecast(placeID: place.id, savedAt: Date(), forecast: forecast)
        if let data = try? JSONEncoder().encode(entry) { defaults.set(data, forKey: "forecast.\(place.id.uuidString)") }
    }
}
