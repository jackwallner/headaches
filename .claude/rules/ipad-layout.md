---
paths:
  - "HeadacheLogger/Utilities/PadLayout.swift"
  - "HeadacheLogger/Utilities/UnfoldedSplit.swift"
  - "HeadacheLogger/Views/RootTabView.swift"
  - "HeadacheLogger/Views/OnboardingView.swift"
  - "HeadacheLogger/Views/PaywallView.swift"
  - "HeadacheLoggerUITests/IPadLayoutUITests.swift"
  - "project.yml"
---

# Migraine Headache Tracker: iPad layout (2026-11-12)

- Free, native: `TARGETED_DEVICE_FAMILY "1,2"` on the app and the widget (the
  watch is untouched), all four orientations via
  `UISupportedInterfaceOrientations~ipad`. Once a version ships with iPad
  support it can never be removed, so keep every screen at App Review quality.
- The iPhone Duo split (`UnfoldedSplit`) is phone only: an iPad is regular width
  too, and `UnfoldedSplit.isRegularPhone` keeps it out. iPad uses the system top
  tab bar and one screen at a time.
- Width: `padReadableColumn(maxWidth:maxHeight:)` (`PadLayout.swift`) caps a
  screen at 680 pt centred, on iPad at regular width only, with the page colour
  filling the sides. It wraps each tab's `NavigationStack` in `RootTabView`, so
  the large title, toolbar items and any pushed screen share the column. Never
  put it inside a `List`. Onboarding uses 560 pt wide and 720 pt tall so a page
  sits centred instead of leaving a void between the text and the button. A
  compact iPad window (Split View at a third) and every iPhone fall through
  untouched.
- Sheets: `padFormSheet()` sets `presentationSizing(.form)` so the paywall, trial
  offer, intro, quiz, notes and edit sheets are form-sized cards, not full-width
  slabs. The paywall also caps itself at 560 pt for the full-screen cover in
  onboarding. Add it to any new sheet. The trial offer's `.presentationDetents`
  is ignored on iPad.
- No extra labels or helper text to fill iPad space. If a screen looks empty,
  fix the layout.
- Proof: `IPadLayoutUITests` captures every main screen, onboarding and both
  paywalls in portrait and landscape (`gh-sim test --device "iPad Pro 13-inch
  (M5)" --only HeadacheLoggerUITests/IPadLayoutUITests`, or a local iPad on
  `agent-sim checkout headaches --slot 6`). It uses `XCUIScreen.main`: the
  window screenshot of a landscape iPad comes back rotated and cropped.
