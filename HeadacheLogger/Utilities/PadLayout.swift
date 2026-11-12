import SwiftUI
import UIKit

/// iPad: a screen keeps a readable column in the middle of the window instead of
/// stretching edge to edge. The page colour fills the sides, so the window reads
/// as one surface. Compact widths (iPhone, iPad Split View at a third) and every
/// iPhone are untouched.
private struct PadReadableColumn: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let maxWidth: CGFloat
    var maxHeight: CGFloat = .infinity

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    func body(content: Content) -> some View {
        if isPad && horizontalSizeClass == .regular {
            content
                .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
        } else {
            content
        }
    }
}

extension View {
    /// Caps a screen's width on iPad. 680 pt matches the system's readable list
    /// width; pass a smaller value for sparse screens such as onboarding.
    func padReadableColumn(maxWidth: CGFloat = 680, maxHeight: CGFloat = .infinity) -> some View {
        modifier(PadReadableColumn(maxWidth: maxWidth, maxHeight: maxHeight))
    }
}

extension Color {
    /// A plain page's colour: the grouped page colour on iPad, so it matches the
    /// sides the readable column leaves; `phone` on iPhone.
    static func padPageOr(_ phone: UIColor) -> Color {
        UIDevice.current.userInterfaceIdiom == .pad ? Color(.systemGroupedBackground) : Color(phone)
    }
}

extension View {
    /// A sheet is a centred form-sized card on iPad rather than a full-width
    /// slab. A no-op on iPhone.
    @ViewBuilder
    func padFormSheet() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.form)
        } else {
            self
        }
    }
}
