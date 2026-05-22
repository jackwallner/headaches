---
version: alpha
name: One Tap Headache Tracker
description: Bold red accent on system gray backgrounds. Direct, high-contrast, and warm — a health tracker that feels active, not sterile.
colors:
  brand: "#F2405C"
  brandGradientStart: "#F2405C"
  brandGradientEnd: "#DB296E"
  brandDark: "#591F29"
  severitySlight: "#EAB308"
  severityMedium: "#F97316"
  severityExtreme: "#EF4444"
  statusComplete: "#22C55E"
  statusPartial: "#F97316"
  statusFailed: "#EF4444"
  statusPending: "#3B82F6"
  summaryPink: "#EC4899"
  summaryOrange: "#F97316"
  summaryPurple: "#A855F7"
  summaryBlue: "#3B82F6"
  metricTeal: "#14B8A6"
  metricIndigo: "#6366F1"
  metricMint: "#22D3EE"
typography:
  display:
    fontFamily: SF Pro Display
    fontSize: 34pt
    fontWeight: 700
  heroNumber:
    fontFamily: SF Pro Display
    fontSize: 56pt
    fontWeight: 700
  buttonIcon:
    fontFamily: SF Pro Display
    fontSize: 36pt
    fontWeight: 700
  h1:
    fontFamily: SF Pro Display
    fontSize: 22pt
    fontWeight: 700
  h2:
    fontFamily: SF Pro Display
    fontSize: 20pt
    fontWeight: 700
  h3:
    fontFamily: SF Pro Text
    fontSize: 17pt
    fontWeight: 600
  body:
    fontFamily: SF Pro Text
    fontSize: 17pt
    lineHeight: 1.5
  bodySemibold:
    fontFamily: SF Pro Text
    fontSize: 17pt
    fontWeight: 600
  subheadline:
    fontFamily: SF Pro Text
    fontSize: 15pt
  subheadlineSemibold:
    fontFamily: SF Pro Text
    fontSize: 15pt
    fontWeight: 600
  callout:
    fontFamily: SF Pro Text
    fontSize: 16pt
  footnote:
    fontFamily: SF Pro Text
    fontSize: 13pt
  caption:
    fontFamily: SF Pro Text
    fontSize: 12pt
  captionSemibold:
    fontFamily: SF Pro Text
    fontSize: 12pt
    fontWeight: 600
  caption2:
    fontFamily: SF Pro Text
    fontSize: 11pt
  caption2Semibold:
    fontFamily: SF Pro Text
    fontSize: 11pt
    fontWeight: 600
  monoValue:
    fontFamily: SF Pro Text
    fontSize: 17pt
    fontWeight: 600
    fontDesign: monospaced
  monoCaption:
    fontFamily: SF Pro Text
    fontSize: 11pt
    fontDesign: monospaced
rounded:
  chartBar: 4px
  pill: 8px
  dataPill: 12px
  brandButton: 14px
  metricChip: 14px
  chip: 14px
  card: 18px
  largeCard: 22px
  mainButton: 28px
  style: continuous
spacing:
  xs: 4px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 20px
  xxl: 24px
  xxxl: 32px
components:
  mainButton:
    gradient:
      - "{colors.brandGradientStart}"
      - "{colors.brandGradientEnd}"
    gradientDirection: topLeading → bottomTrailing
    textColor: white
    font: title2.bold
    rounded: "{rounded.mainButton}"
    style: continuous
    shadow: heavy
  statusBadge:
    textColor: "{semanticColor}"
    font: captionSemibold
    padding: 6px 10px
    background: "{semanticColor}.opacity(0.12)"
    rounded: Capsule
  metricChip:
    titleColor: secondary
    titleFont: caption2Semibold
    valueColor: "{tint}"
    valueFont: monoValue
    spacing: 4px
    padding: 10px 12px
    background: "{tint}.opacity(0.10)"
    rounded: "{rounded.metricChip}"
    style: continuous
  dataPill:
    titleColor: secondary
    titleFont: caption2
    valueFont: monoValue
    spacing: 2px
    padding: 8px 10px
    background: tertiarySystemGroupedBackground
    rounded: "{rounded.dataPill}"
    style: continuous
  summaryCard:
    titleColor: secondary
    titleFont: caption
    valueColor: "{tint}"
    valueFont: h2
    spacing: 6px
    padding: "{spacing.lg}"
    background: secondarySystemGroupedBackground
    rounded: "{rounded.card}"
    style: continuous
  insightRow:
    padding: 14px
    iconFont: 22pt semibold
    titleFont: bodySemibold
    subtitleFont: caption
  proactiveAlertsCard:
    padding: 14px
    background: brand.opacity(0.08)
    border: brand.opacity(0.25), 1px
    rounded: "{rounded.brandButton}"
  planCard:
    padding: 14px
    rounded: "{rounded.brandButton}"
    border: secondary.opacity(0.3), 1px
    borderSelected: brand, 2px
  captureBanner:
    padding: 16px
    rounded: 16px
  captureRecoveryCard:
    padding: "{spacing.lg}"
    background: orange.opacity(0.10)
    border: orange.opacity(0.35), 1px
    rounded: "{rounded.card}"
    style: continuous
  severityIndicator:
    slight:
      color: "{colors.severitySlight}"
      font: captionSemibold
    medium:
      color: "{colors.severityMedium}"
      font: captionSemibold
    extreme:
      color: "{colors.severityExtreme}"
      font: captionSemibold
  proBadge:
    text: Pro
    textColor: "{colors.brand}"
    font: caption.bold
    padding: 4px 8px
    background: brand.opacity(0.15)
    rounded: Capsule
---
## Overview

Red-forward and direct. The brand accent (`#F2405C`) drives every interaction — the main log button, tab bar, Pro badges, and paywall. System gray backgrounds keep the canvas quiet so the red pops. Severity uses yellow/orange/red semantic colors. Everything is `.continuous` rounded, generous but never soft.

## Colors

The palette has three layers: brand, semantic status, and decorative tints.

**Brand**
- **Red (`#F2405C`):** The only accent. Tab bar, main button, Pro markers, paywall CTAs. No other accent colors compete with it.
- **Gradient (`#F2405C` → `#DB296E`):** Used on the main headache log button. Top-leading to bottom-trailing.
- **Dark (`#591F29`):** Widget container background — a deep burgundy that anchors the home screen.

**Status (Semantic)**
- **Slight (`#EAB308`):** Low-severity headaches.
- **Medium (`#F97316`):** Medium-severity headaches, partial captures, recovery warnings.
- **Extreme (`#EF4444`):** High-severity headaches, failed captures.
- **Complete (`#22C55E`):** Successful logs, confirmed states.
- **Pending (`#3B82F6`):** Environment-only captures.

**Decorative Tints**
- Summary cards: pink, orange, purple, blue — assigned per metric for visual distinction.
- Metric chips: teal (steps), indigo (sleep), mint (AQI) — fixed per data type.

## Typography

All system SF Pro. No custom fonts. Monospaced digits for numeric values (steps, sleep hours, AQI) to keep numbers aligned in cards and chips. Point sizes are the native iOS dynamic type scale.

- **display:** 34pt bold — onboarding headlines.
- **heroNumber:** 56pt bold — insights teaser icon, quiz completion checkmark.
- **buttonIcon:** 36pt bold — main headache button SF Symbol.
- **h1:** 22pt bold (`.title2`) — section headers.
- **h2:** 20pt bold (`.title3`) — quiz questions, summary card values.
- **h3:** 17pt semibold (`.headline`) — card titles, button text.
- **body:** 17pt regular — quiz options, onboarding body.
- **subheadline:** 15pt — status text, weather summaries.
- **callout:** 16pt — paywall descriptions, insight sections.
- **footnote:** 13pt — secondary descriptions, legal text.
- **caption:** 12pt — metadata, chart annotations.
- **caption2:** 11pt — metric chip titles, watch status.
- **monoValue:** 17pt semibold monospaced — metric values.
- **monoCapiton:** 11pt monospaced — watch relative time.

## Corner Radii

Every shape uses `.continuous` style. Radii form an intentional progression:

- **4px:** Chart bar marks.
- **8px:** Pills and badges (Capsule).
- **12px:** Data pills.
- **14px:** Brand buttons, metric chips, proactive alerts card, plan cards.
- **16px:** Capture banners.
- **18px:** Cards — event rows, summary cards, recovery cards.
- **22px:** Large cards — latest event card.
- **28px:** The main headache log button.

## Opacity Scale

Consistent opacity usage across the app for backgrounds, borders, and overlays:

- **0.08:** Subtle filled backgrounds (proactive alerts card).
- **0.10:** Metric chip backgrounds, recovery card backgrounds.
- **0.12:** Status badge backgrounds.
- **0.15:** Pro badge backgrounds.
- **0.18:** Green "On" status badges.
- **0.25:** Stroke borders (proactive alerts card, plan cards deselected).
- **0.35:** Warning stroke borders (recovery card).

## Icons

SF Symbols exclusively. The primary icon is `brain.head.profile` — used on the main tab, the log button, and onboarding. Other key symbols:

- `clock.arrow.circlepath` — History
- `chart.bar.xaxis` — Patterns / Insights
- `slider.horizontal.3` — Settings
- `bell.badge.fill` / `bell.slash.fill` — Proactive alerts on/off
- `checkmark.circle.fill` — Confirmation states
- `bolt.heart.fill` — Widget default

## Do's and Don'ts

- **Do** use `#F2405C` for every interactive accent. It's the only brand color.
- **Do** use the severity color mapping consistently: yellow → slight, orange → medium, red → extreme.
- **Do** use `.continuous` on every `RoundedRectangle`.
- **Do** use monospaced digits for all numeric values in cards and chips.
- **Don't** introduce any blue as a brand accent. The app is red.
- **Don't** use sharp corners. Minimum radius is 4px (chart bars only).
- **Don't** add custom fonts — SF Pro only.
- **Don't** use `Color.accentColor` directly — always use the explicit `Color(red: 0.95, green: 0.25, blue: 0.36)` value until tokenized.
