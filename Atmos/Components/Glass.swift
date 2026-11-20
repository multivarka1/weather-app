import SwiftUI

struct AdaptiveGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
        } else if #available(iOS 26.0, *) {
            GlassEffectContainer {
                content.glassEffect(.regular, in: .rect(cornerRadius: 24))
            }
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.25)))
        }
    }
}
extension View { func adaptiveGlass() -> some View { modifier(AdaptiveGlass()) } }

struct WeatherBackground: View {
    let code: String?
    var colors: [Color] {
        guard let code else { return [.blue, .indigo] }
        if code.contains("night") { return [Color(red: 0.04, green: 0.08, blue: 0.22), .indigo] }
        if code.contains("thunder") { return [.black, .purple, .indigo] }
        if code.contains("snow") { return [.gray, .cyan, .blue] }
        if code.contains("rain") { return [.indigo, .blue, .teal] }
        if code.contains("cloud") { return [.gray, .blue, .cyan] }
        return [.blue, .cyan, Color(red: 0.65, green: 0.78, blue: 0.85)]
    }
    var body: some View { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea() }
}
