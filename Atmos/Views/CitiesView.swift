import SwiftUI
import MapKit

@MainActor
final class CitySearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" { didSet { completer.queryFragment = query } }
    @Published var results: [MKLocalSearchCompletion] = []
    @Published var error: String?
    private let completer = MKLocalSearchCompleter()
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) { results = completer.results }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) { self.error = error.localizedDescription }
    func resolve(_ result: MKLocalSearchCompletion) async -> Place? {
        do {
            let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: result)).start()
            guard let item = response.mapItems.first else { return nil }
            let coordinate = item.placemark.coordinate
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            return Place(name: item.placemark.locality ?? item.name ?? result.title, latitude: coordinate.latitude, longitude: coordinate.longitude, timeZoneIdentifier: placemark?.timeZone?.identifier ?? TimeZone.current.identifier)
        } catch { self.error = error.localizedDescription; return nil }
    }
}

struct CitiesView: View {
    @EnvironmentObject private var model: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = CitySearch()
    var body: some View {
        NavigationStack {
            List {
                if search.query.isEmpty {
                    Section("Местоположение") {
                        Button { model.location.request(); dismiss() } label: { Label("Моё местоположение", systemImage: "location.fill") }
                    }
                    Section("Сохранённые города") {
                        ForEach(model.places) { place in
                            Button { model.select(place); dismiss() } label: {
                                HStack { Text(place.name); Spacer(); if place.id == model.selected?.id { Image(systemName: "checkmark") } }
                            }
                        }.onDelete(perform: model.delete)
                    }
                } else {
                    ForEach(search.results, id: \.self) { result in
                        Button {
                            Task { if let place = await search.resolve(result) { model.add(place); dismiss() } }
                        } label: { VStack(alignment: .leading) { Text(result.title); Text(result.subtitle).font(.caption).foregroundStyle(.secondary) } }
                    }
                }
                if let error = search.error ?? model.location.error { Text(error).foregroundStyle(.secondary) }
            }.searchable(text: $search.query, prompt: "Поиск города")
                .navigationTitle("Города")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}
