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

/// Where a leading-pane screen stops above the floating tab bar in the
/// unfolded split. Content ends `gap` points above the bar, and a row that
/// would cross that line is hidden whole, so no row is sliced and nothing
/// reads through the bar's glass. The edge sits halfway between the last whole
/// row and the first hidden one, above the separator between them, and is
/// drawn with the cards' rounded corners, so a card ends on a whole row. A row
/// taller than `maximumSnap` is cut at the line instead, so one tall card
/// never empties the screen.
enum TabBarClearance {
    static let gap: CGFloat = 16
    static let maximumSnap: CGFloat = 140
    /// Lets the last row scroll fully above the edge.
    static let contentPadding: CGFloat = 28
    /// The inset-grouped cards' margin and corner radius in a phone-width pane.
    static let cardInset: CGFloat = 20
    static let cornerRadius: CGFloat = 26

    /// The edge below which nothing draws, in the rows' coordinate space, or
    /// `nil` off the split (folded, nothing is hidden).
    /// - Parameters:
    ///   - safeBottom: the bottom of the screen's safe area, the bar's top edge.
    ///   - rows: the vertical extent of each row marked `keepsWholeAboveTabBar()`.
    static func edge(isSplit: Bool, safeBottom: CGFloat, rows: [ClosedRange<CGFloat>]) -> CGFloat? {
        guard isSplit else { return nil }
        let line = safeBottom - gap
        let crossing = rows.filter {
            $0.lowerBound < line && $0.upperBound > line && line - $0.lowerBound <= maximumSnap
        }
        // The first row not shown: one the line would slice, else the next below it.
        let firstCrossing = crossing.map(\.lowerBound).min()
        guard let hidden = firstCrossing ?? rows.map(\.lowerBound).filter({ $0 >= line }).min() else {
            return line
        }
        guard let shown = rows.map(\.upperBound).filter({ $0 <= hidden }).max() else {
            return firstCrossing ?? line
        }
        return min(line, max(shown, ((shown + hidden) / 2).rounded(.down) - 1))
    }
}

/// The rows one screen has marked `keepsWholeAboveTabBar()`, in global space.
@MainActor @Observable
final class TabBarClearanceRows {
    private(set) var spans: [UUID: ClosedRange<CGFloat>] = [:]

    func set(_ span: ClosedRange<CGFloat>?, for id: UUID) {
        guard spans[id] != span else { return }
        spans[id] = span
    }
}

extension EnvironmentValues {
    /// True inside the leading pane of the unfolded split, where screens keep
    /// clear of the floating tab bar. The History pane has no bar, so its list
    /// runs to the screen edge as on a phone.
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

    /// See `TabBarClearance`. Applied by each leading-pane screen with its own
    /// page colour, which shows under the bar. Off the split nothing is
    /// hidden, so folding never rebuilds the screen.
    func clearsFloatingTabBar(backdrop: Color = Color(.systemGroupedBackground)) -> some View {
        modifier(ClearsFloatingTabBar(backdrop: backdrop))
    }

    /// Marks a row (a card, a list row, a header or footer) that is shown whole
    /// or not at all above the floating tab bar. A no-op outside a screen that
    /// calls `clearsFloatingTabBar`.
    func keepsWholeAboveTabBar() -> some View {
        modifier(KeepsWholeAboveTabBar())
    }

    /// The pane is only 669 pt tall, so a leading-pane list uses the inline
    /// title Home already has and compact section spacing, instead of spending
    /// a row's height on a large title. Folded, the phone's large title.
    func compactChromeInPane() -> some View {
        modifier(CompactChromeInPane())
    }
}

private struct ClearsFloatingTabBar: ViewModifier {
    @Environment(\.isUnfoldedPane) private var isSplit
    @State private var rows = TabBarClearanceRows()
    @State private var safeBottom: CGFloat = 0
    let backdrop: Color

    private var edge: CGFloat? {
        TabBarClearance.edge(isSplit: isSplit, safeBottom: safeBottom, rows: Array(rows.spans.values))
    }

    func body(content: Content) -> some View {
        let edge = edge
        return content
            .environment(rows)
            .contentMargins(.bottom, isSplit ? TabBarClearance.contentPadding : nil, for: .scrollContent)
            .bottomScrollEdgeEffectHidden(isSplit)
            .mask {
                GeometryReader { proxy in
                    if let edge {
                        ClearanceMask(height: max(edge - proxy.frame(in: .global).minY, 0))
                    } else {
                        Rectangle()
                    }
                }
                .ignoresSafeArea()
            }
            .background(backdrop.ignoresSafeArea())
            // The list's frame already stops at the safe area, so its bottom
            // is the bar's top edge; subtracting the inset again counts the bar twice.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).maxY
            } action: { safeBottom = $0 }
    }
}

/// Everything above the edge, with a card's rounded bottom corners at the card
/// margins. Outside the cards the page colour shows either way.
private struct ClearanceMask: View {
    let height: CGFloat

    var body: some View {
        let radius = min(TabBarClearance.cornerRadius, height)
        ZStack(alignment: .top) {
            Rectangle()
                .frame(height: height - radius)
            UnevenRoundedRectangle(
                bottomLeadingRadius: radius,
                bottomTrailingRadius: radius,
                style: .continuous
            )
            .padding(.horizontal, TabBarClearance.cardInset)
            .frame(height: height)
        }
    }
}

private struct KeepsWholeAboveTabBar: ViewModifier {
    @Environment(TabBarClearanceRows.self) private var rows: TabBarClearanceRows?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: ClosedRange<CGFloat>.self) { proxy in
                let frame = proxy.frame(in: .global)
                return frame.minY...max(frame.minY, frame.maxY)
            } action: { rows?.set($0, for: id) }
            .onDisappear { rows?.set(nil, for: id) }
    }
}

private struct CompactChromeInPane: ViewModifier {
    @Environment(\.isUnfoldedPane) private var isSplit

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(isSplit ? .inline : .automatic)
            .listSectionSpacing(isSplit ? .compact : .default)
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
            // Built only while the display is split, so a phone never lays the
            // pane out at zero width where VoiceOver and UI tests still find it.
            if let split {
                trailing
                    .frame(width: split.secondaryWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, split.secondaryX)
            }
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
