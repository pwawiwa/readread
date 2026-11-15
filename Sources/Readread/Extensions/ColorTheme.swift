import SwiftUI
import AppKit

enum PaperTheme: String, CaseIterable, Identifiable {
    case brokenWhite = "Broken White"
    case sepia = "Sepia"
    case pureWhite = "Pure White"
    case dark = "Dark"

    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .brokenWhite:
            return NSColor(red: 245/255, green: 240/255, blue: 231/255, alpha: 1.0) // #F5F0E7
        case .sepia:
            return NSColor(red: 244/255, green: 236/255, blue: 216/255, alpha: 1.0) // #F4ECD8
        case .pureWhite:
            return NSColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 1.0) // #FFFFFF
        case .dark:
            return NSColor(red: 28/255, green: 26/255, blue: 23/255, alpha: 1.0) // #1C1A17
        }
    }

    var color: Color {
        Color(nsColor: nsColor)
    }
}

private func dynamicColor(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? dark : light
    }))
}

extension Color {
    // Editorial Reading-Room Palette (DESIGN.md)
    static let editorialCanvas = dynamicColor(
        light: NSColor(red: 245/255, green: 240/255, blue: 231/255, alpha: 1.0), // #F5F0E7
        dark: NSColor(red: 28/255, green: 26/255, blue: 23/255, alpha: 1.0)     // #1C1A17
    )

    static let editorialPaper = dynamicColor(
        light: NSColor(red: 252/255, green: 250/255, blue: 245/255, alpha: 1.0), // #FCFAF5
        dark: NSColor(red: 38/255, green: 35/255, blue: 31/255, alpha: 1.0)     // #26231F
    )

    static let editorialInk = dynamicColor(
        light: NSColor(red: 47/255, green: 43/255, blue: 37/255, alpha: 1.0),    // #2F2B25
        dark: NSColor(red: 242/255, green: 237/255, blue: 228/255, alpha: 1.0)  // #F2EDE4
    )

    static let editorialSecondaryInk = dynamicColor(
        light: NSColor(red: 107/255, green: 98/255, blue: 88/255, alpha: 1.0),  // #6B6258
        dark: NSColor(red: 176/255, green: 167/255, blue: 155/255, alpha: 1.0)  // #B0A79B
    )

    static let editorialAccent = dynamicColor(
        light: NSColor(red: 138/255, green: 75/255, blue: 44/255, alpha: 1.0),   // #8A4B2C
        dark: NSColor(red: 196/255, green: 117/255, blue: 77/255, alpha: 1.0)   // #C4754D
    )

    static let editorialRule = dynamicColor(
        light: NSColor(red: 47/255, green: 43/255, blue: 37/255, alpha: 0.12),
        dark: NSColor(red: 242/255, green: 237/255, blue: 228/255, alpha: 0.12)
    )

    // Backwards-compatible aliases
    static let offWhite = editorialCanvas
    static let brokenWhite = Color(red: 245/255, green: 240/255, blue: 231/255)
    static let warmCream = dynamicColor(
        light: NSColor(red: 239/255, green: 233/255, blue: 222/255, alpha: 1.0),
        dark: NSColor(red: 34/255, green: 31/255, blue: 27/255, alpha: 1.0)
    )
    static let paperWhite = editorialPaper
    static let sidebarBg = dynamicColor(
        light: NSColor(red: 240/255, green: 235/255, blue: 226/255, alpha: 1.0),
        dark: NSColor(red: 24/255, green: 23/255, blue: 20/255, alpha: 1.0)
    )
    static let textPrimary = editorialInk
    static let textSecondary = editorialSecondaryInk
    static let accentBrown = editorialAccent
}

extension NSColor {
    static let brokenWhitePaper = NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: 28/255, green: 26/255, blue: 23/255, alpha: 1.0)     // #1C1A17
            : NSColor(red: 245/255, green: 240/255, blue: 231/255, alpha: 1.0) // #F5F0E7
    })

    static let offWhitePaper = NSColor.brokenWhitePaper
}
