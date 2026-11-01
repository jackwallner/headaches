import SwiftUI
import UIKit

extension Color {
    /// System secondary text is 3.4:1 on the grouped cards; this is 6:1 in light
    /// mode and the system value in dark mode.
    static let readableSecondary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .secondaryLabel : UIColor(white: 0.38, alpha: 1)
    })

    /// The brand pink as text: 5:1 on white and on the grouped backgrounds,
    /// where the brand fill itself is 3.6:1.
    static let readableBrand = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.25, blue: 0.36, alpha: 1)
            : UIColor(red: 0.80, green: 0.14, blue: 0.28, alpha: 1)
    })

    /// The brand pink as a fill behind white text, 5:1 in both modes
    /// (`readableBrand` lightens in dark mode, where white on it is 3.4:1).
    static let brandFill = Color(red: 0.80, green: 0.14, blue: 0.28)

    /// Orange as text or a filled button behind white text, 4.8:1 in light mode.
    static let readableOrange = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemOrange : UIColor(red: 0.72, green: 0.34, blue: 0, alpha: 1)
    })
}
