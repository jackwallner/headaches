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
- Unfolded, the system draws the tab bar as a floating bottom bar across the
  leading pane (folded it is the vertical bar), so the tabs get a hard bottom
  scroll edge (`unfoldedBarEdge`) to stop list rows reading through it.
- Onboarding uses `.unfoldedLeadingPane`, with `OnboardingFoldPanel` in the
  trailing pane. Sheets (paywall, trial offer, details, edit) are still system
  form sheets centred on the inner display.
- Captures: `gh-sim all --device 'iPhone Duo' --scheme HeadacheLogger --wait 10
  --record-seconds 120 --args "-uitesting -HeadacheScreenshotSeed
  -HeadacheProOverride -HeadacheScreenshotBrand -HeadacheDuoTour"` plus
  `--url noop://1` through `noop://9`. The noop URLs fail fast and only pace
  shots (`simctl openurl` to a real scheme raises an alert on iOS 27).
  `-HeadacheDuoTour` (DEBUG) moves one stop every 22 s from launch, since
  gh-sim relaunches after unfolding: folded History, Patterns, the top
  pattern's detail, Settings; unfolded Patterns, the detail, Settings, then
  back to One Tap. `HEADACHEDUOTOUR` lines in app.log map shots to stops.
