# One Tap Headache Tracker — App Store Preview Frames

> **Audience:** Claude Design
> **Deliverable:** 5 marketing preview frames sized for the App Store iPhone 6.9" slot (**1290 × 2796**), each combining (a) one of the supplied raw screenshots inside an iPhone device frame, (b) a short headline + sub-copy band, and (c) brand-consistent background art.
> **Source screenshots:** `./screenshots/raw_*.jpeg` (iPhone 17 Pro captures, 1203 × 2614, except raw_05_dark which is a smaller capture — see §6).

---

## 1. Product One-Liner

**One Tap Headache Tracker** is a local-first iPhone + Apple Watch headache logger. The user taps once, and the app silently captures 50+ data points from Apple Health, local weather, and air quality — no forms, no typing. Over time it surfaces personal patterns (pressure, exertion, temperature, AQI) and can proactively warn before risky weather.

Audience: people with frequent headaches or migraines who want to find their triggers without the friction of typing into a journal app. They have an iPhone, often an Apple Watch, and want their data to stay on-device.

Tone: **direct, warm, confident.** Not clinical, not playful. Headlines are short and declarative. No emojis. No hype words like "revolutionary" or "AI-powered."

---

## 2. Brand Visual System

The app is **red-forward on system gray**. Carry that into the marketing frames — these are an extension of the in-app design system, not a separate marketing universe.

### 2.1 Color tokens (use exactly)

| Token | Hex | Usage in frames |
|---|---|---|
| `brand` | `#F2405C` | Primary accent — emphasis word, callouts, Pro pill |
| `brandGradientStart` | `#F2405C` | Top-leading of any brand gradient |
| `brandGradientEnd` | `#DB296E` | Bottom-trailing of any brand gradient |
| `brandDark` | `#591F29` | Deep burgundy — optional dark band background |
| `ink` | `#0B1220` | Primary text on light surfaces |
| `inkOnDark` | `#FFFFFF` | Primary text on brand / brandDark bands |
| `inkSecondary` | `#5B6470` | Sub-copy, metadata on light bands |
| `canvas` | `#F2F2F7` | Light system-gray background behind the device frame |
| `surface` | `#FFFFFF` | Card / sheet white |

**No other accent colors.** Do not introduce blue, green, teal, or purple in the marketing chrome. (The screenshots themselves contain semantic colors — yellow/orange/red severity, teal/indigo/mint metric chips — leave those untouched inside the device frame.)

No gradients beyond the brand red→pink gradient, optionally used on the headline band. No drop shadows beyond a single soft device shadow.

### 2.2 Type

- **Headline:** SF Pro Rounded, Heavy, 72–88pt at 1290px width. Letterspacing −0.5. Two lines max, hard line breaks deliberate.
- **Sub-copy:** SF Pro, Semibold, 32–36pt. One line where possible, two max.
- One **red emphasis word/phrase** per headline. Never two. On dark bands the emphasis sits in white and the rest of the headline goes to a lighter weight — same rule, inverted.

### 2.3 Layout grid

Two stacked bands per frame:

```
┌─────────────────────────┐
│  COPY BAND (top ~24%)   │  ← headline + sub-copy
│  Headline goes here     │
│  Optional sub-copy line │
├─────────────────────────┤
│                         │
│   DEVICE FRAME          │  ← screenshot inside a clean
│   (centered, ~74% h)    │     iPhone 15/16/17 Pro shell,
│                         │     soft 8–12px shadow, no glare
│                         │
└─────────────────────────┘
```

Mix two band styles across the set so the row doesn't feel monotonous:
- **Light band:** `canvas` background, `ink` headline, `brand` emphasis word.
- **Brand band:** `brand` (or brand gradient) background, `inkOnDark` headline, white emphasis stays white with the rest at ~70% opacity — or use `brandDark` (`#591F29`) for one frame to give the set a darker beat.

Device frame: black iPhone 17 Pro shell, Dynamic Island as-is, no hand mockups, no stadium/lifestyle backgrounds. The status bar already shows clock/signal/wifi/battery — do not overpaint it. (Frames 1–4 show 9:53 / 9:54 — that's fine. Don't normalize to 9:41.)

---

## 3. Frame-by-Frame Brief

All 5 frames are mandatory. Order matters — frame 1 is the App Store hero.

### Frame 1 — The Hero / One-Tap Log
- **Asset:** `raw_01_log.jpeg` (One Tap tab with hero "Log Headache" card, Latest Event card, milestone prompt)
- **Headline:** `Log a headache.` / `In one tap.`
- **Sub-copy:** `Health, weather, and air quality — captured automatically.`
- **Emphasis:** `In one tap.` in `brand` red.
- **Layout:** Light band on top (`canvas` background).

### Frame 2 — History & CSV Export
- **Asset:** `raw_02_history.jpeg` (History tab — totals, "Most common day: Friday", Export CSV / Import CSV cards)
- **Headline:** `Your history.` / `Doctor-ready.`
- **Sub-copy:** `Export every entry as CSV. Share it in seconds.`
- **Emphasis:** `Doctor-ready.` in `brand` red.
- **Layout:** Light band on top.

### Frame 3 — Pattern Detection
- **Asset:** `raw_03_patterns.jpeg` (Patterns tab — "12 headaches logged", Exertion-linked 100%, Steady pressure 58%, Temperature cluster)
- **Headline:** `Find what's` / `triggering them.`
- **Sub-copy:** `Personal patterns from pressure, exertion, temperature, and air.`
- **Emphasis:** `triggering them.` in `brand` red.
- **Layout:** Brand band on **bottom** so the dense pattern list reads first. This is the data-density frame.

### Frame 4 — Proactive Forecast Alerts
- **Asset:** `raw_04_alerts.jpeg` (Proactive Alerts settings — Notifications, Forecast location, Pressure/AQ signal learning)
- **Headline:** `Get ahead of` / `the next one.`
- **Sub-copy:** `Quiet forecast alerts when pressure or air quality turn risky.`
- **Emphasis:** `the next one.` in `brand` red.
- **Layout:** Light band on top.

### Frame 5 — Dark Mode
- **Asset:** `raw_05_dark.jpeg` (One Tap tab in dark mode — same hero card, dark canvas)
- **Headline:** `Dark mode,` / `same one tap.`
- **Sub-copy:** `Built for late nights and migraine-friendly viewing.`
- **Emphasis:** `same one tap.` in `brand` red.
- **Layout:** Use the **`brandDark` (`#591F29`)** band on top — this is the one darker beat in the set. Headline white, emphasis stays white but with a thin red underline accent (1.5pt) under the emphasis phrase only.

---

## 4. Hard Constraints

- ❌ **Do not retouch pixels inside the screenshot.** Crop only — every number, every label, every chip stays exactly as captured.
- ❌ No emojis, sparkles, motion lines, "WOW" effects, or sportsbook/promo styling.
- ❌ No medical claims. Do not write "cure," "diagnose," "treatment," "FDA," or "clinically proven." The app helps users *track and find patterns* — that's it.
- ❌ No competitor names (Migraine Buddy, N1-Headache, etc.).
- ❌ No Apple Health, HealthKit, or Apple Watch wordmarks/logos in the marketing chrome. The app uses these — the App Store frame doesn't need to badge them.
- ❌ No fake/marketing UI. Every pixel inside the device frame must come from the supplied screenshot.
- ❌ No more than one red emphasis phrase per headline.
- ❌ No "Available on the App Store" badge — App Store places that itself.
- ✅ One red emphasis phrase per headline.
- ✅ All shapes use continuous-rounded corners. Device frame shadow is soft, single, ≤12px blur, ≤30% opacity.

---

## 5. Output Specifications

- **Dimensions:** 1290 × 2796 px, PNG, sRGB.
- **Device shell:** iPhone 15/16/17 Pro (black titanium). One soft shadow, no glow.
- **Filename convention:** `appstore_preview_<NN>_<slug>.png`
  - `appstore_preview_01_one_tap.png`
  - `appstore_preview_02_history.png`
  - `appstore_preview_03_patterns.png`
  - `appstore_preview_04_alerts.png`
  - `appstore_preview_05_dark.png`
- **Safe zone:** Keep all headline text ≥ 64px from any edge.
- **Export location:** `/Users/jackwallner/headaches/fastlane/screenshots/en-US/` (Fastlane will pick these up for App Store metadata upload).
- **Also provide:** one composite contact-sheet PNG showing all 5 frames at 25% scale for quick review.

---

## 6. Asset notes & gotchas

- `raw_01..04` are **1203 × 2614** JPEGs (iPhone 17 Pro captures). Upscale modestly to fit the device frame; do not stretch.
- `raw_05_dark.png` is **1320 × 2868** — full-resolution capture of the same One Tap screen in dark mode.
- The "9:53" / "9:54" / "9:55" status-bar times across frames are fine — leave them alone. Don't normalize to 9:41.
- The Latest Event card in raw_01 says "Vancouver, WA · Rain, 55°F" — that's real demo data, keep it visible.
- The milestone card in raw_01 ("5 headaches logged — enough for patterns") is intentional product UI, not test content. Keep it visible.

---

## 7. Reference files

| File | What it is |
|---|---|
| `reference/design-system.md` | Full in-app design system spec — palette, type, components |
| `reference/product-description.md` | App Store description and subtitle for tone calibration |
| `screenshots/raw_*.jpeg` | Source captures for each frame |
