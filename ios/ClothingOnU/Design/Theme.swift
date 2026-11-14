import SwiftUI

/// One palette, one spacing scale, one radius scale. Every view uses these; no ad-hoc values.
enum Theme {
    // Warm neutrals that sit next to the studio backdrop of the renders without clashing.
    static let canvas = Color(light: 0xF4F1EC, dark: 0x121110)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1D1C1A)
    static let ink = Color(light: 0x1B1A19, dark: 0xF2EFEA)
    static let secondaryInk = Color(light: 0x6E6A65, dark: 0xA39E97)
    static let hairline = Color(light: 0xE4DFD8, dark: 0x2E2C29)
    /// Backdrop of the generated photos; used behind them so letterboxing is invisible.
    static let studio = Color(light: 0xCFC7BE, dark: 0xCFC7BE)
    static let accent = Color.accentColor
    static let warning = Color(light: 0xB4690E, dark: 0xF0A54A)
    static let danger = Color(light: 0xB3261E, dark: 0xF2B8B5)

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let s: CGFloat = 10
        static let m: CGFloat = 16
        static let l: CGFloat = 24
    }

    /// Display type is the system serif (New York) for an editorial feel; everything else is SF.
    static func display(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .serif).weight(.semibold)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
