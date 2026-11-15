import AppKit
import SwiftUI

struct Scene: Identifiable {
    let id: String
    let name: String
    let caption: String
    let symbol: String
    let glow: UInt32

    static let catalog = [
        Scene(id: "snow", name: "Snow Lantern Inn", caption: "Warm windows on a snowy mountainside", symbol: "snowflake", glow: 0xF5EBD7),
        Scene(id: "rain", name: "The Rainy Bookshop", caption: "Amber windows and rain-slick cobbles", symbol: "cloud.rain", glow: 0xD0E3C8),
        Scene(id: "petals", name: "Blossom Creek", caption: "A spring morning by the footbridge", symbol: "leaf", glow: 0xFFE4C6),
        Scene(id: "leaves", name: "Cider Mill", caption: "Maple leaves and a turning waterwheel", symbol: "leaf.fill", glow: 0xFFE2A1),
        Scene(id: "fireflies", name: "Lantern Marsh", caption: "Fireflies along a little marsh boardwalk", symbol: "lightbulb", glow: 0xE9EF9F),
        Scene(id: "stars", name: "Campfire Lake", caption: "A little camp beneath the Milky Way", symbol: "sparkles", glow: 0xF2DCFF)
    ]
}

func ink(_ hex: UInt32) -> Color {
    Color(red: Double(hex >> 16) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
}
