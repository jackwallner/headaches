# Localization — fastlane + Astro

**Playbook:** `docs/astro-global-aso-go-2026.md` / `~/Desktop/astro-global-aso-go-2026.md`

**Last full go:** 2026-05-25 — see `docs/astro-phase-b-report.md`

---

## Quick commands

```bash
# Pull live/draft metadata (set version)
ASC_APP_VERSION=1.3.0 ./scripts/pull-appstore-metadata.sh

# Close gaps automatically (draft version + missing locales + upload)
./scripts/asc-finish-missed.sh

# Or manual draft upload
eval "$(python3 scripts/asc-ensure-draft-version.py | grep '^export ')"
./scripts/asc-upload-metadata.sh

# fastlane deliver (screenshots + metadata; needs editable version)
ASC_APP_VERSION=1.4.0 ./scripts/upload-appstore-metadata.sh

# Add missing ASC locales (API; may fail on live appInfo — seeds fastlane folders)
ASC_APP_VERSION=1.3.0 ./scripts/asc-add-missing-localizations.sh --all-supported

# Astro
./scripts/astro-sync-all-stores.sh
./scripts/astro-prune-all-stores.sh
./scripts/astro-optimize.py --store us
```

---

## Locales on disk (50)

**39 on ASC:** `ar-SA`, `ca`, `cs`, `da`, `de-DE`, `el`, `en-AU`, `en-CA`, `en-GB`, `en-US`, `es-ES`, `es-MX`, `fi`, `fr-CA`, `fr-FR`, `he`, `hi`, `hr`, `hu`, `id`, `it`, `ja`, `ko`, `ms`, `nl-NL`, `no`, `pl`, `pt-BR`, `pt-PT`, `ro`, `ru`, `sk`, `sv`, `th`, `tr`, `uk`, `vi`, `zh-Hans`, `zh-Hant`

**11 extra locales** (version metadata on draft **1.4.0**; appInfo still manual): `bn-BD`, `gu-IN`, `kn-IN`, `ml-IN`, `mr-IN`, `or-IN`, `pa-IN`, `sl-SI`, `ta-IN`, `te-IN`, `ur-PK`

---

## Backups

| Backup | Contents |
|--------|----------|
| `metadata.bak.20260525-174714` | Pre-run pull snapshot |
| `metadata.bak.pre-upload-20260525-174752` | Optimized tree before ASC upload |

```bash
./scripts/restore-appstore-metadata.sh --list
./scripts/restore-appstore-metadata.sh 20260525-174714
```

---

## en-US keyword field (on ASC 1.4.0)

```
headache,migraine,tracker,watch,widget,diary,pain,cluster,export,trigger,health,doctor,symptom,log
```

Apply script: `python3 scripts/aso-apply-locale-optimizations.py`  
Report: `scripts/aso-locale-optimization-report.json`

---

## Astro — 91 stores

Summary: `scripts/astro-keywords-by-store/_summary.json`  
Per-store JSON: `scripts/astro-keywords-by-store/{store}.json`

Locale → store map: `scripts/astro-sync-all-stores.py` (`LOCALE_TO_STORE`)

---

## Live vs draft metadata

| Version | State | Metadata editable? |
|---------|--------|-------------------|
| 1.3.0 | READY_FOR_SALE (live) | No (API + deliver) |
| 1.4.0 | PREPARE_FOR_SUBMISSION | Yes — **uploaded this run** |

Submit **1.4.0** with a binary to publish optimized keywords/descriptions.
