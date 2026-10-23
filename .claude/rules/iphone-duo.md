---
paths:
  - "HeadacheLogger/Views/RootTabView.swift"
  - "HeadacheLogger/Views/HistoryView.swift"
  - "HeadacheLogger/Views/InsightsView.swift"
  - "HeadacheLogger/Views/OnboardingView.swift"
  - "HeadacheLogger/Utilities/UnfoldedSplit.swift"
  - "HeadacheLoggerTests/UnfoldedSplitTests.swift"
---

# Migraine Headache Tracker: iPhone Duo (2026-10-21)

- Unfolded (regular width, room for two panes of at least 360 pt),
  `RootTabView` puts the tab view (One Tap, Patterns, Settings and its bar) on
  the leading side of the fold and History in its own pane on the trailing
  side; the History tab leaves the bar while split. Pane edges come from
  `GeometryProxy.verticalFold()` (iOS 27.1 `reservedRegions(.division)`), else
  an even split (`UnfoldedSplit`, tested in `UnfoldedSplitTests`). The folded
  Duo, portrait phones and the unfolded Duo held in portrait keep the single
  column. A Plus/Max phone in landscape is regular width too and splits evenly.
- Folding only moves frames: the `TabView` is never rebuilt. History moves
  between its tab and the pane, so its year filter lives in `RootTabView`
  (`historyYear`). Keep new History state there.
- Each tab's content and the History pane get `horizontalSizeClass = .compact`,
  so they lay out as on a phone. Never set it on the `TabView` itself (in Quit
  Zyn that flipped the Duo's vertical bar to a bottom bar on a tab switch).
- Unfolded, every leading tab keeps the phone's bottom tab bar
  (`horizontalBarsInPane`: `toolbarVerticalBehavior(.disabled)` while split,
  else iOS 27.1 picks a vertical rail on some launches). Each screen calls
  `.clearsFloatingTabBar(backdrop:)` with its own page colour: in a pane
  (`\.isUnfoldedPane`) its content dissolves 8 pt above the bar, or above the
  home indicator in the History pane, and a bottom content margin lets the last
  row scroll clear (`TabBarClearance`, tested). A hard scroll edge was not
  enough: rows were sliced at the edge of its backdrop. Folded, it is a no-op.
- Onboarding uses `.unfoldedLeadingPane`, with `OnboardingFoldPanel` in the
  trailing pane. Sheets (paywall, trial offer, details, edit) are still system
  form sheets centred on the inner display.
- History's heatmap always spans 90 days (`HeatmapData.padded`; days before the
  first log are outlined). Its cells are square `Grid` cells that share the
  card's width (`HeatmapLayout.weekColumns`); measuring the width instead let the
  card overflow its row in the History pane. Title, legend and caption live
  inside the card (a plain list footer drew a white band), so the whole card
  ends above the pane's bottom fade.
- Captures: `gh-sim all --device 'iPhone Duo' --scheme HeadacheLogger --wait 10
  --args "-uitesting -HeadacheScreenshotSeed -HeadacheProOverride
  -HeadacheScreenshotBrand"` plus one `--screen "-HeadacheDuoScreen <name>"`
  per surface: `log`, `history`, `patterns`, `pattern` (pushes the top
  pattern's detail) and `settings` (DEBUG, read once at launch). Never `--url`:
  iOS 27.1 raises an "Open in" alert for every openurl. The seed's first log is
  past the 90-day window, so History's counts hold across midnight.
