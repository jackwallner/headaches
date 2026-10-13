# App Store review prompt (One Tap Headache Tracker)

Policy: `ios-dev` skill, "App Store ratings and feedback". No in-app rating question; only the system prompt asks.

| Field | Value |
|-------|-------|
| App Store ID | `6762074561` |
| Write-review URL | `AppStoreReviewLinks.writeReviewURL` |
| Feedback email | `jackwallner+ha@gmail.com` |
| Positive moment | Successful one-tap log with full context (`Context saved.`) |
| Gates | 2nd cold launch, onboarding done, 30-day cooldown, Home clear ~3s after the log |
| Avoid | Cold launch, onboarding, errors, trial/Pro sheets, paywall chains |
| Settings | "Rate One Tap Headache Tracker" (write-review link) and "Send Feedback" (mail) |
| App group | `group.com.jackwallner.headachelogger` |

Implementation: `ReviewPromptTracker`, `ReviewPromptCoordinator`, host in `HeadacheLoggerRootContent`.
