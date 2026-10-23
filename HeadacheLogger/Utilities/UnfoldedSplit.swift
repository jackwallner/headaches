import SwiftUI

/// Pane frames for the unfolded iPhone Duo: One Tap and the other tabs on the
/// leading side of the fold, History on the trailing side, so nothing straddles
/// the crease. `nil` keeps the single column (every ordinary iPhone, the folded
/// Duo, and the unfolded Duo held in portrait, where each half is too narrow).
struct UnfoldedSplit: Equatable, Sendable {
    var primaryWidth: CGFloat
    var secondaryX: CGFloat
    var secondaryWidth: CGFloat

    /// Narrowest pane that still fits the compact One Tap and History layouts.
    static let minimumPaneWidth: CGFloat = 360

    /// - Parameters:
    ///   - width: the container's width.
    ///   - fold: the vertical fold's leading and trailing edge in the same
    ///     coordinate space, or `nil` when the system reports none.
    static func make(width: CGFloat, isRegularWidth: Bool, fold: ClosedRange<CGFloat>?) -> UnfoldedSplit? {
        guard isRegularWidth, width >= minimumPaneWidth * 2 else { return nil }
        if let fold,
           fold.lowerBound >= minimumPaneWidth,
           width - fold.upperBound >= minimumPaneWidth {
            return UnfoldedSplit(
                primaryWidth: fold.lowerBound,
                secondaryX: fold.upperBound,
                secondaryWidth: width - fold.upperBound
            )
        }
        let half = (width / 2).rounded(.down)
        return UnfoldedSplit(primaryWidth: half, secondaryX: half, secondaryWidth: width - half)
    }
}

/// The container's width and fold, measured together so one geometry change
/// moves both panes.
struct PaneGeometry: Equatable, Sendable {
    var width: CGFloat = 0
    var fold: ClosedRange<CGFloat>?
}

extension GeometryProxy {
    /// The vertical fold's horizontal extent in this proxy's space. Inactive
    /// folds count too, so the panes don't jump while the device opens.
    func verticalFold() -> ClosedRange<CGFloat>? {
        guard #available(iOS 27.1, *) else { return nil }
        let fold = reservedRegions(kind: .division, options: .includeInactive)
            .map(\.frame)
            .first { $0.height > $0.width && $0.minX > 0 && $0.maxX < size.width }
        guard let fold else { return nil }
        return fold.minX...fold.maxX
    }
}

/// How far content stays clear of the floating tab bar in the unfolded split.
/// Content dissolves over `fade` and is hidden for `hidden` points above the
/// bottom edge (the bar's inset plus a gap), so no row is sliced by the bar or
/// reads through its glass; `contentPadding` lets the last row scroll clear.
struct TabBarClearance: Equatable, Sendable {
    var fade: CGFloat
    var hidden: CGFloat
    var contentPadding: CGFloat

    static let fadeHeight: CGFloat = 36
    static let gap: CGFloat = 8

    static func make(isSplit: Bool, barInset: CGFloat) -> TabBarClearance {
        guard isSplit else { return TabBarClearance(fade: 0, hidden: 0, contentPadding: 0) }
        return TabBarClearance(
            fade: fadeHeight,
            hidden: max(barInset, 0) + gap,
            contentPadding: fadeHeight + gap
        )
    }
}

extension EnvironmentValues {
    /// True inside a pane of the unfolded split, where screens keep clear of
    /// the floating tab bar (or the home indicator in the History pane).
    @Entry var isUnfoldedPane: Bool = false
}

extension View {
    /// A leading-pane tab keeps the phone's horizontal bars while split. iOS
    /// 27.1 otherwise moves a tab's toolbar, and the tab bar with it, into a
    /// vertical rail on some launches and not others. Folded, the default.
    @ViewBuilder
    func horizontalBarsInPane(_ isSplit: Bool) -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(isSplit ? .disabled : .automatic)
        } else {
            self
        }
    }

    /// See `TabBarClearance`. Applied by each screen with its own page colour,
    /// which shows under the bar. Off the split the mask is fully open, so
    /// folding never rebuilds the screen.
    func clearsFloatingTabBar(backdrop: Color = Color(.systemGroupedBackground)) -> some View {
        modifier(ClearsFloatingTabBar(backdrop: backdrop))
    }
}

private struct ClearsFloatingTabBar: ViewModifier {
    @Environment(\.isUnfoldedPane) private var isSplit
    @State private var barInset: CGFloat = 0
    let backdrop: Color

    private var clearance: TabBarClearance {
        .make(isSplit: isSplit, barInset: barInset)
    }

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, isSplit ? clearance.contentPadding : nil, for: .scrollContent)
            .bottomScrollEdgeEffectHidden(isSplit)
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    // Ink is gone within the first 16 pt, so no faint glyphs
                    // linger above the bar.
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.4), location: 0.2),
                            .init(color: .black.opacity(0.06), location: 0.35),
                            .init(color: .clear, location: 0.45),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: clearance.fade)
                    Color.clear.frame(height: clearance.hidden)
                }
                .ignoresSafeArea()
            }
            .background(backdrop.ignoresSafeArea())
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { barInset = $0 }
    }
}

private extension View {
    @ViewBuilder
    func bottomScrollEdgeEffectHidden(_ hidden: Bool) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(hidden, for: .bottom)
        } else {
            self
        }
    }
}

/// Keeps a single-column screen (onboarding) on the leading side of the fold
/// and puts `trailing` in the other pane. Every other width shows the screen as
/// it is. Only frames change, so a fold mid-step keeps the screen's state.
struct UnfoldedLeadingPane<Trailing: View>: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var geometry = PaneGeometry()
    let trailing: Trailing

    private var split: UnfoldedSplit? {
        UnfoldedSplit.make(width: geometry.width, isRegularWidth: horizontalSizeClass == .regular, fold: geometry.fold)
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            content
                .environment(\.horizontalSizeClass, split == nil ? horizontalSizeClass : .compact)
                .frame(maxWidth: split?.primaryWidth ?? .infinity, maxHeight: .infinity)
            trailing
                .frame(width: split?.secondaryWidth ?? 0)
                .frame(maxHeight: .infinity)
                .padding(.leading, split?.secondaryX ?? 0)
                .opacity(split == nil ? 0 : 1)
                .accessibilityHidden(split == nil)
        }
        .onGeometryChange(for: PaneGeometry.self) { proxy in
            PaneGeometry(width: proxy.size.width, fold: proxy.verticalFold())
        } action: { geometry = $0 }
    }
}

extension View {
    func unfoldedLeadingPane<Trailing: View>(@ViewBuilder trailing: () -> Trailing) -> some View {
        modifier(UnfoldedLeadingPane(trailing: trailing()))
    }
}
