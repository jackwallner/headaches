---
paths:
  - "artifacts/asc-screenshots/**"
  - "fastlane/screenshots/**"
---

# Localized store sets

- Recapture with `artifacts/asc-screenshots/l10n-20261105/tools/capture.sh`. It runs one `gh-sim` UI test for English and every target locale, then sorts attachments into the kit's raw tree.
- Use `capture.sh --history-only [locale ...]` to refresh frames 02, 03 and 06 after History changes. History row accessibility identifiers can propagate to child buttons in SwiftUI, so keep action identifiers on the controls themselves.
- Review the locale sheets under `artifacts/asc-screenshots/l10n-20261105/sheets/`, run the locale gate, and copy only root-level PNGs into the target `fastlane/screenshots/<locale>/` folder.
- The app's DEBUG seed supplies stable log data. XCUITest opens History, scrolls to an entry, opens the export menu, and presents the event editor. Spanish screenshots use Celsius and localized seed notes and weather.
- These phone frames have a continuous bezel. If raw-image matching fails after the live app screen changes, locate the phone with `locate.py --bezel --radius`; it produced consistent geometry across all seven frames.
