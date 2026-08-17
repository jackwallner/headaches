# aso-plan.md — HeadacheLogger ASO positioning + metadata

> Rewritten 2026-08-16. App ID `6762074561`, repo `~/headaches`.
> Supersedes the 2026-06-25 plan, whose subtitle recommendation never shipped.
> Methodology: `~/Desktop/aso.md`.

---

## 0. Current decision (2026-08-16)

**Positioning:** the migraine log that fills itself in. One tap, then Watch,
HealthKit and weather attach the context automatically, then the app tells you
which triggers are yours. Every competitor above us is a manual diary.

**Staged in `fastlane/metadata/en-US`, not yet submitted:**

| Field | Value | Chars |
|---|---|---|
| name | `Migraine Tracker: Headache Log` | 30/30 |
| subtitle | `One Tap Diary & Trigger Alerts` | 30/30 |
| keywords | `barometric,pressure,forecast,weather,tension,cluster,chronic,aura,pain,sinus,daily,nausea,symptom` | 97/100 |

**Was live before this change:** name `Migraine Headache Tracker Log`, subtitle
`Barometric Pressure Forecast` (a verbatim copy of Pressure Pal's subtitle),
keywords `one,tap,diary,aura,cluster,tension,trigger,pain,relief,simple,track,weather,journal,pal,episode`.

---

## 1. The volume reality (Astro US, 2026-08-16)

| Term | Popularity | Our rank |
|---|---|---|
| `migraine tracker` | **44–47** | #37 |
| `one tap` (generic) | 29 | #243 |
| `headache tracker` | 9 | #11 |
| `migraine` / `headache` | 6–7 | #26 / #34 |
| `one tap headache`, `one tap migraine`, `tap migraine` | **5 (floor)** | **#1–#2** |
| `apple watch headache`, `headache widget`, `headache export` | 5 (floor) | #2, #164, #27 |

`migraine tracker` is the only term in this category with real demand. We were
#37, and all top 12 results carry the literal string "Migraine Tracker" in the
app name. That is what the name change buys.

The one-tap cluster is fully owned and worth nothing: popularity 5 is the floor,
and 7 days of it produced 2,048 search impressions and 13 first-time downloads.

---

## 2. Method: the literal-word SERP test

For any candidate keyword, pull the SERP and ask **do small apps rank here on the
literal word, or do generic headache trackers rank without it?** Under 2026
semantic matching, synonym nouns collapse into one cluster and the word is waste.

| Candidate | Verdict | Evidence (2026-08-16 SERP) |
|---|---|---|
| `daily` | ✅ **IN** | `daily headache log`: #1 and #2 are tiny apps (1 and 3 ratings) named "…Daily Log", beating Cranium (157★) on the literal word |
| `hormonal` | ❌ OUT | `hormonal headache`: 8/8 are generic headache trackers, none carry the word. Slot is already served without paying 8 chars |
| `journal` | ❌ OUT | `headache journal`: top 8 (Buddy, MiG, Cranium…) carry "journal" nowhere. Collapses into `diary` |
| `attack` | ❌ OUT | `migraine attack tracker`: only 1 of 8 uses the word |
| `sinus` | ⚠️ weak IN | `sinus headache`: only Migraine Weather Forecast (#5) carries it. Cheap at 5 chars, legitimate subtype |
| `severity` | ❌ OUT | Attribute word, not a query. Nobody searches it |
| `vestibular` | ❌ OUT | Passes the test (4 of 8 carry it, small apps rank) but we do not track vertigo. Intent mismatch |
| `watch`, `widget`, `export`, `sleep` | ❌ OUT | See §3 |

---

## 3. Why no watch/widget/export in the field

We rank **#2 for `apple watch headache` with no watch word in any field** — the
old live metadata had no "watch", "widget" or "export" anywhere. Those ranks come
from actually shipping a watchOS target and widgets, not from metadata. Buying
them would cost 12 chars (`apple` + `watch`) for a position already held free.

The `apple watch headache` SERP is also contaminated: Apple's own Watch app at #3,
Chronix Watch Dials #6, Watch Faces Gallery #8. Apple has not resolved that query
to health tracking, and popularity 5 says almost nobody types it.

**Those words belong in screenshot captions**, where they are the strongest
conversion argument and feed Apple's AI tag layer (tags are Apple-documented and
editable in ASC; screenshot OCR into search is vendor-claimed, not confirmed).

---

## 4. Known cost of this change

`barometric`, `pressure` and `forecast` move from the **subtitle** (high weight)
to the **keyword field** (lower weight). Expect `barometric headache` (#7),
`pressure headache` (#8) and `headache forecast` (#16) to soften. That is
deliberate: those are all popularity 5 versus `migraine tracker` at 44.

Expect 2–4 weeks of rank turbulence after any name change. Do not change anything
else in that window or the signal is unreadable.

---

## 5. Competitor tiers

| Tier | Apps |
|---|---|
| **WALL** | Migraine Buddy (41k★), MiG (2.7k★), Bearable (6.1k★) |
| **BARO LANE INCUMBENT** | Pressure Pal (687★) — owns `Barometric Pressure Forecast` as a subtitle |
| **WINNABLE PEERS** | Relief AI (25★), Migraine Trail (43★), Migsy (47★), Migraine Insight (458★), Headache Hero (21★) |
| **NEW ENTRANTS ON OUR CLAIM** | One Tap Headache Diary (0★), ebb "One tap when it starts" (1★), Migraine Tap (0★) |

One tap is no longer a differentiator on its own. Automatic capture is.

---

## 6. Screenshot captions (indexed-adjacent, conversion-critical)

1. "Log a migraine in one tap"
2. "Your Watch and the weather fill in the rest"
3. "Sleep, HRV and barometric pressure, attached automatically"
4. "It tells you which triggers are yours"
5. "Export a clean CSV for your neurologist"

Screens 1 and 2 are the only ones visible in search results. The one-tap claim and
the auto-capture claim have to be those two.

---

## 7. Open items

- Conversion is the real bottleneck: 2,048 impressions → 13 installs.
- Consider moving primary category Medical → Health & Fitness, where nearly the
  entire `migraine tracker` top 12 sits. Test **after** the metadata change lands.
- `sinus` and `nausea` are the weakest field slots. First candidates to swap if
  the next Astro pull shows no movement.
