# ASC metadata proposal — Headache Tracker (en-US)

Apple limits (no spaces after commas in keyword field):

| Field | Limit | Current len |
|-------|-------|-------------|
| Name | **30** | 26 |
| Subtitle | **30** | 28 |
| Keywords | **100** | 100 |

---

## Keywords (100 chars) — verified fit

**Current** (100/100) — no `headache` or `migraine`:

```
health,journal,export,doctor,symptom,head,episode,trigger,diary,cluster,tension,chronic,pain,pattern
```

**Recommended** (98/100):

```
headache,migraine,tracker,watch,widget,diary,pain,cluster,export,trigger,health,doctor,symptom,log
```

Dropped from field (still track in Astro): `head`, `episode`, `journal`, `tension`, `chronic`, `pattern`.

**Do not use** `docs/app-store-metadata.md` draft keywords — that string is **119 chars** and will be rejected/truncated:

```
headache,migraine,tracker,log,journal,diary,weather,barometric,pressure,trigger,doctor,export,csv,watch,health,symptoms
```

Optional swap if you want `aura` (must drop 5+ chars elsewhere):

```
headache,migraine,tracker,watch,widget,diary,pain,cluster,trigger,export,health,doctor,symptom,log
```

(98 chars — drop `export` or merge `symptom`→`symptoms` only if you recalc; `symptoms` is +1 char.)

---

## Name (30 chars) — keep

**Keep:** `Headache Tracker - One Tap` (26/30)

- Astro **#1** on `headache tracker one tap`
- Changing name risks that exact-match rank
- Only 4 chars spare — not enough to add `Migraine` without dropping `One Tap`

**Do not switch to** `One Tap Headache Tracker` (24) unless you A/B test — same words, weaker match to current #1 phrase.

---

## Subtitle (30 chars) — optimize

**Current:** `Simple migraine and pain log` (28/30) — Astro **#30** on that exact phrase.

| Option | Len | Pros | Cons |
|--------|-----|------|------|
| *Keep current* | 28 | Defends #30 rank | Misses competitor “diary” / “track” patterns |
| `Headaches & Migraines Diary` | 27 | Aligns with **#90** `headaches and migraines diary`; competitor subtitles | Loses “simple” / “pain log” indexing |
| `Track Headache Pain & Triggers` | 30 | Uses full limit; `track headache`, `triggers` | New phrase — no rank history yet |
| `Migraine & Headache Diary Log` | 29 | Diary + both condition words | Long; partial overlap with name |

**Recommendation:** If you change subtitle, use **`Headaches & Migraines Diary`** (27) — best match to competitor SERP and existing Astro push-tier rank. Wait 14 days and compare rank on both old and new phrases in Astro before reverting.

---

## What we optimized so far

| Field | Astro tracking | ASC file updated |
|-------|----------------|------------------|
| Keywords | Yes (71 terms, tiers) | Proposed below in `fastlane/metadata` |
| Name | Tracked, ranked #1 | **No change** (intentional) |
| Subtitle | Tracked, ranked #30 | **Your call** — proposal above |

After you approve subtitle choice, run:

```bash
ASC_APP_VERSION=1.3.0 ./scripts/pull-appstore-metadata.sh
# edit fastlane/metadata/en-US/{name,subtitle,keywords}.txt
./scripts/upload-appstore-metadata.sh   # when ready to push
```
