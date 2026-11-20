import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("fahrenheit") private var fahrenheit = false
    @AppStorage("windUnit") private var windUnit = "ms"
    @AppStorage("pressureUnit") private var pressureUnit = "hPa"
    @AppStorage("theme") private var theme = "system"
    @AppStorage("proxyURL") private var proxyURL = ""
    @State private var cities = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Единицы измерения") {
                    Picker("Температура", selection: $fahrenheit) { Text("°C").tag(false); Text("°F").tag(true) }
                    Picker("Ветер", selection: $windUnit) { Text("м/с").tag("ms"); Text("км/ч").tag("kmh"); Text("mph").tag("mph") }
                    Picker("Давление", selection: $pressureUnit) { Text("hPa").tag("hPa"); Text("мм рт. ст.").tag("mmHg") }
                }
                Section("Внешний вид") { Picker("Тема", selection: $theme) { Text("Системная").tag("system"); Text("Светлая").tag("light"); Text("Тёмная").tag("dark") } }
                Section("Данные") {
                    TextField("HTTPS-адрес прокси", text: $proxyURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button("Управление городами") { cities = true }
                    if let url = URL(string: "https://www.met.no/en") { Link("Weather data by MET Norway", destination: url) }
                }
                Section("О приложении") { LabeledContent("Версия", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") }
            }.navigationTitle("Настройки")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
                .sheet(isPresented: $cities) { CitiesView() }
        }
    }
}
