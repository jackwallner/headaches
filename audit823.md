# Migraine Headache Tracker audit823

Fresh max-reasoning audit of `/Users/jackwallner/headaches`, completed 2026-08-23.

This audit covers only Migraine Headache Tracker. It is an audit artifact, not an implementation. No app code, configuration, metadata, website, or other repository file was changed.

## Scope and evidence rules

The review covered:

- Local Swift, SwiftUI, SwiftData, StoreKit, RevenueCat, WidgetKit, WatchConnectivity, HealthKit, background-task, test, script, website, metadata, terms, privacy, and agent-documentation files.
- The live App Store listing and the available App Store Connect status and analytics surfaces for app ID `6762074561`.
- The available production-mode RevenueCat project for `One Tap Headache Tracker`, project ID `9f4317d7`.
- The public GitHub Pages site and the corresponding checked-in HTML and JSON-LD.
- Trial and purchase paths, review prompting, onboarding, capture, insights, alerts, watch/widget paths, and likely release-regression signals.

Evidence labels used below:

- **Verified local** means directly read from the repository.
- **Verified ASC** means visible in App Store Connect or the public App Store listing during this audit.
- **Verified RevenueCat** means visible in the production-mode RevenueCat project during this audit.
- **Inference** means a conclusion from code or from a configuration relationship. It needs runtime or dashboard validation before being treated as a measured fact.
- **Recommendation** means proposed implementation or experiment work, not an existing behavior.

Out of scope by explicit instruction: I did not classify the App Store `Data Not Collected` label versus RevenueCat purchase or entitlement processing as a defect. The privacy policy already names RevenueCat. The consistency findings below concern names, prices, URLs, behavior descriptions, legal copy, release state, and operational documentation.

## Executive assessment

The app has a strong core product loop: a headache is persisted immediately, contextual data is filled in asynchronously, and the free experience remains useful without an account. The strongest monetization value is also clear in the code: personalized patterns and proactive alerts become useful after the app has accumulated a small history.

The highest-risk issues are not cosmetic:

1. **P0, pending purchase is handled as success in three purchase surfaces.** `PurchaseState.pending` is returned by `StoreService`, but onboarding, the root direct-trial sheet, and the full paywall either finish onboarding, dismiss the offer, or otherwise treat pending as purchased. This can lose the trial pitch, pollute conversion measurement, and leave a user without an active entitlement.
2. **P1, pricing has multiple sources of truth.** Local StoreKit testing and website JSON-LD say yearly `$39.99` and lifetime `$89.99`. Observed RevenueCat production transactions and the RevenueCat paywall builder showed yearly `$29.99` and lifetime `$59.99`. Monthly `$9.99` agrees. The native paywall mostly uses localized StoreKit prices at runtime, but QA, screenshots, tests, SEO, and user expectations can disagree.
3. **P1, offer exposure and offer completion are conflated.** Onboarding marks the trial offer as seen when the screen appears. Root trial flows mark it seen when presented. A dismissal, product failure, fallback paywall dismissal, or pending purchase can therefore remove the best conversion path without a successful trial start.
4. **P1, the monetization funnel is under-instrumented.** RevenueCat has custom paywall impression calls only. There are no custom attributes, no explicit source, selection, attempt, pending, cancellation, error, or completion events in the app code. RevenueCat and ASC cannot explain which surface produced a trial or which step lost a user.
5. **P1, site, metadata, and app behavior use different identities and URLs.** The public listing is `Migraine Tracker- Headache Log`; the website and many documents use `One Tap Headache Tracker` or `Migraine Headache Tracker Log`. The website canonical URL is `jackwallner.com/ios/headaches/`, while ASC points to GitHub Pages. README store URLs use older redirect paths. A user, search engine, or coding agent can land on different source-of-truth answers.
6. **P1, background location behavior is described inconsistently outside RevenueCat.** Onboarding and older metadata say location is used only when a headache is logged. Proactive Alerts use the last known coarse location for background forecast checks, and the current privacy policy acknowledges this. Copy and support content should describe the Pro behavior consistently.
7. **P1, there is no production crash, hang, purchase, capture, or background-task watchdog in the repository.** Local logs and `os.Logger` calls do not provide an alerting path. The model-store recovery path can delete a corrupt store before falling back to memory, which is a data-recovery risk even though it avoids one class of launch crash.
8. **P2, agent documentation is fragmented and stale.** The `AGENTS.md` symlink arrangement is good, but README commands use a named simulator, several metadata documents describe old titles and versions, and archive notes contain historical symbols. There is no Cursor-specific guide and no concise current app manifest for an agent.

## Current product and release identity

| Surface | Observed value | Evidence and interpretation |
| --- | --- | --- |
| Repository | `/Users/jackwallner/headaches` | Verified local. The codebase is internally named `HeadacheLogger` and the product target is `OneTapHeadacheTracker`. |
| iOS target | `HeadacheLogger` | Verified local in `project.yml`, `CLAUDE.md`, and Xcode project configuration. |
| iPhone bundle ID | `com.jackwallner.headachelogger` | Verified local in `project.yml` and `fastlane/Appfile`. |
| Watch bundle ID | `com.jackwallner.headachelogger.watch` | Verified local in `project.yml`. |
| Widget bundle ID | `com.jackwallner.headachelogger.widget` | Verified local in `project.yml`. |
| App Store Connect app ID | `6762074561` | Verified ASC and local review-link code. |
| Live App Store title | `Migraine Tracker- Headache Log` | Verified public App Store listing. The missing space before the hyphen is visible copy debt. |
| Local en-US title | `Migraine Tracker- Headache Log` | Verified local at `fastlane/metadata/en-US/name.txt`. |
| Subtitle | `One Tap Diary & Trigger Alerts` | Verified ASC and local en-US metadata. |
| Category | Medical | Verified public App Store listing. |
| Age rating | 9+ | Verified public App Store listing. |
| Current version | 1.5.0 | Verified local `project.yml`, ASC status, and website JSON-LD. |
| Local build | 94 | Verified local `project.yml`. |
| ASC version status | iOS 1.5.0, Ready for Distribution | Verified ASC app list on 2026-08-23. This is status evidence, not proof of every storefront or release channel being current. |
| Public App Store rating | 4.7 from 3 ratings | Verified public listing on 2026-08-23. The sample is too small for a strong quality conclusion. |
| Public languages | English shown | Verified public listing. Local fastlane metadata contains 50 locale directories, so active storefront localization status needs verification. |
| RevenueCat project | `One Tap Headache Tracker`, `9f4317d7` | Verified RevenueCat. |
| RevenueCat entitlement | `HeadachePro`, with code fallback `pro` | Verified local `HeadacheLogger/Services/StoreService.swift:13-16`. The fallback is a future configuration hazard. |
| Public website | `https://jackwallner.github.io/headaches/` | Verified ASC links and local metadata. |
| Website canonical | `https://jackwallner.com/ios/headaches/` | Verified local `docs/index.html:10,57`. This differs from the public marketing URL. |

### Snapshot limitations

The ASC analytics page was visible but sparse for the selected day. The snapshot showed Net Paid Plans `4`, Plan Starts `-`, Conversion to Paid `4`, Churned `-`, and Paid to Offer `-`. This is not a complete historical cohort and must not be used as a trial conversion rate.

The RevenueCat overview was in production mode and showed, at the time of inspection: Active Trials `0`, Active Subscriptions `4`, MRR `$11`, Revenue `$30` for the last 28 days, New Customers `29`, and Active Customers `57`. Recent transactions included ended yearly trials, yearly conversions at `$29.99`, and lifetime purchases at `$59.99` and `$80.05` in different currencies. These are dated snapshots, not a denominator-based conversion analysis.

## Download and App Store conversion audit

### Current listing strengths

- The title contains both `Migraine` and `Headache`, which covers the two highest-intent condition terms in the visible name.
- The subtitle communicates a simple diary and trigger-alert promise.
- The description has a clear one-tap action, Apple Watch support, Apple Health context, weather and air quality, patterns, alerts, widgets, Siri, CSV export, local-first storage, trial language, restore, and legal links.
- The live listing is free with in-app purchases, so the download decision does not require a paid upfront commitment.
- The public listing links to a working-looking support page, marketing page, and privacy policy path in the same GitHub Pages site.
- Four iPhone screenshots were visible. The listing advertises iPhone and Apple Watch, but the public listing did not show an accessibility feature declaration and did not establish a watch screenshot sequence.

### Metadata evidence

The local `fastlane/metadata` tree contains 50 locale directories. Character-count validation found no name, subtitle, or keyword field over Apple limits, and the locale files inspected were non-empty. This confirms file hygiene, not that every localization is uploaded, approved, or currently displayed in every storefront.

The current en-US files are:

```text
Name: Migraine Tracker- Headache Log
Subtitle: One Tap Diary & Trigger Alerts
Keywords: barometric,pressure,forecast,weather,tension,cluster,chronic,aura,pain,simple,daily,symptom,sinus
Promotional text: One tap logs a headache. Over time you get a doctor-ready record of triggers, patterns, and what actually helps.
Marketing URL: https://jackwallner.github.io/headaches/
Support URL: https://jackwallner.github.io/headaches/support.html
Privacy URL: https://jackwallner.github.io/headaches/privacy-policy.html
Release notes: Bug fixes and performance improvements.
```

The public listing showed English only even though `fastlane/Deliverfile` and local metadata support many locales. Treat this as an ASC state question, not as proof that the upload failed:

1. Inspect the version localization state in ASC for every locale.
2. Compare the locale list in ASC with `fastlane/metadata` and `scripts/asc-supported-locales.json`.
3. Confirm whether the storefront intentionally launches English-only or whether localizations are pending review, attached to a draft version, or not uploaded.
4. If English-only is intentional, remove or clearly label the stale localization expectation in agent docs. If not intentional, verify screenshots and copy in at least the highest-download storefronts before changing all 50.

### Metadata findings and opportunities

#### P2, fix title typography and identity

`Migraine Tracker- Headache Log` has no space before the hyphen in both local and live metadata. `Migraine Tracker - Headache Log` fits within the 30-character name limit and is easier to scan. Before changing it, check whether the accepted title is locked to the current version and whether the title change would affect an existing search ranking. The change is small but should be made only with a current ASC release plan.

The app has at least four active names across surfaces:

- `Migraine Tracker- Headache Log`, live listing and current en-US metadata.
- `One Tap Headache Tracker`, onboarding, terms, privacy, support, README, and older metadata.
- `Migraine Headache Tracker Log`, website title and JSON-LD.
- `HeadacheLogger` and `OneTapHeadacheTracker`, code and target names.

Recommendation: choose one consumer-facing name, one short product descriptor, and one internal repository name. Keep the internal target names if changing them would cause churn, but add a current identity table to the agent guide.

#### P2, do not blindly reuse the stale keyword proposal

`docs/astro-aso-metadata-proposal.md` describes an older title and subtitle and recommends a keyword field containing `headache,migraine,tracker,watch,widget,diary,pain,cluster,export,trigger,health,doctor,symptom,log`. The current live title already contains `migraine`, `headache`, and `tracker`, so the incremental value of repeating these terms in the keyword field should be measured rather than assumed.

The current field emphasizes `barometric`, `pressure`, `forecast`, `weather`, `tension`, `cluster`, `chronic`, `aura`, `pain`, `simple`, `daily`, `symptom`, and `sinus`. Candidate tests include:

- `diary`, `log`, or `journal` for generic logging intent.
- `migraine` or `headache` only if the title and subtitle are not already carrying adequate search coverage in the target storefront.
- `watch`, `widget`, or `Apple Health` intent, subject to Apple's keyword rules and actual ranking data.
- `trigger` and `pattern`, which describe the Pro value more directly than some weather terms.

Use one controlled metadata change per release, record the exact field and date, then compare ASC acquisition sources, product-page views, downloads, and search-rank evidence. Do not copy the 119-character old draft in `docs/app-store-metadata.md`; that document itself says the old draft exceeds the limit.

#### P2, make the first screenshot do the download work

The listing has four iPhone screenshots, but a source inspection cannot establish their order or current copy. Validate the screenshot sequence against three user questions:

1. What happens in the first two seconds? The first frame should show the one-tap log result, not a settings or empty-state screen.
2. Why keep the app? A subsequent frame should make the accumulated pattern and doctor-ready export value concrete.
3. Why upgrade? A later frame should show personalized alerts or insights without implying diagnosis, treatment, or guaranteed prediction.

Recommended product-page variants:

- Core action first: `Tap once. Context fills itself.`
- Outcome first: `See which patterns follow your headaches.`
- Pro value first: `Get a heads-up when your own history detects a risk pattern.`

Measure product-page conversion, not just screenshot preference. Guard against health claims that sound clinical or predictive beyond the app's actual confidence logic.

#### P2, accessibility and trust signals

The public listing says the developer has not indicated accessibility features. Audit the actual VoiceOver labels, Dynamic Type behavior, contrast, reduced motion, button hit targets, and watch accessibility before adding an ASC declaration. The code has several explicit accessibility identifiers and labels, but no localization resources were found by the repository file scan, so the implementation should be checked in runtime rather than inferred from metadata.

## Trial, purchase, and entitlement flow

### Product catalog and current plans

Verified local product IDs in `HeadacheLogger/Services/StoreService.swift:6-16`:

| Code name | Product ID | RevenueCat package mapping | Observed role |
| --- | --- | --- | --- |
| Lifetime | `com.jackwallner.headachelogger` | `$rc_lifetime` | Non-consumable, one-time purchase. |
| Yearly | `com.jackwallner.headachelogger.pro.yearly` | `$rc_annual` | Annual subscription, code sorts first and defaults to it on the full paywall. |
| Monthly | `com.jackwallner.headachelogger.pro.monthly` | `$rc_monthly` | Monthly subscription, direct onboarding trial target. |

RevenueCat's `default` offering was visible with three packages and display name `Headache Pro`. The code uses `offerings.headacheProPaywallOffering`, which resolves `offering("default")` before falling back to `current` in the local extension. This is a reasonable fallback, but it must be monitored because a missing offering currently becomes an empty product list rather than a differentiated configuration error.

### User paths currently present

| Entry point | Code path | User experience | Monetization risk |
| --- | --- | --- | --- |
| New install | `OnboardingView` steps 0 through 3 | Welcome, Health pre-prompt, Location pre-prompt, then a trial page. | The trial page is in the onboarding sequence, so an offer exposure is easily confused with onboarding completion. |
| Onboarding trial CTA | `OnboardingView.startTrialPurchase()` | Directly purchases the monthly package when loaded. The CTA and disclosure use the localized package price and eligibility. | Monthly is selected for the smaller recurring number, while the full paywall leads with yearly. This is a valid hypothesis but needs measured source-specific conversion and retention. |
| Onboarding fallback | `showPaywallFallback` | Full paywall opens when the monthly package is unavailable. | The full-screen cover's `onDismiss` calls `finishOnboarding()` even if the user dismisses without buying. |
| First log | `HeadacheLoggerApp.evaluateFirstLogTrialOffer()` | Waits about four seconds after the log event so the success state can render, then presents the trial sheet. | Good timing intent, but the flag is set at presentation, not completion. |
| Existing user | `HeadacheLoggerApp.evaluateExistingUserTrialOffer()` | Waits about three seconds after Home appears when existing logs are present. | May compete with a user's first meaningful return session and is one-shot even after a dismissal. Test timing against retention. |
| Patterns second touch | `evaluateInsightsTrialOffer()` | Uses a separate seen flag as a fallback if products failed during the first-log path. | Good recovery intent, but source state and completion state are still not separately measured. |
| Home milestones | `HomeView` | Milestones at 3, 5, and 10 logs can show a Pro paywall. | Multiple upgrade surfaces may stack with trial and review prompts unless the session guard remains correct. |
| Patterns | `InsightsView` | Free locked teaser with sample or blurred previews, then Pro paywall. | Strong value-context entry point. Need distinguish enough-data users from users who have not logged enough to personalize. |
| History | `HistoryView` | Doctor PDF and some history tools gate to Pro, with a contextual paywall. | Export has high user value, but the user should understand what is free before investing in logging. |
| Settings | `SettingsView` | Proactive Alerts row opens paywall for free users, and subscription management appears for subscribers. | A reliable recovery entry point, but the same plan and price source must be used. |
| Restore | `StoreService.restorePurchases()` | Restore is on onboarding, trial sheet, full paywall, and Settings. | Good coverage. Restore success and failure need explicit telemetry and UI-state validation. |

### P0, pending transaction treated as a completed purchase

`StoreService.purchase(_:)` returns `.pending` for StoreKit 2 pending transactions at `HeadacheLogger/Services/StoreService.swift:326-360`. On device, RevenueCat also returns `.pending` when the purchase response does not yet contain the expected active entitlement.

The callers do not preserve the pending state:

- `OnboardingView.swift:313-316` handles `.purchased, .pending` together and calls `finishOnboarding()`.
- `HeadacheLoggerApp.swift:520-543`, in `startDirectTrialPurchase()`, handles `.purchased, .pending` together, marks `hasSeenTrialOffer`, and dismisses the trial sheet.
- `PaywallView.swift:329-346` handles `.purchased, .pending` together and simply breaks, with no pending message or recovery state.
- `OnboardingView` also presents the fallback full paywall with `.fullScreenCover(... onDismiss: { finishOnboarding() })` at `OnboardingView.swift:49-52`, so dismissing the fallback without a purchase can complete onboarding.

Impact:

- A pending parental-approval or delayed-store transaction can be reported internally as a trial start even though no entitlement is active.
- A new user can lose the trial CTA and exit onboarding without Pro.
- A user can see a closed or apparently completed flow, then have to discover Restore Purchases manually.
- RevenueCat trial and conversion metrics become hard to reconcile with in-app flags.

Required behavior:

1. Treat `pending` as a first-class state with copy such as `Purchase pending approval. Your access will update when Apple confirms it.`
2. Keep the offer or paywall open, or provide a clearly labeled non-purchase exit, until the transaction is resolved.
3. Listen for entitlement updates and dismiss only when the explicit `HeadachePro` entitlement becomes active.
4. Do not set onboarding completion, offer-seen, or trial-start state from `.pending`.
5. Test StoreKit pending, cancellation, approval after backgrounding, interrupted network, restore, and relaunch.

Acceptance evidence:

- A pending transaction leaves `isProUnlocked == false` and `hasSeenTrialOffer` unchanged unless the product decision explicitly says exposure should be consumed.
- Onboarding can be completed without a purchase through the visible `Get Started` path.
- The user sees a recovery message and can restore or retry.
- A later entitlement update unlocks Pro and dismisses the surface exactly once.
- ASC and RevenueCat trial-start counts are not incremented by a pending result alone.

### P1, separate exposure, attempt, completion, and dismissal

`OnboardingView.handleTrialStepAppear()` at `OnboardingView.swift:292-297` sets `hasSeenTrialOffer = true` when the fourth step appears. The root flow also calls `markTrialOfferSeen()` at presentation time in `HeadacheLoggerApp.swift:472-518`. These flags are useful for suppressing repeated interruptions, but they currently answer several different questions:

- Was the offer rendered?
- Did the user understand the offer?
- Did the user tap the CTA?
- Did Apple show a purchase sheet?
- Did the trial begin?
- Did the user dismiss or decline?

Recommendation: keep separate state for `trialOfferExposureCount` or a bounded exposure marker, `lastTrialOfferSource`, `lastTrialOfferPackage`, `trialPurchaseAttempted`, `trialPurchasePending`, and `trialStarted`. Avoid storing medical content. If a one-shot offer is a product decision, make that explicit and still record the outcome separately.

Validation matrix:

| Scenario | Offer exposure | Purchase attempt | Entitlement | Offer state after relaunch |
| --- | --- | --- | --- | --- |
| User taps `Get Started` | Yes | No | No | Product decision, but should be distinguishable from a successful trial. |
| User taps CTA then cancels Apple sheet | Yes | Yes | No | CTA should remain available according to the chosen retry policy. |
| User taps CTA and transaction becomes pending | Yes | Yes | No initially | Pending state and recovery affordance must remain. |
| User approves pending transaction | Yes | Yes | Yes | Pro unlocks and the paywall closes. |
| Product fetch fails | Maybe | No | No | Fallback must not silently mark onboarding complete on dismissal. |
| User buys lifetime | Yes or no | Yes | Yes | No subscription-management row, but Pro features unlock. |

### P1, entitlement matching is too broad

`CustomerInfo.hasHeadacheProEntitlement` at `StoreService.swift:147-150` currently returns true when `entitlements.active` is non-empty. `StoreService.apply(customerInfo:)` uses the same broad active-entitlement logic. This is safe only while the RevenueCat project has exactly one entitlement that can unlock this app.

Recommendation: check `entitlements[RevenueCatConfig.proEntitlement]?.isActive == true`, with the fallback only during a controlled migration. Add a test for a customer with another active entitlement that must not unlock Headache Pro. This prevents a future RevenueCat catalog addition from silently changing access.

### P1, product loading and offering fallback need diagnostics

At `StoreService.swift:305-323`, a device fetch resolves the RevenueCat offering and sets `products` to an empty array when no offering is available. The paywall then shows `Couldn't Load Plans` and `Try Again` at `PaywallView.swift:58-100`.

Recommendations:

- Distinguish network failure, RevenueCat configuration failure, StoreKit product-unavailable, and no-intro-eligibility states.
- Record the offering identifier, returned product IDs, package count, locale, storefront, and app version as safe diagnostics.
- Add a non-purchase support path from the empty state, including Restore and a support link if the user has already paid.
- Set a bounded retry policy to avoid repeated requests on every view appearance.
- Alert on production sessions with paywall impression but zero products.

### Trial pricing and offer configuration decision

The code intentionally uses the monthly package for the onboarding trial (`StoreService.swift:153-166`) and sorts yearly, monthly, lifetime on the full paywall (`StoreService.swift:79-90,212-220`). The full paywall defaults to yearly in `PaywallView.swift:308-327`.

This creates a testable product choice:

- New users see the lower monthly recurring number and can start monthly directly.
- Users who reach a contextual paywall see yearly first and may see an annual savings badge.

Do not assume that the same free-trial eligibility applies to both products. The local StoreKit file has a seven-day introductory offer on both monthly and yearly. The observed RevenueCat Components draft showed a seven-day trial label on Yearly but did not visibly label Monthly with a trial. The public description says both monthly and yearly have a seven-day free trial. Verify the actual ASC introductory-offer configuration and RevenueCat eligibility response for both IDs, then align the paywall, onboarding disclosure, metadata, and terms.

## RevenueCat audit

### Verified project state

RevenueCat production-mode evidence on 2026-08-23:

- Project: `One Tap Headache Tracker`, ID `9f4317d7`.
- Default offering: `Headache Pro`, three packages, created 2026-05-10.
- Packages: `$rc_monthly`, `$rc_annual`, `$rc_lifetime`.
- Observed package IDs match `StoreService` product constants.
- RevenueCat Paywalls showed a `Headache Pro` Components paywall with `Draft changes`, `No offering`, and last edit 2026-08-01 in the published list.
- The builder showed `Changes saved as a draft` and a `Publish changes` control.
- The builder copy showed Yearly `$29.99 / year` with a seven-day free trial, Monthly `$9.99 / month`, and Lifetime `$59.99 one-time`.
- RevenueCat Experiments showed `No experiments yet`.

The app code is a native SwiftUI paywall, not an obvious RevenueCat Components Paywall. Unless code elsewhere references the Components paywall, the draft is likely not user-visible. That is an inference and must be confirmed before anyone publishes or deletes it.

Decision required:

1. Native SwiftUI remains the sole paywall source of truth, in which case archive or clearly label the unused Components draft and maintain a catalog checklist.
2. RevenueCat Components becomes the source of truth, in which case migrate intentionally, test the rendered purchase states, and remove duplicate native copy.
3. A hybrid is allowed only with explicit surface ownership, shared product identifiers, shared trial disclosure, and separate impression IDs.

### Existing RevenueCat instrumentation

The only custom RevenueCat event-like call found is `Purchases.shared.trackCustomPaywallImpression(...)` in `StoreService.swift:451-465`.

Current impression IDs:

- `headache_onboarding_trial`
- `headache_trial_sheet`
- `headache_pro_intro_sheet`
- `headache_home_sheet`
- `headache_history_sheet`
- `headache_insights_sheet`
- `headache_settings_sheet`

The onboarding impression is configured with `oncePerSession: true`. Impressions are skipped in the simulator. There were no `setAttributes`, `setAttribute`, custom RevenueCat event, purchase-source, trial-source, or review-source calls found in the app code scan.

This is enough to answer `which paywall surface was rendered` in RevenueCat, but not enough to answer:

- whether products loaded,
- which package was selected,
- whether the user tapped the CTA,
- whether the Apple sheet appeared,
- whether the user cancelled,
- whether the result was pending,
- whether an active entitlement arrived later,
- whether the user restored,
- whether the user was eligible for the intro offer,
- whether the user had completed a first log,
- whether a later trial or lifetime purchase came from an earlier exposure.

### Recommended safe custom attributes

Set only low-sensitivity operational or funnel attributes. Do not send headache severity, medication, diagnosis, free-text notes, raw HealthKit values, coordinates, locality, weather values, or any other medical or environmental event data to RevenueCat.

| Attribute | Suggested values | Set or refresh at | Why it helps |
| --- | --- | --- | --- |
| `app_version` | `1.5.0` | RevenueCat configuration completion and app foreground | Segment regressions by release. |
| `build_number` | `94` | Same point | Separate metadata-only release from binary behavior. |
| `paywall_surface` | `onboarding`, `first_log`, `existing_user`, `insights`, `history`, `settings`, `home_milestone`, `pro_intro` | Immediately before a purchase attempt | Tie purchase events to the last known surface. |
| `trial_offer_source` | Same bounded source enum | When each offer is rendered | Compare source conversion and retention. |
| `trial_package_id` | Product ID, not price | Before the trial CTA or purchase | Verify monthly versus yearly behavior. |
| `selected_package_kind` | `monthly`, `yearly`, `lifetime` | On selection and before purchase | Measure plan-order and framing experiments. |
| `trial_offer_eligible_monthly` | `true` or `false` | After eligibility refresh | Explain why a trial CTA did or did not appear. |
| `trial_offer_eligible_yearly` | `true` or `false` | Same point | Same for yearly. |
| `onboarding_completed` | `true` or `false` | After a real onboarding completion decision | Separate offer completion from onboarding. |
| `first_log_completed` | `true` or `false` | After the first persisted event | Segment users by delivered value. |
| `event_count_bucket` | `0`, `1`, `2-4`, `5-9`, `10+` | After a successful event save | Relate value maturity to conversion without sending event data. |
| `health_permission_state` | `undecided`, `authorized`, `denied`, `limited` if supported | After onboarding and settings changes | Explain context-value differences. |
| `location_permission_state` | `undecided`, `when_in_use`, `denied`, `restricted` | After onboarding and settings changes | Explain weather and alert availability. |
| `alerts_enabled` | `true` or `false` | When the Pro alert toggle changes | Measure whether alert value is activated after purchase. |
| `pattern_alert_state` | `not_ready`, `ready`, `enabled`, `disabled` | When the personal sample threshold changes or settings change | Explain whether a purchaser reaches the alert aha moment. |
| `last_capture_status` | `complete`, `partial`, `failed`, `pending` | After capture finalization | Detect UX regressions without sending event content. |
| `storefront` | StoreKit storefront country code | After StoreKit or RevenueCat provides it | Compare price and conversion by storefront. |
| `locale` | BCP-47 language/region | Configuration completion | Identify localization and price-display problems. |
| `device_family` | `iPhone`, `iPad`, `watch` where applicable | Configuration completion | Separate device-specific acquisition and purchase behavior. |

Implementation insertion points:

1. `StoreService.configureIfNeeded()` after RevenueCat is configured, for app and device context.
2. `StoreService.fetchProducts()` after the offering and intro eligibility resolve, for catalog state.
3. Each paywall presenter immediately before impression tracking, setting `paywall_surface` and source.
4. Each plan-card selection callback in `PaywallView`, setting `selected_package_kind`.
5. Each purchase caller before `store.purchase(package)`, setting source and product ID.
6. `StoreService.apply(customerInfo:)` after checking the explicit `HeadachePro` entitlement, for subscription state changes.
7. `OnboardingView.finishOnboarding()` only after the user has made a real completion decision, not from a pending purchase or paywall dismissal.
8. Capture finalization and alert settings changes for the safe status attributes above.

Before implementation, verify the exact RevenueCat SDK attribute API exposed by the pinned `5.72.0` package. If custom event APIs are not available or are not appropriate, use bounded attributes plus RevenueCat's built-in purchase events and keep the complete event ledger in a local or separate analytics system selected by the product owner.

### RevenueCat catalog and price consistency

Observed values:

| Source | Monthly | Yearly | Lifetime | Status |
| --- | --- | --- | --- | --- |
| `HeadacheLogger/Services/Products.storekit` | `$9.99` | `$39.99` | `$89.99` | Local StoreKit Testing configuration. |
| `docs/index.html` JSON-LD | `$9.99` | `$39.99` | `$89.99` | Published-site source in the repo. |
| RevenueCat Components draft | `$9.99` | `$29.99` | `$59.99` | Draft builder state, not proven to be active in the app. |
| RevenueCat production transaction rows | Evidence for `$29.99` yearly and `$59.99` lifetime | Same | Same | Observed transaction evidence in production mode. |
| Native SwiftUI paywall | Localized `StoreProduct` price | Localized `StoreProduct` price | Localized `StoreProduct` price | Runtime code, so the Apple product configuration is the final device price. |

Required decision: either update the live catalog and all supporting copy to the intended price, or update local StoreKit, site JSON-LD, tests, screenshots, and docs to the live price. Do not let a test configuration continue to assert that it matches ASC when the observed production catalog differs.

## Native paywall and A/B test opportunities

### Existing native paywall behavior

`HeadacheLogger/Views/PaywallView.swift` is a custom SwiftUI paywall. It has:

- A header, feature cards, three plan cards, one CTA, billing disclosure, Restore Purchases, Terms, Privacy, and an empty/error state.
- Yearly as the hard-coded recommended and default plan.
- A yearly savings badge derived from current package prices.
- Trial-aware labels and localized prices from `StoreService`.
- A full-plan fallback for the onboarding direct-trial path.
- Paywall impression IDs sent to RevenueCat.
- A `purchaseInFlight` state, but no first-class pending state.

The native implementation has useful control for experiments, but the experiment allocation and result logging are absent. Do not call a code branch an A/B test until it has randomized assignment or deterministic cohort assignment, exposure logging, a primary metric, guardrails, and a stop rule.

### Prioritized experiment matrix

| Priority | Hypothesis | Variant A | Variant B | Primary metric | Guardrails | Code surface |
| --- | --- | --- | --- | --- | --- | --- |
| P1 | Users need delivered value before committing. | Onboarding monthly trial CTA. | Finish onboarding, show the trial after the first successful capture. | Trial starts per install and day-7 retained users. | Onboarding completion, first-log completion, refund/cancel rate. | `OnboardingView`, root trial triggers. |
| P1 | The lower first price increases trial starts without destroying paid value. | Monthly direct trial as current. | Yearly direct trial with explicit annual renewal amount. | Trial starts per eligible offer impression. | Trial-to-paid, first renewal, support contacts. | `StoreService.onboardingTrialPackage`, onboarding copy. |
| P1 | Default plan choice changes conversion. | Yearly default, current. | Monthly default. | Completed purchases per paywall impression. | Revenue per visitor, trial-to-paid, lifetime share. | `PaywallView.selectDefaultPackageIfNeeded()`. |
| P1 | Clear price framing reduces uncertainty. | Localized annual price plus monthly equivalent. | Annual price plus explicit `then billed annually` and exact renewal disclosure. | CTA tap rate and completed purchase rate. | Refunds, cancellations, legal-copy complaints. | Plan card and disclosure. |
| P1 | Contextual value converts better than generic features. | `Know before the headache hits` and alerts first. | Personal pattern and doctor-ready history first. | Purchase completion by source. | Time to first log, paywall dismissal, review prompt suppression. | `PaywallView`, `InsightsView`, `HistoryView`. |
| P1 | A direct trial should follow a visible success moment. | First-log sheet after the current four-second delay. | Inline or Home card after `Context saved` and after the user opens the result. | Trial start per complete capture. | Session abandonment, prompt collision, review funnel. | `HeadacheLoggerApp.evaluateFirstLogTrialOffer()`. |
| P2 | A preview is more persuasive when it is readable. | Blurred or sampled pattern preview, current. | One clearly labeled, privacy-safe example plus a real-data unlock explanation. | Insights paywall open and purchase rate. | Misleading-example complaints, confusion about real versus sample data. | `InsightsView` locked teaser. |
| P2 | One plan at a time lowers choice friction. | Three cards, current. | Recommended yearly card with a secondary `See monthly and lifetime` expansion. | Purchase completion and time to selection. | Lifetime share and restore support. | `PaywallView` plan layout. |
| P2 | Feature-specific paywalls outperform generic plan lists. | Same full paywall for every gate. | Copy and selected feature vary by source, with one shared catalog. | Source-specific purchase rate. | Total paywall frequency, retention, support contacts. | Home, History, Insights, Settings sheets. |
| P2 | Trial copy should show the next charge before the Apple sheet. | Existing disclosure. | Explicit `7 days free, then $X per month/year`, cancel path, and selected package. | CTA tap and cancellation before first charge. | App Review compliance and refund requests. | `StoreService` disclosure builders. |
| P3 | Review timing can be improved after monetization changes. | Current positive-moment gate. | Same gate with a longer post-purchase success window. | Rating conversion and average rating. | Prompt complaints, prompt dismissal, purchase interruption. | `ReviewPromptTracker`, root coordinator. |

### Experiment implementation requirements

- Assign a variant before the first exposure and persist it in the app group.
- Include variant and source in the RevenueCat-safe attributes or the selected event system.
- Do not randomize a user between monthly and yearly prices after an Apple purchase sheet has opened.
- Keep all legal and price disclosures dynamic from the selected StoreKit product.
- Exclude users with an active entitlement, pending transaction, or unresolved customer status from acquisition experiments.
- Use install-level or customer-level assignment, not view-level randomization.
- Predefine minimum exposure, decision date, primary metric, and guardrails.

## Onboarding and in-app UX

### Strengths

- `OnboardingView.swift:20-54` has four clear steps and prefetches products before the trial step.
- The Health screen explains read-only access and the Location screen explains approximate weather use and no continuous tracking.
- The common page layout reserves CTA and legal-footer space, reducing button movement between steps.
- The user can select `Get Started` rather than buying, and legal links plus Restore are visible on the trial step.
- `CaptureCoordinator.captureHeadache()` inserts the event and saves it before asynchronous enrichment at lines 80-112, protecting the one-tap promise.
- Widget and watch-originated pending rows are re-enriched on foreground through `pendingCaptureFetchDescriptor()` at `CaptureCoordinator.swift:61-78`.
- Partial context is surfaced rather than silently discarded.
- Insights are gated until five events by `InsightsEngine.minimumSampleSize` at `InsightsEngine.swift:8-11`, which reduces overclaiming from tiny samples.
- Proactive Alerts use a separate five-day personal signal threshold in `ProactiveAlertsEngine.swift:514-517`.
- The app has contextual paywalls from Home, History, Patterns, Settings, and onboarding, rather than one generic upsell only.

### P1, onboarding trial and permission copy needs a single behavior contract

The onboarding screen at `OnboardingView.swift:223-236` says Pro provides patterns, pressure and air-quality heads-up, and on-device processing. The button and disclosure are dynamic when the monthly package loads. However:

- The screen is both an onboarding step and a monetization surface.
- A user can leave through `Get Started`, but the seen flag is still set.
- The fallback full paywall dismiss handler completes onboarding regardless of purchase state.
- The Location pre-prompt says weather and place labels happen when logging, while Pro background forecasts use cached location.

Define one contract for each permission and purchase outcome. The agent implementing the next change should be able to answer, for every path, whether onboarding is complete, whether the offer is consumed, whether Pro is active, and what the user can do next.

### P1, the first capture can take longer than the one-tap promise suggests

At `CaptureCoordinator.swift:117-165`, HealthKit capture runs before environment capture. The event is safe because it was already saved, but the UI remains in a `Saving and collecting context…` state while the sequential work completes. On first permission use or poor network, this may be several seconds.

Recommendations:

- Keep the immediate `Saved` state separate from `Context enrichment` state.
- Render the timestamp and initial event as complete immediately, then show optional context arriving progressively.
- Record time-to-initial-save, time-to-finalize, and partial/failed status in safe diagnostics.
- Make retry visible from the event detail and include a non-blocking `Context still loading` status for pending rows.
- Do not delay a review or trial prompt until a complete capture if the user already received meaningful value, but avoid presenting both prompts in the same session.

### P1, background alert reliability is not visible to the user

`BackgroundRefreshService.swift:4-55` schedules a BGAppRefreshTask with an earliest interval of three hours, but iOS decides whether and when it runs. The app schedules only when Pro is active and alerts are enabled (`HeadacheLoggerApp.swift:338-343`).

`ProAlertsConfigView` shows last alert and settings, but a user needs to distinguish:

- alerts enabled,
- notification permission granted,
- location available,
- personal pattern ready,
- last forecast check,
- last successful forecast response,
- last scheduled task,
- last task failure or skipped condition.

Add a compact status view in the eventual implementation. If the last successful forecast check is older than a chosen threshold, explain why an alert may not arrive and offer a foreground refresh. This is especially important because an alert product can be perceived as broken even when no crash occurred.

### P2, pattern and alert value ladder

The free Patterns view has a locked teaser with sample or blurred previews. Pro content becomes useful at five logged events, while multivariate analysis requires more data in `InsightsEngine.swift`. Proactive Alerts require at least five condition days and additional relative-risk conditions.

The product should make this ladder explicit:

1. Log one headache immediately and see the saved context.
2. Reach five logs and unlock initial patterns.
3. Build five condition days and unlock personal alert readiness.
4. Continue logging to improve confidence and expose combined patterns.

The paywall should promise only what the user can reach. If the app says `Get proactive notifications before your headache risk starts to climb`, state that the feature becomes active after enough personal history and a qualifying pattern. Avoid language that sounds like diagnosis or guaranteed prediction.

### P2, string and localization architecture

The repository file scan found no `.lproj`, `Localizable.strings`, or `.xcstrings` files. The App Store metadata has 50 locale directories, but the app UI appears to be source-string English. The next implementation agent should decide whether UI localization is planned. If yes, add a deliberate localization plan and test the paywall, legal disclosure, date, currency, and accessibility strings in the first supported languages. If no, do not imply full product localization just because ASC metadata has many locales.

## Ratings and review funnel

### Existing funnel

`ReviewPromptTracker.swift` is conservative:

- Five app launches minimum, lines 28-31.
- Seven days since first open, lines 30-32 and 116-129.
- Three positive moments, lines 32-35.
- Positive moments are recorded for complete context capture, CSV/PDF exports, and a real insight.
- A 120-day cooldown after `Not now`, lines 35-37 and 109-114.
- An outcome suppresses future passive prompts, lines 66-77 and 148-155.
- The root delays the passive prompt by 3.5 seconds after a positive moment and avoids onboarding, trial, Pro intro, and error states at `HeadacheLoggerApp.swift:277-325`.

`ReviewPromptSheet.swift` uses an enjoyment question, routes unhappy users to feedback, and opens a storefront-aware write-review URL for users who say they are enjoying the app. Settings can request a manual prompt through `ReviewPromptCoordinator`, and feedback goes to `jackwallner+ha@gmail.com`.

This is a good baseline because it avoids cold-launch, error, onboarding, and paywall prompts. The public rating is 4.7 from only three ratings, so the goal should be more qualified review volume, not simply more prompts.

### P2, review improvements

- Keep the positive-moment gate and do not tie review requests to purchase completion or a positive payment outcome.
- Treat `Maybe later` and `Not now` as different intent if product decisions need to distinguish them, while keeping a long cooldown.
- Record only safe operational state if measurement is added. Do not attach review prompts to medical content.
- Validate that direct write-review URLs open the correct storefront on non-US devices. `AppStoreReviewLinks` derives the storefront dynamically.
- Add a support/troubleshooting link before the feedback mail composer if the mail app is unavailable.
- Add tests for no cold-launch prompt, no prompt during an active purchase, no prompt after a failed capture, and no second passive prompt after a recorded outcome.
- Check whether the copy `Support an indie dev` increases trust or feels like pressure. The current copy also says `honest App Store review`, which is preferable to requesting a specific star rating.

### Review funnel validation

Use a staged test account or StoreKit environment and verify:

1. Three complete logs over the minimum launch and age thresholds produce one enjoyment prompt only on Home.
2. A partial or failed capture does not count as a positive moment.
3. `Not really` opens feedback without opening the review URL.
4. `Maybe later` does not invoke the native review request immediately.
5. A review outcome suppresses future passive prompts but Settings remains a deliberate manual path.
6. A trial or paywall sheet never appears on top of the review sheet.

## Usage paths and user experience by feature

### Home and one-tap logging

`HomeView` centers the product on a large log action with accessibility labels and an identifier. The event is saved immediately, then context is filled from HealthKit and Open-Meteo. The Home view shows the latest event, recovery or status cards, milestones, previous entries, and a `What Gets Captured` explanation.

The key validation questions are:

- Does the first tap visibly acknowledge within a human-perceptible interval even when HealthKit is slow?
- Does the user understand that the timestamp is already safe when enrichment is pending?
- Can a partial context event be retried without duplicating the event?
- Does a watch or widget event appear with a status that explains whether it is queued or complete?
- Does the first-log trial offer wait until the success state is understandable?
- Does a user who declines Pro still retain a useful Home and History experience?

### History and export

`HistoryView` exposes event details, CSV export, Doctor PDF, import/export, and Pro gates. CSV and PDF exports count as positive moments, which is a sensible signal because they represent delivered value. Validate the paywall timing around a user who has invested in logging but has not yet seen a pattern.

The local README says CSV has 60+ columns and the website JSON-LD describes the export as 60-column. Keep this number generated from the export schema or describe it as `60+` everywhere. A static exact number can drift as fields are added.

### Patterns and Insights

`InsightsView` distinguishes free locked previews from Pro data. Pro content includes personalized patterns, daily risk forecast, and alert entry points. It includes a non-clinical disclaimer in detail views and waits for five events before showing personal insights.

Validation priorities:

- A new user sees a useful sample without mistaking it for their own data.
- A five-event user sees an accurate empty or no-signal state if no pattern qualifies.
- A user without location or forecast data sees a clear partial-data explanation.
- Pattern copy never implies causation from correlation or diagnosis.
- The paywall source is recorded as `insights`, not as a generic sheet.

### Proactive Alerts

`ProAlertsConfigView` handles notification permission, location, thresholds, quiet hours, test alerts, pattern sensitivity, and readiness. `ProactiveAlertsEngine` requires personal signal conditions before sending forecast notifications.

Validate the complete lifecycle:

- Pro purchase or restore unlocks the row.
- Notification denial shows a recoverable settings path.
- Location denial does not crash or create an endless permission loop.
- A user below the pattern sample threshold understands why alerts are quiet.
- A test notification is clearly labeled as a test.
- The six-hour notification cooldown is visible or explainable.
- A background task that is never granted execution time does not claim that a forecast was checked.

### Watch, widget, and Siri

The codebase supports Apple Watch logging, WidgetKit quick logging, App Intents, and WatchConnectivity. These are strong download and retention differentiators, but they create more regression surfaces than the iPhone path:

- Watch transfer can produce an orphan or duplicate.
- Widget extensions cannot perform the full enrichment pass and rely on foreground re-enrichment.
- Siri or widget launch can occur before onboarding is complete.
- App Group availability affects local persistence.
- Watch and widget bundle configuration must stay aligned with `project.yml` and entitlements.

Add source-specific safe diagnostics: `capture_source`, queue age bucket, deduplication result, enrichment result, and final capture status. Do not send event content.

## Website, terms, privacy, and consistency

### Consistency matrix

| Topic | Local or live value | Finding | Priority |
| --- | --- | --- | --- |
| Consumer name | Listing and metadata use `Migraine Tracker- Headache Log`; site and legal pages use `One Tap Headache Tracker` or `Migraine Headache Tracker Log`. | Search, support, legal, and agent handoffs can look like different products. | P1 |
| App Store URL | README uses `headache-migraine-logger`; older site links use `migraine-headache-tracker-log`; public canonical listing observed is `migraine-tracker-headache-log`. | Redirects may work, but every redirect is a link-check and analytics risk. | P1 |
| Marketing URL | ASC and metadata use GitHub Pages. | `docs/index.html:10,57` declares `jackwallner.com/ios/headaches/` as canonical and JSON-LD URL, so search engines receive a different identity. | P1 |
| Monthly price | `$9.99` across local, site, and observed RC. | Consistent in the checked surfaces. Verify local currency rendering. | P3 |
| Yearly price | Local StoreKit and site JSON-LD `$39.99`; observed RC builder and production transaction `$29.99`. | Multiple sources of truth. | P1 |
| Lifetime price | Local StoreKit and site JSON-LD `$89.99`; observed RC builder and production transaction `$59.99`. | Multiple sources of truth. | P1 |
| Trial | Public description says monthly and yearly have seven-day trials; local StoreKit has both; RC builder visibly labels Yearly only. | Verify actual product configuration and align copy. | P1 |
| Version | Project, ASC, and JSON-LD say 1.5.0; local build is 94. | Version is aligned in these surfaces. | P3 |
| Location behavior | Onboarding and older metadata say only at log time; privacy policy says background Pro checks use last-known coarse location. | Behavior copy should disclose the Pro background path consistently. | P1 |
| Terms renewal copy | `docs/terms.html:119` says `Manage or cancel in Settings, your name, Subscriptions.` | Grammatically broken and less actionable than the actual iOS path. | P2 |
| Support | `docs/support.html` covers permissions, weather, Watch queue, and export. | Missing purchase, trial, Restore Purchases, subscription, price, and refund guidance. | P2 |
| Privacy | `docs/privacy-policy.html:115-129` describes local data, Apple, and RevenueCat. | RC disclosure is intentionally not scored as a defect in this audit. | Excluded by request |

### Website findings

`docs/index.html:8-12` uses `Migraine Headache Tracker Log` in the title and a canonical URL on `jackwallner.com`. The JSON-LD at lines 23-60 repeats that name, advertises `$39.99` yearly and `$89.99` lifetime, and uses the older App Store path `migraine-headache-tracker-log`.

Recommended source-of-truth policy:

1. Choose the one public marketing URL that ASC should use, then redirect or canonicalize the other URL.
2. Use the current direct App Store path in README, JSON-LD, website buttons, review links, and all docs.
3. Remove hard-coded plan prices from SEO JSON-LD unless a release script updates them from the same catalog decision. Static price markup is currently wrong relative to observed production transactions.
4. If prices remain in JSON-LD, include a last-reviewed marker in the source and make the audit script fail when local and chosen production values differ.
5. Align the page title, hero, legal pages, support, onboarding, and App Store display name or explicitly state the relationship between the internal and consumer names.

### Privacy behavior copy outside the excluded RevenueCat issue

The current privacy page is more complete than the older README and metadata. It states that HealthKit data stays local, location can be sent to Open-Meteo, the app has no developer-owned server, and background requests use last-known coarse location. This is good evidence of the intended behavior.

The following older copy should be reviewed against that policy:

- `OnboardingView.swift:157-167` says location is used only to fetch weather and place labels when the user logs.
- `README.md` says location is used once per tap.
- `docs/app-store-metadata.md` says the only external request happens at the moment of a log.
- The App Store review information in `docs/app-store-metadata.md` describes only a log-time request.

The Pro background forecast path means those statements are incomplete. Update the eventual canonical copy to say that foreground logging uses current location and Proactive Alerts may use the last known coarse location for forecast checks, without claiming continuous tracking. Verify the App Store privacy answers and permission descriptions against the final behavior.

### Terms and support improvements

Fix the terms sentence to a precise platform path such as `Manage or cancel in Settings > [your name] > Subscriptions.` Verify the final Apple wording and do not hard-code a user-specific name in app copy.

Add a purchase section to support covering:

- What the free tier includes.
- Monthly, yearly, and lifetime differences.
- The exact seven-day trial and renewal price for the selected plan.
- How to cancel through Apple.
- Restore Purchases and what to do when the entitlement is delayed.
- Pending approval and parental-approval states.
- Apple refund routing.
- Contact support when a paywall has no products.

## Crash, regression, and watchdog audit

### Current observability evidence

No Crashlytics, Sentry, Firebase Crash Reporting, MetricKit, or equivalent production crash integration was found in the app source scan. `StoreService` has an `os.Logger` for purchase errors, and several services print errors in debug or directly, but there is no repository-owned alerting path and no normalized event schema.

The app can therefore have a live crash or user-visible failure without a signal in this codebase. ASC crash and diagnostics surfaces, TestFlight feedback, RevenueCat transaction data, and a later Mac watchdog must be treated as separate inputs.

### High-value signals to monitor

| Signal | Source or code path | Detection rule to scaffold | User impact |
| --- | --- | --- | --- |
| Crash-free sessions/users | ASC diagnostics, TestFlight, or chosen crash provider | Compare current version and build with prior release baseline; alert on statistically meaningful drop. | Immediate production regression. |
| Launch crash | `HeadacheModelStore.sharedModelContainer`, `HeadacheLoggerApp` initialization | Any launch crash or repeated launch failure by build/device/OS. | App cannot open. |
| Store corruption recovery | `HeadacheModelStore.swift:12-35` | Count store initialization failures, delete-and-retry paths, in-memory fallback, and fatal fallback. | Possible data loss or crash. |
| Initial save failure | `CaptureCoordinator.swift:100-107` | Alert on rate of `Could not save event. Try again.` above baseline. | Core one-tap promise fails. |
| Final save failure | `CaptureCoordinator.swift:139-146` | Alert on `Context captured but save failed` and pending row age. | User believes context was saved when it was not fully persisted. |
| Pending capture backlog | `CaptureCoordinator.pendingCaptureFetchDescriptor()` | Count rows pending longer than 15 minutes, 1 hour, and 24 hours. | Watch/widget or iPhone context never completes. |
| Partial/failed capture rate | `HeadacheEvent.captureStatus` | Compare complete, partial, failed, pending by build, permission state, device, and network status. | The app may appear unreliable even without a crash. |
| HealthKit query errors | `HealthKitService` | Count query failures by metric and authorization state. | Missing health context. |
| Open-Meteo/location errors | `EnvironmentService` | Count location denied, timeout, HTTP, parse, and unavailable results. | Missing weather or AQI context. |
| Product load with zero packages | `StoreService.fetchProducts()` | Paywall impression followed by zero products or empty offering. | Downloaded users cannot buy. |
| Pending purchase | `StoreService.purchase()` | Count pending results and time to entitlement resolution. | Trial and access state can be stranded. |
| Entitlement mismatch | `StoreService.apply(customerInfo:)` | Purchase completed but `HeadachePro` inactive after a bounded delay. | Paying user remains locked. |
| Restore failure | `StoreService.restorePurchases()` | Restore attempt without resolved status or with error. | Existing customer cannot recover access. |
| Trial start without entitlement | Offer attempt plus RevenueCat/StoreKit result | Alert when local trial-start state is true but no active entitlement exists after the wait window. | Funnel and access integrity failure. |
| Paywall dismissal after pending | Paywall state machine | Alert or test failure if pending closes without recovery copy. | User confusion and lost conversion. |
| Background task scheduling failure | `BackgroundRefreshService.swift:26-37` | Count submission errors and record last scheduled time. | Alerts silently stop. |
| Background task stale | `BackgroundRefreshService.swift:39-55`, `ProactiveAlertsEngine.runIfEligible()` | Alert when Pro with alerts enabled has no successful forecast check beyond the chosen SLA. | User misses a promised alert. |
| Notification permission denied | `ProAlertsConfigView` | Track enabled preference versus OS authorization state. | User thinks alerts are active when they cannot display. |
| Watch queue age | WatchConnectivity and App Group state | Alert on queued captures older than a threshold. | Wrist logging appears lost. |
| Review prompt collision | Root sheet state | Assert that review, trial, Pro intro, and paywall sheets are never simultaneously scheduled. | Poor UX and lower trust. |

### Immediate watchdog priorities

1. Add an explicit production crash source before relying on a Mac script. A Mac cannot infer a live user's crash from local app files alone.
2. Instrument purchase and capture state transitions with low-sensitivity fields and release/build identifiers.
3. Preserve evidence before deleting a corrupt SwiftData store. `HeadacheModelStore.swift:20-24` removes the store, WAL, and SHM files after the first failure. A safer implementation would move or copy the corrupt files to a bounded recovery location, record the failure, then rebuild only after preservation.
4. Add a last-successful-background-check timestamp and task result, stored locally for the settings UI and emitted through the selected safe telemetry path.
5. Build a release comparison report for build 94 against the prior production build over 0-24 hours, 24-72 hours, and 7 days.

### Release watch window

For each release, compare:

- Crash-free users and sessions.
- Launch failures and hangs.
- Product-load success.
- Paywall impressions with package counts.
- Purchase attempts by product and result.
- Pending transaction duration.
- Entitlement resolution latency.
- Restore success.
- Complete, partial, failed, and pending capture rates.
- Background forecast checks and alert sends.
- Watch/widget queue age.
- Support contacts and refund signals.

Segment each metric by app version/build, iOS version, device family, storefront, locale, and purchase surface. Do not use raw headache or HealthKit data for release monitoring.

### Mac watchdog scope for a later implementation

The broader requested Mac script should be a configurable scaffold only until an external data source and notification destination are chosen. It can safely automate:

- Reading exported ASC crash or diagnostic reports.
- Reading RevenueCat CSV or API exports.
- Reading a local app-generated event JSON or CSV stream.
- Computing release baselines and thresholds.
- Detecting price, metadata, URL, legal, and product-ID drift.
- Detecting paywall impressions with no products, pending purchase aging, and trial-state mismatch when those fields are exported.
- Sending an email after a user explicitly configures credentials and a destination.

It cannot detect a live crash from the Mac by itself unless the app or Apple service exports a crash signal to a source the script can read. The watchdog design should therefore keep ingestion adapters separate from rule evaluation and notification delivery.

No watchdog script was added in this focused audit because the requested write scope was only `audit823.md`.

## Agent documentation and repository hygiene

### What is working

- `AGENTS.md` is a symlink to `CLAUDE.md`, so the canonical app guidance is shared rather than duplicated.
- `CLAUDE.md` identifies the XcodeGen project, scheme, simulator lease owner, and global iOS conventions.
- `docs/app-store-review-strategy.md` is short and points to the review implementation symbols.
- The repository has scripts for ASC metadata, ASC state, ASO reports, TestFlight, and screenshot processing.

### What can confuse Cursor, Claude, or Codex

| Path | Evidence | Risk | Recommendation |
| --- | --- | --- | --- |
| `README.md` | Uses `Headache Logger`, an older App Store path, and a named `iPhone 17` simulator destination. | An agent may use stale naming or violate the current headless simulator pool rule. | Update URLs and commands or clearly mark the README as human-facing. |
| `CLAUDE.md` | Ten-line pointer with generic delegation rules and no current product/catalog table. | An agent knows the project name but not the current source of truth for pricing, live status, or docs. | Add a compact current manifest and canonical paths, without duplicating global policy. |
| `AGENTS.md` | Symlink is correct. | A future replacement could break shared guidance. | Preserve the symlink; do not copy it. |
| `.cursor` | No Cursor directory or Cursor-specific instructions found. | Cursor agents may discover stale README and archive notes without a current pointer. | Add a Cursor file only if the team wants Cursor-specific behavior; otherwise make README and CLAUDE sufficient. |
| `.claude/settings.local.json` | Permissions allow list is empty. | Not a product issue, but an agent may treat the file as authoritative project policy. | Keep harness-local settings out of product docs. |
| `.claude/scheduled_tasks.lock` | Contains a June 2026 process timestamp and session ID. | A stale lock can confuse scheduled automation. | Verify the owning process before removing or regenerating it; do not delete it as part of an audit. |
| `.commandcode/taste/taste.md` | Only a short generated heading. | It adds no current product guidance. | Keep generated taste notes separate from engineering source of truth. |
| `docs/app-store-metadata.md` | Heading and review notes still center v1.1.0 and old `One Tap` copy. | An agent may upload stale release notes or old product claims. | Move to a dated handoff/archive section and create a current metadata decision file. |
| `docs/astro-aso-metadata-proposal.md` | Uses old title/subtitle and commands `ASC_APP_VERSION=1.3.0`. | An agent may revert accepted 1.5.0 metadata. | Mark as historical experiment or move under an ASO archive. |
| `archive/*.md` | Multiple old findings and plans contain historical paths and symbols. | Broad search can surface obsolete implementation instructions. | Keep archive, but add a strong archive banner and a current index. |
| `claude-design/` | Design references and raw screenshots exist separately from current implementation notes. | An agent may treat design snapshots as current UI requirements. | Add date and status to design README and link the current runtime source. |
| `fastlane/metadata.bak.*` | Several timestamped metadata backups are present. | Automated searches can select a backup instead of the active tree. | Keep backups outside the active metadata path or document the selection rule. |

### Suggested agent-friendly structure

Do not implement this as part of the audit. The next documentation cleanup can use:

```text
CLAUDE.md                 short current app manifest and pointers
AGENTS.md                 symlink to CLAUDE.md
README.md                 human setup and current links
docs/current/             active product, release, legal, and support decisions
docs/audits/              dated audit artifacts
docs/handoffs/            dated implementation handoffs
docs/archive/             historical plans and superseded audits
fastlane/metadata/        active ASC payload only
archive/                  legacy location with an explicit archive banner
```

The current audit file is intentionally left at the requested repository path, `/Users/jackwallner/headaches/audit823.md`.

### Canonical-source table to add later

| Question | Canonical source |
| --- | --- |
| Product IDs and entitlement | `HeadacheLogger/Services/StoreService.swift` plus RevenueCat catalog review. |
| Local StoreKit test prices | `HeadacheLogger/Services/Products.storekit`, explicitly labeled test-only. |
| Live prices | ASC and RevenueCat production catalog decision, not static docs. |
| App Store metadata | `fastlane/metadata/` active tree plus ASC verification. |
| Public product name and URL | One chosen decision record linked from `CLAUDE.md`. |
| Privacy | `docs/privacy-policy.html` and ASC privacy answers. |
| Terms | `docs/terms.html` and Apple EULA link. |
| Support | `docs/support.html`, including purchase and restore troubleshooting. |
| Purchase state machine | `StoreService`, onboarding, root sheet, and PaywallView tests. |
| Release validation | `ios-dev` conventions, scheme StoreKit configuration, and current TestFlight procedure. |

## Prioritized backlog

### P0, fix before trusting trial or purchase metrics

1. Separate `.pending` from `.purchased` in onboarding, direct trial, and full paywall.
2. Do not complete onboarding or dismiss an offer from a pending result.
3. Do not complete onboarding merely because the fallback paywall was dismissed.
4. Dismiss a purchase surface only after the explicit Headache Pro entitlement is active or the user deliberately exits.

Acceptance: the pending validation matrix above passes on StoreKit Testing and on a real TestFlight purchase path where possible.

### P1, reconcile commercial truth

1. Decide intended yearly and lifetime price.
2. Align ASC products, RevenueCat, local StoreKit configuration, website JSON-LD, screenshots, terms, metadata, and tests.
3. Verify monthly and yearly introductory offers independently.
4. Decide whether the RevenueCat Components draft is used or retired.
5. Replace broad active-entitlement checks with the explicit `HeadachePro` entitlement.

Acceptance: one catalog table produces the same product IDs, trial eligibility, and price expectations in native paywall, StoreKit tests, website checks, and release documentation.

### P1, make the funnel measurable

1. Add source, package, selection, attempt, cancellation, pending, entitlement, restore, and error state transitions.
2. Add safe app/build/storefront/locale and value-maturity attributes.
3. Add product-load success and zero-product diagnostics.
4. Preserve exposure state separately from completion state.

Acceptance: a trial or purchase can be traced from surface to product selection to final entitlement without medical or free-text data.

### P1, make background and persistence failures visible

1. Add a crash source or an ASC/TestFlight ingestion path.
2. Count store recovery and preserve corrupt-store evidence before deletion.
3. Add capture status and pending-age reporting.
4. Add last successful background forecast check and task result.
5. Add release-over-release thresholds and a configured email or other notification adapter later.

Acceptance: the watchdog can detect the top signals from exported data without AI and produce a report with build and time-window context.

### P1, align public behavior copy

1. Align name and App Store URLs.
2. Align canonical website URL and JSON-LD.
3. Update prices and trial language.
4. Explain Pro background forecast location use consistently.
5. Add purchase and restore support guidance.

Acceptance: a user reading ASC, the site, privacy, terms, support, onboarding, and paywall sees one coherent product and billing explanation.

### P2, optimize acquisition and experience

1. Test title spacing after checking current ranking and version constraints.
2. Run a controlled keyword experiment instead of copying stale ASO proposals.
3. Test screenshot first-frame and Pro-value narratives.
4. Test monthly versus yearly default and source-specific paywall framing.
5. Verify accessibility and decide a UI localization strategy.

### P2, organize agent context

1. Add a current app manifest to `CLAUDE.md`.
2. Mark v1.1.0 and v1.3.0 documents historical.
3. Add archive banners and current-doc pointers.
4. Update README simulator and App Store commands to current fleet conventions.
5. Document active metadata selection so backups cannot be mistaken for source.

## Validation plan for the implementation agent

### Purchase and trial validation

- Use the scheme's StoreKit configuration for simulator testing. Do not configure the production RevenueCat key on a simulator.
- Exercise monthly, yearly, lifetime, eligible trial, ineligible trial, cancellation, pending, approval-after-pending, restore, network failure, offering-empty, and entitlement-delay cases.
- Test onboarding exit, fallback paywall dismissal, first-log prompt, existing-user prompt, Patterns fallback, Home milestone, Settings, and History entry points.
- Verify `hasCompletedOnboarding`, offer exposure state, trial attempt state, and Pro entitlement after every case.
- Test native paywall and RevenueCat Components only according to the chosen ownership decision.
- On a physical or TestFlight device, verify the actual RevenueCat product and price, because simulator values come from `Products.storekit`.

### Metadata and website validation

- Pull current ASC metadata before editing and compare every active locale with `fastlane/metadata`.
- Check Unicode character counts for name, subtitle, and keywords.
- Check all links for status, redirect count, canonical target, and App Store app ID.
- Parse website JSON-LD and compare product IDs, prices, currency, version, title, and App Store URL with the chosen catalog decision.
- Compare terms, privacy, support, onboarding, paywall, App Store description, and review notes for trial, renewal, location, data handling, and medical disclaimer language.
- Confirm the selected public name in title, hero, legal pages, support, and metadata.

### Funnel and watchdog validation

- Export or query ASC and RevenueCat data for a fixed release window.
- Reconcile purchase attempts, trial starts, active entitlements, trial endings, conversions, cancellations, and refunds.
- Confirm no pending result is counted as a completed trial.
- Confirm paywall impressions with zero products are visible.
- Confirm capture pending rows, partial statuses, and alert task results are represented in the watchdog input.
- Test a synthetic bad-release fixture containing a price mismatch, stale URL, missing product, pending purchase, and crash spike. The non-AI checker should flag all of them with file or source evidence.

### Agent documentation validation

- Ask a fresh Cursor, Claude, or Codex session to identify the current product name, bundle ID, ASC ID, RevenueCat project, product IDs, live price source, simulator procedure, and legal URLs using only the current root pointers.
- Confirm that the session does not select `docs/astro-aso-metadata-proposal.md`, `docs/app-store-metadata.md` v1.1.0, or an `archive` note as current instructions.
- Confirm that the session understands the audit artifact is read-only evidence, not an implementation plan that has already been applied.

## Decisions to resolve before implementation

1. Which yearly and lifetime prices are intended for production: the observed RevenueCat values or the local and website values?
2. Should onboarding start the monthly trial, the yearly trial, or only present the trial after the first successful log?
3. Is the native SwiftUI paywall the permanent source of truth, or should RevenueCat Components be adopted?
4. Are the 50 ASC locale directories intended to be live now, or is English-only the launch decision?
5. Which public name and URL should all site, metadata, legal, and agent surfaces use?
6. Should the Pro background forecast use of last-known coarse location be stated in onboarding, support, review notes, and App Store copy?
7. Which external crash and transaction data source will the later Mac watchdog ingest?

## Uncertainties and not accessed

- ASC per-localization edit and approval states were not fully enumerated through the visible analytics view.
- ASC historical download, trial, and product-page cohorts were not available as a complete export in this read-only pass.
- RevenueCat funnel charts were not fully loaded, so no source-level conversion rate is claimed.
- The public App Store screenshot pixels were not treated as current evidence for exact screenshot copy or ordering.
- No live simulator or TestFlight purchase run was performed. This was a source and available-dashboard audit only.
- No production crash report feed was available in the repository or visible context. The watchdog section therefore defines required inputs and rules rather than reporting a measured crash spike.
- Browser inspection was read-only. No ASC, RevenueCat, App Store, website, or repository settings were changed.

## Appendix: exact evidence paths and symbols

### Purchase and paywall

- `HeadacheLogger/Services/StoreService.swift:6-16`, product IDs and entitlement names.
- `HeadacheLogger/Services/StoreService.swift:79-90`, full-paywall ordering.
- `HeadacheLogger/Services/StoreService.swift:147-150`, broad entitlement check.
- `HeadacheLogger/Services/StoreService.swift:153-208`, onboarding package, CTA, disclosure, and savings calculation.
- `HeadacheLogger/Services/StoreService.swift:299-323`, configuration and product fetch.
- `HeadacheLogger/Services/StoreService.swift:326-360`, purchase result mapping.
- `HeadacheLogger/Services/StoreService.swift:363-380`, entitlement refresh.
- `HeadacheLogger/Services/StoreService.swift:433-443`, intro eligibility.
- `HeadacheLogger/Services/StoreService.swift:451-465`, custom paywall impressions.
- `HeadacheLogger/Views/PaywallView.swift:117-234`, native paywall content and legal footer.
- `HeadacheLogger/Views/PaywallView.swift:273-346`, CTA, disclosure, restore, and purchase result handling.
- `HeadacheLogger/Views/OnboardingView.swift:20-54`, onboarding shell, product prefetch, fallback paywall.
- `HeadacheLogger/Views/OnboardingView.swift:210-326`, trial page, seen flag, direct purchase, and pending handling.
- `HeadacheLogger/HeadacheLoggerApp.swift:277-325`, review scheduling.
- `HeadacheLogger/HeadacheLoggerApp.swift:413-543`, first-log, existing-user, Patterns, and direct trial flows.
- `HeadacheLogger/HeadacheLoggerApp.swift:547-620`, Pro intro and full-paywall sheet.
- `HeadacheLogger/HeadacheLoggerApp.swift:640-918`, trial offer sheet and billing disclosure.
- `HeadacheLogger/Services/Products.storekit`, local test catalog and prices.

### UX, review, persistence, and alerts

- `HeadacheLogger/Services/CaptureCoordinator.swift:20-78`, pending and widget/watch re-enrichment.
- `HeadacheLogger/Services/CaptureCoordinator.swift:80-168`, immediate save and asynchronous enrichment.
- `HeadacheLogger/Services/HeadacheModelStore.swift:12-35`, store recovery, deletion, memory fallback, and fatal fallback.
- `HeadacheLogger/Services/ReviewPromptTracker.swift:28-155`, review thresholds, cooldown, and outcomes.
- `HeadacheLogger/Views/ReviewPromptSheet.swift:103-256`, enjoyment, review, feedback, and mail flow.
- `HeadacheLogger/Views/InsightsView.swift:20-245`, locked and Pro insights paths.
- `HeadacheLogger/Views/ProAlertsConfigView.swift`, alert permission, readiness, thresholds, and test alert UI.
- `HeadacheLogger/Services/BackgroundRefreshService.swift:4-55`, background scheduling and execution.
- `HeadacheLogger/Services/InsightsEngine.swift:8-11`, five-event insight threshold.
- `HeadacheLogger/Services/ProactiveAlertsEngine.swift:514-517`, personal alert sample thresholds.

### Public and agent documentation

- `fastlane/metadata/en-US/`, current local App Store metadata.
- `fastlane/Deliverfile`, supported delivery locale list.
- `README.md:9-53`, stale public URL and simulator command evidence.
- `CLAUDE.md`, current app pointer and project identity.
- `docs/index.html:8-60`, title, canonical, JSON-LD, price, and App Store URL evidence.
- `docs/privacy-policy.html:86-145`, current privacy and RevenueCat disclosure.
- `docs/terms.html:90-125`, medical and billing terms, including the grammar defect.
- `docs/support.html:65-105`, current support scope.
- `docs/app-store-metadata.md`, v1.1.0 handoff and review information.
- `docs/astro-aso-metadata-proposal.md`, older title, subtitle, and v1.3.0 command.
- `docs/app-store-review-strategy.md`, review funnel decision notes.
- `.claude/settings.local.json`, `.claude/scheduled_tasks.lock`, `.commandcode/taste/taste.md`, agent-tooling files.

### Live surfaces inspected

- Public App Store listing: `https://apps.apple.com/us/app/migraine-tracker-headache-log/id6762074561`
- App Store Connect app: app ID `6762074561`, app list and analytics surfaces.
- RevenueCat project: `https://app.revenuecat.com/projects/9f4317d7/overview`
- RevenueCat product catalog: `https://app.revenuecat.com/projects/9f4317d7/product-catalog`
- RevenueCat paywalls and builder for the `Headache Pro` offering.
- RevenueCat experiments: no experiments visible.
- Published website: `https://jackwallner.github.io/headaches/`
- Published privacy, terms, and support paths under the same GitHub Pages site.

## Final audit conclusion

The app's acquisition story is credible: one-tap capture, automatic context, Apple Watch and widget entry, personal patterns, alerts, and local-first trust. The next implementation pass should start with purchase-state correctness and commercial source-of-truth reconciliation. Once those are fixed, safe funnel attributes and release watchdog inputs will make the remaining paywall and metadata experiments measurable instead of speculative. Documentation cleanup should happen alongside those changes so future Cursor, Claude, and Codex sessions use the current product, price, URL, and validation rules.
