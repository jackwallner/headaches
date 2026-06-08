# Astro ASO setup — Headache Tracker - One Tap

**Playbook run:** 2026-05-25 · `astro-global-aso-go-2026.md` **go** (full pipeline)

| Field | Value |
|-------|--------|
| App Store name | Headache Tracker - One Tap |
| Bundle ID | `com.jackwallner.headachelogger` |
| Astro appId | `6762074561` |
| ASC version (metadata upload) | **1.4.0** (`PREPARE_FOR_SUBMISSION`) |
| Live App Store version | **1.3.0** (`READY_FOR_SALE`) |

## US highlights (en-US keywords on ASC 1.4.0)

```
headache,migraine,tracker,watch,widget,diary,pain,cluster,export,trigger,health,doctor,symptom,log
```

(98/100 chars — replaces prior `health,journal,export,...` on live 1.3.0.)

## Astro

- **91 stores** synced: `scripts/astro-keywords-by-store/_summary.json` (`syncedAt` 2026-05-26)
- Prune pass: all 91 stores (`scripts/astro-prune-all-stores.log`)
- Competitor scan: `scripts/astro-competitor-research.json` (91 stores)
- Tier-1 suggestions pass: run (`astro-tier1-second-pass.log` — MCP returned no extra suggestions this session)

## ASC upload path

Live **1.3.0** metadata is locked. Use draft **1.4.0**:

```bash
./scripts/asc-finish-missed.sh
```

State file: `scripts/.asc-state.json` · **50** version localizations on 1.4.0 (keywords + descriptions).

**To ship:** attach a build to **1.4.0** and submit for review.

## Scripts added/used

| Script | Purpose |
|--------|---------|
| `asc-add-missing-localizations.sh` | Seed + API create locales (blocked on live appInfo) |
| `asc-finish-missed.sh` | Auto: draft version + missing version locales + upload |
| `asc-upload-metadata.sh` | PATCH keywords/description to draft ASC version |
| `asc-ensure-draft-version.py` | Find/create `PREPARE_FOR_SUBMISSION` version |
| `aso-apply-locale-optimizations.py` | Native keyword/subtitle pass for all fastlane locales |
| `astro-competitor-scan.py` | 91-store `search_app_store` |
| `astro-prune-all-stores.sh` | Prune all stores |
| `astro-tier1-second-pass.py` | Suggestions for tier-1 stores |

## Next: **go refine**

After **1.4.0** is live (or 14+ days on new keywords), re-pull → `astro-optimize --all-stores` → tune from ranks → upload.
