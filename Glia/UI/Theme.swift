import SwiftUI
import simd

/// Glia's palette. Node colors carry meaning (page type); the ea source
/// shifts everything toward a cooler blue so the two brains read apart
/// at a glance. Values are linear-ish sRGB tuned on the Metal canvas.
enum Theme {
    static let background = Color(red: 0.043, green: 0.051, blue: 0.071)
    static let accent = Color(red: 0.486, green: 0.361, blue: 1.0)      // #7C5CFF

    private static let typeColors: [String: SIMD4<Float>] = [
        "person":          SIMD4(0.32, 0.84, 0.54, 1),   // green
        "company":         SIMD4(1.00, 0.62, 0.31, 1),   // orange
        "concept":         SIMD4(0.90, 0.78, 0.31, 1),   // gold
        "note":            SIMD4(0.88, 0.35, 0.45, 1),   // rose
        "atom":            SIMD4(0.62, 0.55, 1.00, 1),   // violet
        "source":          SIMD4(0.39, 0.44, 0.54, 1),   // slate
        "extract_receipt": SIMD4(0.31, 0.76, 0.76, 1),   // teal
        "original":        SIMD4(0.85, 0.55, 1.00, 1),   // orchid
        "meeting":         SIMD4(0.31, 0.66, 1.00, 1),   // blue
    ]
    private static let otherColor = SIMD4<Float>(0.54, 0.57, 0.65, 1)
    private static let eaTint = SIMD4<Float>(0.22, 0.74, 0.97, 1)       // #38BDF8

    static func color(type: String, source: String) -> SIMD4<Float> {
        let base = typeColors[type] ?? otherColor
        guard source == "ea" else { return base }
        return simd_mix(base, eaTint, SIMD4(repeating: 0.42))
    }

    static func swatch(type: String) -> Color {
        let c = typeColors[type] ?? otherColor
        return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }

    static func edgeColor(focused: Bool) -> SIMD4<Float> {
        focused
            ? SIMD4(0.48, 0.52, 0.64, 0.42)
            : SIMD4(0.48, 0.52, 0.64, 0.05)
    }
}
