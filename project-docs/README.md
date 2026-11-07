# Project documentation

Developer notes and historical audits for this repository. The published site remains in the docs directory.

## Audits

- [aso827.md](audits/aso827.md): Migraine Tracker ASO Audit
- [audit823.md](audits/audit823.md): Migraine Headache Tracker audit823
- [ios27HeadacheLogger.md](audits/ios27HeadacheLogger.md): iOS 27 compatibility audit: OneTap Headache Tracker
- [state-machines-2026-11-06.md](audits/state-machines-2026-11-06.md): State machine audit: 9 bugs (5 proved by test, 4 code path), repro in state-machines-2026-11-06-repro.swift
- [state-machines-2026-11-06-review.md](audits/state-machines-2026-11-06-review.md): Independent review of the state machine audit: 9 of 9 confirmed, 0 false positives, ranking and routes corrected
- [state-machines-2026-11-06-fixes.md](audits/state-machines-2026-11-06-fixes.md): Fixes for the state machine audit: 8 fixed (7 with regression tests), 1 held for Jack (B8 trial pitch timing), full suite green
- [state-machines-2026-11-06-verify.md](audits/state-machines-2026-11-06-verify.md): Independent verification of the state machine fixes at 331eb69: PASS, 8 fixes hold, full suite 125/125, 7 tests proved to fail without their fix, B1 prompt seen on the shipping screen

## Design

- [design.md](design/design.md)

## Marketing

- [aso-plan.md](marketing/aso-plan.md): aso-plan.md: HeadacheLogger ASO positioning + metadata
