import SwiftUI

@main
struct AtmosApp: App {
    @StateObject private var model = WeatherViewModel()
    @AppStorage("theme") private var theme = "system"
    var body: some Scene {
        WindowGroup {
            HomeView().environmentObject(model)
                .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
        }
    }
}

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var places: [Place] = [] { didSet { persistPlaces() } }
    @Published var selected: Place?
    @Published var forecast: Forecast?
    @Published var cachedAt: Date?
    @Published var error: String?
    @Published var loading = false
    let location = LocationService()
    private let service: any WeatherServing
    private let cache: any ForecastCaching
    private var requestID = UUID()
    init(service: any WeatherServing = WeatherService(), cache: any ForecastCaching = WeatherCache()) {
        self.service = service
        self.cache = cache
        if let data = UserDefaults.standard.data(forKey: "places"), let saved = try? JSONDecoder().decode([Place].self, from: data) { places = saved }
        let selectedID = UserDefaults.standard.string(forKey: "selectedPlace")
        selected = places.first(where: { $0.id.uuidString == selectedID }) ?? places.first
        location.onPlace = { [weak self] place in self?.add(place) }
    }
    private func persistPlaces() {
        if let data = try? JSONEncoder().encode(places) { UserDefaults.standard.set(data, forKey: "places") }
    }
    func add(_ place: Place) {
        if let existing = places.first(where: { abs($0.latitude - place.latitude) < 0.001 && abs($0.longitude - place.longitude) < 0.001 }) { select(existing); return }
        places.append(place)
        select(place)
    }
    func select(_ place: Place) {
        selected = place
        UserDefaults.standard.set(place.id.uuidString, forKey: "selectedPlace")
        Task { await refresh() }
    }
    func delete(at offsets: IndexSet) {
        let removed = offsets.map { places[$0].id }
        places.remove(atOffsets: offsets)
        if let selected, removed.contains(selected.id) {
            self.selected = nil
            forecast = nil
            if let first = places.first { select(first) }
        }
    }
    func refresh() async {
        guard let place = selected else { return }
        let id = UUID(); requestID = id
        let cached = cache.load(for: place)
        forecast = cached?.forecast
        cachedAt = cached?.savedAt
        error = nil
        loading = true
        let proxyString = UserDefaults.standard.string(forKey: "proxyURL") ?? ""
        guard let url = URL(string: proxyString), !proxyString.isEmpty else {
            error = WeatherError.configuration.localizedDescription; loading = false; return
        }
        do {
            let result = try await service.forecast(for: place, proxy: url)
            guard requestID == id else { return }
            guard !result.properties.timeseries.isEmpty else { throw WeatherError.empty }
            cache.save(result, for: place)
            forecast = result; cachedAt = nil
        } catch {
            guard requestID == id else { return }
            self.error = error.localizedDescription
        }
        if requestID == id { loading = false }
    }
}
