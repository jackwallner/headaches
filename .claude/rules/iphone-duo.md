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
  else iOS 27.1 picks a vertical rail on some launches). Each leading screen
  calls `.clearsFloatingTabBar(backdrop:)` with its own page colour: in the
  pane (`\.isUnfoldedPane`) content stops at a hard edge 16 pt above the bar,
  and a row marked `.keepsWholeAboveTabBar()` that would cross it is hidden
  whole (`TabBarClearance.edge`, tested). Mark every new row, card, section
  header and footer on a leading screen, or it is cut at the edge. A fade
  (attempt 2) and a hard scroll edge (attempt 1) both sliced rows and were
  rejected. `.compactChromeInPane()` gives Patterns and Settings an inline
  title and compact sections in the 669 pt pane. Folded, all of it is a no-op.
- The History pane has no bar, so it gets no clearance: its list runs to the
  screen edge as on a phone (a fade there cut the quiz card mid-glyph).
- Onboarding uses `.unfoldedLeadingPane`, with `OnboardingFoldPanel` in the
  trailing pane. Sheets (paywall, trial offer, details, edit) are still system
  form sheets centred on the inner display.
- History's heatmap always spans 90 days (`HeatmapData.padded`; days before the
  first log are outlined). Its cells are square `Grid` cells that share the
  card's width (`HeatmapLayout.weekColumns`); measuring the width instead let the
  card overflow its row in the History pane. Title, legend and caption live
  inside the card (a plain list footer drew a white band).
- Captures: `gh-sim all --device 'iPhone Duo' --scheme HeadacheLogger --wait 10
  --args "-uitesting -HeadacheScreenshotSeed -HeadacheProOverride
  -HeadacheScreenshotBrand"` plus one `--screen "-HeadacheDuoScreen <name>"`
  per surface: `log`, `history`, `patterns`, `pattern` (pushes the top
  pattern's detail) and `settings` (DEBUG, read once at launch). Never `--url`:
  iOS 27.1 raises an "Open in" alert for every openurl. The seed's first log is
  past the 90-day window, so History's counts hold across midnight.
