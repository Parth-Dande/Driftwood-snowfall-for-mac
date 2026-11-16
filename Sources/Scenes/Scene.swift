import SwiftUI

/// A wallpaper and the weather that falls over it.
struct Scene: Identifiable {
    /// The weather this scene shows. Each kind of weather belongs to exactly one scene.
    let weather: WeatherKind
    /// The scene's title.
    let name: String
    /// A one-line description shown under the title.
    let caption: String
    /// The SF Symbol that stands for this scene in the gallery.
    let symbolName: String
    /// The scene's accent colour as a 24-bit RGB value.
    let glowHex: UInt32

    /// A stable identifier, also the name of the scene's bundled picture.
    var id: String { weather.rawValue }

    /// Every scene, in the order the gallery shows them.
    static let all = [
        Scene(weather: .snow, name: "Snow Lantern Inn", caption: "Warm windows on a snowy mountainside", symbolName: "snowflake", glowHex: 0xF5EBD7),
        Scene(weather: .rain, name: "The Rainy Bookshop", caption: "Amber windows and rain-slick cobbles", symbolName: "cloud.rain", glowHex: 0xD0E3C8),
        Scene(weather: .petals, name: "Blossom Creek", caption: "A spring morning by the footbridge", symbolName: "leaf", glowHex: 0xFFE4C6),
        Scene(weather: .leaves, name: "Cider Mill", caption: "Maple leaves and a turning waterwheel", symbolName: "leaf.fill", glowHex: 0xFFE2A1),
        Scene(weather: .fireflies, name: "Lantern Marsh", caption: "Fireflies along a little marsh boardwalk", symbolName: "lightbulb", glowHex: 0xE9EF9F),
        Scene(weather: .stars, name: "Campfire Lake", caption: "A little camp beneath the Milky Way", symbolName: "sparkles", glowHex: 0xF2DCFF),
        Scene(weather: .cash, name: "Neon Coast", caption: "Banknotes over a city sunset by the sea", symbolName: "banknote", glowHex: 0xFFC2DD)
    ]
}

extension Color {
    /// Creates a colour from a 24-bit RGB value such as `0xF5EBD7`.
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
