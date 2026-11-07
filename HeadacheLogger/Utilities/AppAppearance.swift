import SwiftUI

enum AppAppearance: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func from(storageValue: Int) -> AppAppearance {
        AppAppearance(rawValue: storageValue) ?? .system
    }
}

/// The app's colors. Every text color meets 4.5:1 on the card and page
/// backgrounds in light and dark. `brand` is the fill (white text on it is at
/// least 4.5:1); `brandText` is the same hue for text and symbols on a light
/// or dark surface. The tint colors are for text; fills stay on system colors.
enum AppTheme {
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    /// Fill behind white text (the Log Headache button, "Show me").
    static let brand = Color(red: 0xD9 / 255, green: 0x2D / 255, blue: 0x4B / 255)
    static let brandEnd = Color(red: 0xDB / 255, green: 0x29 / 255, blue: 0x6E / 255)
    /// Brand hue as text, symbols and the app tint.
    static let brandText = dynamic(light: 0xBD2039, dark: 0xFF5C74)

    /// Secondary text. The system `.secondary` is about 3.4:1 on white.
    static let secondaryText = dynamic(light: 0x4A4A4F, dark: 0xB0B0B6)

    static let slight = dynamic(light: 0x785600, dark: 0xFFD60A)
    /// Solid orange behind white text.
    static let orangeFill = Color(red: 0xA8 / 255, green: 0x44 / 255, blue: 0x00)
    static let orange = dynamic(light: 0xA84400, dark: 0xFF9F0A)
    static let red = dynamic(light: 0xB81A1A, dark: 0xFF6B63)
    static let green = dynamic(light: 0x13692C, dark: 0x32D74B)
    static let teal = dynamic(light: 0x0D6B64, dark: 0x40D0C0)
    static let indigo = dynamic(light: 0x4338CA, dark: 0x8E8CFF)
    static let cyan = dynamic(light: 0x0C6B85, dark: 0x64D2FF)
    static let pink = dynamic(light: 0xB01553, dark: 0xFF6482)
    static let purple = dynamic(light: 0x7E22CE, dark: 0xC47DFF)
    static let blue = dynamic(light: 0x1D4ED8, dark: 0x6EA8FF)
}

/// State changes that animate only when Reduce Motion is off.
enum Motion {
    static let standard = Animation.easeInOut(duration: 0.25)

    static func animate(reduce: Bool, _ animation: Animation = standard, _ body: () -> Void) {
        if reduce {
            body()
        } else {
            withAnimation(animation, body)
        }
    }
}
