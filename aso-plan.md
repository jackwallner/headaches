# aso-plan.md — Headache Tracker ASO Metadata Update + Rollout Plan

> Written 2026-06-25 (SERP-corrected same day). App: **Headache Tracker - One Tap** (ID `6762074561`, repo `~/headaches`). Methodology: `~/Desktop/aso.md`.

---

## 0. TL;DR / Current decision

- **Positioning:** one-tap headache/migraine **log** with barometric pressure context — NOT a weather/barometer app, NOT general symptom diary, NOT Migraine Buddy.
- **Two lanes (don't conflate):**
  1. **One-tap log lane** (subtitle weight) — `one tap headache` SERP PASS, app **#2**
  2. **Baro/forecast lane** (keyword field only) — `headache forecast` PASS app **#8**; `barometric headache` PASS app **#8**
- **SERP FAIL — do not subtitle-weight:** `barometric forecast` (pure weather apps, not in top 50), `symptom diary` (Daylio/IBS journals), `weather migraine` (Yahoo Weather/WeatherBug), field word `pal` (blood-pressure apps)
- **US edit:** subtitle → `One Tap Migraine & Headache Log`; keywords drop `pal,buddy` → add `export,seconds` (~15% swap)
- **Astro:** cleaned 22 junk keywords; tagged `deployed`/`target`/`wall` with SERP notes on baro terms

---

## STEP 0 — Re-pull current state first

| What | How |
|---|---|
| Live metadata | `scripts/pull-appstore-metadata.sh` |
| Rankings/tags/notes | Astro `get_app_keywords(appId="6762074561", store="us")` |
| SERP guardrail | `search_app_store(keyword, store, appId="6762074561")` — **required before any subtitle change** |

---

## 1. SERP validation table (2026-06-25, non-negotiable)

| Term / combo | Rank | SERP top results | Guardrail |
|---|---|---|---|
| `one tap headache` | **#2** | One Tap Headache Diary, Migraine Buddy, MiG, Cranium | ✅ **Subtitle lane** |
| `headache forecast` | **#8** | Headache Forecast-Barometer, MigraineZen, Buddy, **you** | ✅ **Keyword field** (`forecast`) |
| `barometric headache` | **#8** | Buddy, Pressure Pal, BaroBuddy, **you** + some weather | ✅ **Keyword field** (`barometric`,`pressure`) |
| `headache tracker` | #21 | MiG, Buddy, small loggers | ⚠️ target — wall-adjacent |
| `barometric forecast` | not in 50 | Ventusky, Barometric Pressure Today, NOAA marine, Forecast Bar | ❌ **FAIL — never in subtitle** |
| `weather migraine` | not in 50 | WeatherBug 2M★, Yahoo Weather, generic weather | ❌ FAIL — do not add `weather` |
| `symptom diary` | not in 50 | Daylio, IBS food diary, general symptom trackers | ❌ FAIL — drop from subtitle |
| `pressure pal` (field `pal`) | #20 | Barometric Pressure Pal + **blood pressure** apps | ❌ FAIL — remove `pal` from field |
| `migraine diary` | not in top 15 | Migraine Buddy wall | 🚫 wall |

**Lesson:** barometric/forecast value is real but lives in **keyword-field combos** (`headache forecast`, `barometric headache`). Putting `Barometric Forecast` in the **subtitle** steers Apple toward the **weather/barometer SERP** — wrong product class.

---

## 2. Competitor tiers

| Tier | Apps |
|---|---|
| **WALL** | Migraine Buddy (40k★), Bearable, MiG — diary/tracker heads |
| **WINNABLE PEERS** | One Tap Headache Diary (0★), Cranium (149★), Headache Hero (17★), Relief (143★), BaroBuddy (40★) |
| **ADJACENT** | WeatherX, barometer utilities — share forecast terms, different core UX |

---

## 3. Exact US metadata change (SERP-validated, staged)

**Change to:**
- name: `Migraine Headache Tracker Log` *(unchanged)*
- subtitle → `One Tap Migraine & Headache Log`
- keywords → `simple,track,barometric,pressure,cluster,tension,trigger,pain,relief,forecast,chronic,aura,export,seconds`

| Edit | Rationale |
|---|---|
| Subtitle → one-tap log | Passes `one tap headache` SERP (#2). Replaces FAIL `symptom diary journal` intent |
| OUT `pal`, `buddy` | SERP homographs (blood pressure / Migraine Buddy) |
| IN `export`, `seconds` | Product-fit (fast log, doctor export); `seconds` supports one-tap speed story |
| KEEP `barometric`,`pressure`,`forecast` in **field only** | Combos already rank #8 — do not promote to subtitle |

100/100 chars · ~15% swap.

---

## 4. Astro state (done 2026-06-25, tag migration complete)

**US:** 84 keywords · **global:** ~599 (non-US pop-5 @ 1000 junk pruned 2026-06-25).

**Tagged (blue/green/gray only — legacy tags retired account-wide):**
| Tag | Examples |
|---|---|
| `deployed` | simple, track, barometric, pressure, forecast, cluster, tension, trigger, pain, chronic, aura, relief, export, seconds |
| `target` | one tap headache, headache forecast, barometric headache, headache tracker, pressure headache |
| `wall` | migraine buddy, migraine tracker, symptom diary, weather migraine, pressure pal |

**Notes on:** `barometric headache`, `headache forecast`, `pressure pal` — SERP evidence + field vs subtitle guidance.

---

## 5. Product-gated

`apple watch headache`, `migraine medication tracker`, `headache widget` (rank collapsed), doctor-export story weak.

---

## 6. Rollout

Next version + manual release. Re-pull ASC after upload. **Do not** ship subtitle with `barometric` or `forecast` — validated FAIL.
