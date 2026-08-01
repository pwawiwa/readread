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
            return NSColor(red: 250/255, green: 247/255, blue: 240/255, alpha: 1.0) // #FAF7F0
        case .sepia:
            return NSColor(red: 244/255, green: 236/255, blue: 216/255, alpha: 1.0) // #F4ECD8
        case .pureWhite:
            return NSColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 1.0) // #FFFFFF
        case .dark:
            return NSColor(red: 28/255, green: 27/255, blue: 25/255, alpha: 1.0) // #1C1C1A
        }
    }
    
    var color: Color {
        Color(nsColor: nsColor)
    }
}

extension Color {
    // Dynamic broken white and cream paper colors
    static let offWhite = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.name == .darkAqua || appearance.name == .vibrantDark
        ? NSColor(red: 28/255, green: 27/255, blue: 25/255, alpha: 1.0)
        : NSColor(red: 250/255, green: 247/255, blue: 240/255, alpha: 1.0) // Broken white #FAF7F0
    }))
    
    static let brokenWhite = Color(red: 250/255, green: 247/255, blue: 240/255) // #FAF7F0
    
    static let warmCream = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.name == .darkAqua || appearance.name == .vibrantDark
        ? NSColor(red: 38/255, green: 37/255, blue: 34/255, alpha: 1.0)
        : NSColor(red: 245/255, green: 242/255, blue: 235/255, alpha: 1.0)
    }))
    
    static let paperWhite = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.name == .darkAqua || appearance.name == .vibrantDark
        ? NSColor(red: 45/255, green: 44/255, blue: 40/255, alpha: 1.0)
        : NSColor(red: 252/255, green: 251/255, blue: 248/255, alpha: 1.0)
    }))
    
    static let sidebarBg = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.name == .darkAqua || appearance.name == .vibrantDark
        ? NSColor(red: 24/255, green: 24/255, blue: 22/255, alpha: 1.0)
        : NSColor(red: 245/255, green: 244/255, blue: 241/255, alpha: 1.0)
    }))
    
    static let textPrimary = Color(nsColor: NSColor.labelColor)
    static let textSecondary = Color(nsColor: NSColor.secondaryLabelColor)
    static let accentBrown = Color(red: 139/255, green: 90/255, blue: 43/255)
}

extension NSColor {
    static let brokenWhitePaper = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.name == .darkAqua || appearance.name == .vibrantDark
        ? NSColor(red: 28/255, green: 27/255, blue: 25/255, alpha: 1.0)
        : NSColor(red: 250/255, green: 247/255, blue: 240/255, alpha: 1.0) // Warm broken white (#FAF7F0)
    })
    
    static let offWhitePaper = NSColor.brokenWhitePaper
}
