import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: WeatherViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("fahrenheit") private var fahrenheit = false
    @AppStorage("windUnit") private var windUnit = "ms"
    @AppStorage("pressureUnit") private var pressureUnit = "hPa"
    @State private var cities = false
    @State private var settings = false
    var points: [Forecast.Point] { model.forecast?.properties.timeseries.filter { $0.time >= Date().addingTimeInterval(-3600) } ?? [] }
    var body: some View {
        NavigationStack {
            ZStack {
                WeatherBackground(code: points.first?.data.symbol).animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: points.first?.data.symbol)
                ScrollView {
                    VStack(spacing: 16) {
                        if let place = model.selected {
                            header(place)
                            if let error = model.error { Text(error).font(.footnote).padding().frame(maxWidth: .infinity, alignment: .leading).adaptiveGlass() }
                            if let cachedAt = model.cachedAt { Text("Сохранённый прогноз · \(cachedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                            if let point = points.first {
                                current(point, place: place)
                                hourly(place)
                                daily(place)
                                details(point)
                            } else if model.loading {
                                ProgressView("Загружаем прогноз").padding(40).frame(maxWidth: .infinity).adaptiveGlass()
                            } else if model.error == nil {
                                Text("Нет данных прогноза").padding()
                            }
                        } else {
                            VStack(spacing: 18) {
                                Image(systemName: "cloud.sun.fill").font(.system(size: 72)).symbolRenderingMode(.multicolor)
                                Text("Погода ближе").font(.largeTitle.bold())
                                Text("Узнайте прогноз для вашего местоположения или найдите город.").multilineTextAlignment(.center)
                                Button("Использовать геолокацию") { model.location.request() }.buttonStyle(.borderedProminent)
                                Button("Найти город") { cities = true }.buttonStyle(.bordered)
                                if let error = model.location.error { Text(error).font(.footnote) }
                            }.padding(30).frame(maxWidth: .infinity).adaptiveGlass()
                        }
                        if let url = URL(string: "https://www.yr.no/") { Link("Weather data by MET Norway", destination: url).font(.footnote).padding() }
                    }.padding()
                }.refreshable { await model.refresh() }
            }.foregroundStyle(.white)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button { cities = true } label: { Image(systemName: "list.bullet") }.accessibilityLabel("Города") }
                    ToolbarItem(placement: .topBarTrailing) { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Настройки") }
                }
                .toolbarColorScheme(.dark, for: .navigationBar)
                .sheet(isPresented: $cities) { CitiesView() }
                .sheet(isPresented: $settings) { SettingsView() }
                .task { if model.selected != nil && model.forecast == nil { await model.refresh() } }
        }
    }
    func dateText(_ date: Date, zone: TimeZone, format: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate(format)
        return formatter.string(from: date)
    }
    func header(_ place: Place) -> some View {
        VStack(spacing: 4) {
            Text(place.name).font(.largeTitle.weight(.medium)).multilineTextAlignment(.center)
            Text(dateText(Date(), zone: place.timeZone, format: "EEEE, d MMMM")).font(.subheadline)
        }.padding(.top, 16)
    }
    func current(_ point: Forecast.Point, place: Place) -> some View {
        VStack(spacing: 8) {
            Image(systemName: WeatherDisplay.icon(point.data.symbol)).symbolRenderingMode(.multicolor).font(.system(size: 76)).padding(.top)
            Text(WeatherDisplay.temperature(point.data.instant.details.airTemperature, fahrenheit: fahrenheit)).font(.system(size: 80, weight: .thin, design: .rounded)).minimumScaleFactor(0.5)
            Text(WeatherDisplay.description(point.data.symbol)).font(.title3.weight(.medium))
            if let day = forecastDays(points, timeZone: place.timeZone).first {
                Text("Макс. \(WeatherDisplay.temperature(day.maximum, fahrenheit: fahrenheit))   Мин. \(WeatherDisplay.temperature(day.minimum, fahrenheit: fahrenheit))").font(.subheadline)
            }
            Text("Прогноз на \(dateText(point.time, zone: place.timeZone, format: "HH:mm"))").font(.caption)
        }.frame(maxWidth: .infinity).padding(.bottom, 20)
    }
    func hourly(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("ПОЧАСОВОЙ ПРОГНОЗ", systemImage: "clock").font(.caption.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(Array(points.prefix(24).enumerated()), id: \.element.id) { index, point in
                        VStack(spacing: 10) {
                            Text(index == 0 ? "Сейчас" : dateText(point.time, zone: place.timeZone, format: "HH:mm")).font(.caption.weight(index == 0 ? .bold : .regular))
                            Image(systemName: WeatherDisplay.icon(point.data.symbol)).symbolRenderingMode(.multicolor).font(.title3)
                            Text(WeatherDisplay.temperature(point.data.instant.details.airTemperature, fahrenheit: fahrenheit)).bold()
                            if let p = point.data.next1Hours?.details?.probabilityOfPrecipitation { Text("\(Int(p))% ").font(.caption2) }
                            if let p = point.data.next1Hours?.details?.precipitationAmount { Text(String(format: "%.1f мм", p)).font(.caption2) }
                        }.frame(minWidth: 48)
                    }
                }
            }
        }.padding(18).adaptiveGlass()
    }
    func daily(_ place: Place) -> some View {
        let days = forecastDays(points, timeZone: place.timeZone)
        let low = days.compactMap(\.minimum).min() ?? 0
        let high = days.compactMap(\.maximum).max() ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            Label("ПРОГНОЗ ПО ДНЯМ", systemImage: "calendar").font(.caption.weight(.semibold))
            ForEach(days) { day in
                HStack {
                    Text(dateText(day.date, zone: place.timeZone, format: "EEE")).frame(width: 45, alignment: .leading)
                    Image(systemName: WeatherDisplay.icon(day.symbol)).symbolRenderingMode(.multicolor).frame(width: 30)
                    Text(WeatherDisplay.temperature(day.minimum, fahrenheit: fahrenheit)).frame(width: 42)
                    GeometryReader { proxy in
                        if let min = day.minimum, let max = day.maximum {
                            let span = Swift.max(high - low, 1)
                            Capsule().fill(.white.opacity(0.2)).overlay(alignment: .leading) {
                                Capsule().fill(LinearGradient(colors: [.cyan, .yellow], startPoint: .leading, endPoint: .trailing)).frame(width: Swift.max(4, proxy.size.width * CGFloat((max - min) / span))).offset(x: proxy.size.width * CGFloat((min - low) / span))
                            }
                        }
                    }.frame(height: 5)
                    Text(WeatherDisplay.temperature(day.maximum, fahrenheit: fahrenheit)).frame(width: 42)
                }.font(.subheadline)
            }
        }.padding(18).adaptiveGlass()
    }
    func details(_ point: Forecast.Point) -> some View {
        let d = point.data.instant.details
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if let v = d.relativeHumidity { metric("Влажность", value: "\(Int(v))%", icon: "humidity") }
            if let v = d.windSpeed { metric("Ветер", value: wind(v), icon: "wind") }
            if let v = d.windFromDirection { metric("Направление ветра", value: "\(Int(v))°", icon: "location.north") }
            if let v = d.windSpeedOfGust { metric("Порывы ветра", value: wind(v), icon: "wind") }
            if let v = d.airPressureAtSeaLevel { metric("Давление", value: pressure(v), icon: "barometer") }
            if let v = d.cloudAreaFraction { metric("Облачность", value: "\(Int(v))%", icon: "cloud") }
            if let v = point.data.next1Hours?.details?.precipitationAmount { metric("Осадки за час", value: String(format: "%.1f мм", v), icon: "drop") }
        }
    }
    func wind(_ value: Double) -> String {
        switch windUnit {
        case "kmh": return String(format: "%.1f км/ч", value * 3.6)
        case "mph": return String(format: "%.1f mph", value * 2.236936)
        default: return String(format: "%.1f м/с", value)
        }
    }
    func pressure(_ value: Double) -> String {
        pressureUnit == "mmHg" ? String(format: "%.0f мм рт. ст.", value * 0.7500617) : String(format: "%.0f hPa", value)
    }
    func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) { Label(title, systemImage: icon).font(.caption); Text(value).font(.title3.bold()) }.frame(maxWidth: .infinity, minHeight: 76, alignment: .leading).padding(16).adaptiveGlass()
    }
}
