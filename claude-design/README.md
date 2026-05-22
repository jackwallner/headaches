# Claude Design — One Tap Headache Tracker App Store Preview Package

Self-contained handoff for generating App Store preview frames. Everything Claude Design needs to produce the 5 marketing frames lives in this folder.

## Start here

1. Read [`BRIEF.md`](./BRIEF.md) — the primary spec. Covers product, brand tokens, frame-by-frame headlines, output specs, and constraints.
2. Skim [`reference/design-system.md`](./reference/design-system.md) for color/type tokens and component patterns if a brand question comes up.
3. Use the JPEGs in [`screenshots/`](./screenshots/) as the literal source pixels for each device frame — crop only, do not retouch interior content.

## Folder layout

```
claude-design/
├── README.md                              ← you are here
├── BRIEF.md                               ← primary spec; read first
├── screenshots/                           ← raw simulator captures
│   ├── raw_01_log.jpeg                    ← One Tap home (Frame 1)
│   ├── raw_02_history.jpeg                ← History + CSV export (Frame 2)
│   ├── raw_03_patterns.jpeg               ← Pattern detection (Frame 3)
│   ├── raw_04_alerts.jpeg                 ← Proactive Alerts (Frame 4)
│   └── raw_05_dark.png                    ← Dark mode (Frame 5)
└── reference/
    ├── design-system.md                   ← in-app design system spec
    └── product-description.md             ← App Store copy for tone calibration
```

## Deliverables expected back

- 5 PNGs at **1290 × 2796** named `appstore_preview_<NN>_<slug>.png`
- 1 contact-sheet composite at 25% scale for quick review
- Drop into `/Users/jackwallner/headaches/fastlane/screenshots/en-US/` (Fastlane uploads from here)

## Hard constraints (BRIEF has the full list)

- No medical claims ("cure", "diagnose", "treatment")
- One red emphasis phrase per headline, max — `#F2405C`
- No Apple Health / HealthKit / Apple Watch logos in the marketing chrome
- Don't touch pixels inside the screenshot — crop only
- Don't normalize status-bar times — leave 9:53/9:54/9:55 as captured
