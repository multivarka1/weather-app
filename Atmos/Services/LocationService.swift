import Combine
import CoreLocation
import MapKit

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var error: String?
    var onPlace: ((Place) -> Void)?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    func request() {
        error = nil
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: error = "Доступ к геолокации отключён. Выберите город вручную или измените разрешение в настройках iOS."
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { error = "Доступ к геолокации отключён. Выберите город вручную." }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task {
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            let place = Place(name: placemark?.locality ?? "Моё местоположение", latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, timeZoneIdentifier: placemark?.timeZone?.identifier ?? TimeZone.current.identifier)
            onPlace?(place)
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { self.error = error.localizedDescription }
}
