---
paths:
  - "HeadacheLogger/**"
  - "HeadacheLoggerWidget/**"
  - "HeadacheLoggerWatch/**"
  - "SharedHeadache/**"
  - "HeadacheLoggerTests/**"
  - "Tools/Localization/**"
---

# In-app localization

The app, widget, Watch companion, and App Intent ship in English plus de, ja,
es, it, pl, hu, fi, nb, da, ru, pt-PT, uk, and fr. The target list reflects
markets with recent customers.

## Setup
- `SharedHeadache/Localizable.xcstrings` is compiled by the app, widget, and
  Watch targets because each includes `SharedHeadache/` in `project.yml`.
- `HeadacheLogger/InfoPlist.xcstrings` localizes the Health, location, and
  motion permission explanations. Keep brand names unchanged.
- Keep `CFBundleLocalizations` aligned in the app, widget, and Watch Info.plists.
  XcodeGen 2.39 or later reads the shared catalog locales into `knownRegions`.
- Run `python3 Tools/Localization/check.py` from the repository root. It checks
  Swift literals, both catalogs, target-language coverage, plural categories,
  and format placeholders without Xcode.
- `HeadacheLoggerTests/LocalizationTests.swift` checks that every locale ships
  and verifies Russian one, few, and many forms.
- `-HeadacheWidgetSnapshot` renders the widget's shared visual label in a
  small widget-sized screenshot surface for headless locale review.

## Adding or changing copy
- SwiftUI literals and `String(localized:)` use complete sentences or complete
  labels. Do not join translated fragments or build translated sentences with
  string concatenation.
- Use plural variations for count sentences. Russian, Ukrainian, and Polish need
  one, few, many, and other forms. Review the catalog substitution count and
  translated forms together.
- Stored English weather, weekday, quiz, and status values stay stable in
  persistence. Translate them only for display with
  `HeadacheTemperatureFormatting.localizedStoredText(_:)`.
- Do not use `.capitalized` or `.lowercased()` on translated text. Use
  `formatted()` or localized Foundation formatters for dates, numbers, units,
  and durations.
- Prices come from StoreKit. Trial duration comes from the subscription's
  StoreKit period and `DateComponentsFormatter`, never from parsing a label.
- Keep pattern and forecast copy descriptive. It may describe what appears in
  logged data, but must not claim that a signal caused, treats, prevents, or
  diagnoses a headache. Keep medical disclaimers complete.
- Keep product names, storage keys, analytics identifiers, RevenueCat IDs, and
  CSV column names stable. CSV prose comments may be localized.

## Proving a change
- Run `python3 Tools/Localization/check.py` before a build that changes copy.
- Run the iOS test suite with `gh-sim test` and capture localized app, paywall,
  and widget screens with `gh-sim all` or `gh-sim launch` as described in the
  project run instructions. Inspect all localized screenshots for clipping,
  English leftovers, and RTL directionality.
