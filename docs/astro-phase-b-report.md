# Astro global ASO — Phase B report (go run)

**Date:** 2026-05-25  
**App:** Headache Tracker - One Tap (`6762074561`)  
**Pipeline:** `~/Desktop/astro-global-aso-go-2026.md` — full **go**

---

## Backups

| Path | When |
|------|------|
| `fastlane/metadata.bak.20260525-174714` | Pull (start of run) |
| `fastlane/metadata.bak.pre-upload-20260525-174752` | Pre-upload (optimized tree) |

Restore: `./scripts/restore-appstore-metadata.sh --list`

---

## ASC localizations

| Metric | Count |
|--------|------:|
| Locales on ASC draft **1.4.0** (version metadata) | **50** |
| Locales optimized on disk | **50** |
| Live **1.3.0** version locales | **39** (unchanged until 1.4.0 ships) |

### fastlane 2.234+ (fixed)

| Item | Status |
|------|--------|
| **50 version** locales on draft 1.4.0 | Done (API + deliver) |
| **50 appInfo** locales on draft | Done via `fastlane/Deliverfile` + `scripts/fastlane-bin.sh` |
| **en-US subtitle** on draft appInfo | `Migraine & Headache Log` (was `Simple migraine and pain log` on live) |

**PATH trap:** `/usr/local/bin/fastlane` was **2.230** (no `bn-BD`, etc.). Use **`scripts/fastlane-bin.sh`** → Homebrew **2.234.0**.

Check: `python3 scripts/asc-check-state.py`

---

## Keyword / subtitle changes (sample)

Full diff: `scripts/aso-locale-optimization-report.json`

| Locale | Keywords (len) | Change summary |
|--------|-------------:|----------------|
| en-US | 98 | `headache,migraine,tracker,watch,widget,...` (was health,journal,export,...) |
| de-DE | 97 | Native kopfschmerz/migräne/tracker/watch/... |
| fr-FR | ~95 | migraine,céphalée,tracker,montre,... |
| ja | ~90 | 頭痛,片頭痛,トラッカー,ウォッチ,... |
| pl | ~95 | ból,głowy,migrena,tracker,zegarek,... |

**Subtitles** updated locally for en-* / de / fr / es / ca / it / ja / ko / zh-* / pl (≤30 chars). **Name/subtitle** on ASC appInfo remain unchanged until next app version allows appInfo edits.

---

## Astro stores (91)

| Item | Status |
|------|--------|
| `astro-sync-all-stores.sh` | **Done** — 91 stores (`_summary.json` `storeCount`: 91) |
| Prune all stores | **Done** — removed junk e.g. `migraine log` (gb/au/ca), `дневник` (ru/ua/kz/...) |
| Tier-1 second pass | Run — no new MCP suggestions returned |

Logs: `scripts/astro-sync-all-stores.log`, `scripts/astro-prune-all-stores.log`, `scripts/astro-competitor-research.json`

---

## Upload

| Method | Result |
|--------|--------|
| `upload-appstore-metadata.sh` (deliver 2.230) | **Failed** — no editable live version; `edit_live` releaseType error |
| `asc-upload-metadata.sh` → **1.4.0** | **Success** — 39 locales, keywords + description (+ whatsNew/urls where set) |

**Verified:** ASC 1.4.0 `en-US` keywords = optimized string (API read-back).

**User action:** Submit **1.4.0** with a build for metadata to reach the public App Store.

---

## Checklist (playbook)

- [x] Pull + backup
- [x] Add missing locales (seeded; API blocked on live appInfo)
- [x] Re-pull
- [x] Competitor scan (91 stores)
- [x] Optimize all fastlane locales (50 dirs; char verify 0 OVER)
- [x] Pre-upload backup
- [x] Astro 91-store sync
- [x] Prune all stores
- [x] Tier-1 second pass
- [x] Upload (**1.4.0** via API; deliver blocked on live)
- [x] Docs

---

## go refine

Calendar: **~2026-06-08** (14 days after 1.4.0 is live). Re-pull → rank-based `astro-optimize` → tune fastlane → `ASC_APP_VERSION=<draft>` upload.
