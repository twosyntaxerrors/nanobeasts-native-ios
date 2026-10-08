# App Store readiness audit — September 7, 2026

Nanobeasts is close to a release candidate, but I would resolve the confirmed issues and complete production purchase and outdoor-workout validation before submitting it. Screenshots are only part of the remaining work.

This audit inspected the current source, built the Release configuration, inspected the resulting bundles and existing marketing assets, and checked current Apple requirements. App Store Connect opened at its sign-in page, so listing completeness, agreements, subscription status, and previous uploads could not be verified. No app source was changed, no distribution build was uploaded, and no device installation was performed for this audit.

## Confirmed issues to resolve

| Priority | Finding | Work needed |
| --- | --- | --- |
| Before upload | The iPhone app, Watch app, and widget extension have no app-owned `PrivacyInfo.xcprivacy`. The Release bundle contains only RevenueCat and SDWebImage manifests. Nanobeasts itself uses UserDefaults, including shared app-group defaults. | Add declarations for each target's own required-reason API usage, audit other covered APIs, and verify the manifests in the final archive. This is a likely upload blocker; an SDK's manifest is not a declaration of Nanobeasts' own code. |
| Before review | The only privacy and terms links found are on the paywall. Settings disables its paywall entry for Premium members. | Give every user a permanent Privacy Policy entry in Settings. Terms, Support, and Manage Subscription belong beside it. Apple specifically requires an easily accessible in-app privacy policy. |
| Before review | The July 5 public privacy policy describes steps and general activity but does not clearly explain the new optional GPS routes, workout heart rate, Watch-to-phone transfer, HealthKit route saving/import, or user-initiated route/photo sharing. Its broad statement about not transferring location needs clarification for these flows. | Update the policy to describe the actual features, optional permissions, storage, transfers, retention, deletion, and relevant vendors. Reconcile the App Store privacy answers with actual SDK and service practices. |
| Before review | The annual subscription badge is hardcoded to `SAVE 54%`, while nearby text calculates savings from current prices. Loading/error states display fixed US-dollar fallback prices. | Derive the badge from the loaded products and avoid presenting fallback prices as current offers. Preserve localized StoreKit pricing. |
| Before review | Onboarding offers hatch/evolution reminders and says they can be changed in Settings. The preference is persisted, but no hatch/evolution notification scheduler or Settings control was found. The notification code currently schedules workout inactivity prompts. | Implement and test the promised reminder behavior and control, or remove this promise and onboarding choice from the first release. |
| Release decision | The bundle identifier is `com.twosyntaxerrors.nanobeasts.native`; the README explicitly separates it from the original React Native app. The installed display name is `Nanobeasts Native`. | Confirm whether this is a new listing or a replacement for the existing Nanobeasts app. A separate identifier cannot serve as an update to the original listing. Resolve the identity, subscription configuration, and any migration needs before upload. Choose the intended customer-facing display name. |

Evidence locations:

- [Shared defaults](</Users/ervenstnoel/Documents/Nanobeasts Native/NanobeastsShared/WidgetSnapshot.swift>), [Watch defaults](</Users/ervenstnoel/Documents/Nanobeasts Native/NanobeastsWatch/WatchWorkoutRecorder.swift>), [app persistence](</Users/ervenstnoel/Documents/Nanobeasts Native/Nanobeasts/Models/AppStore.swift>), and [artwork cache file metadata](</Users/ervenstnoel/Documents/Nanobeasts Native/Nanobeasts/Services/RemoteArtwork.swift>).
- [Settings](</Users/ervenstnoel/Documents/Nanobeasts Native/Nanobeasts/Features/Settings/SettingsView.swift>), especially `SettingsProCard`; [paywall](</Users/ervenstnoel/Documents/Nanobeasts Native/Nanobeasts/Features/Paywall/RevenueCatPaywallScreen.swift>), including line 76 and the price helpers.
- [Reminder copy](</Users/ervenstnoel/Documents/Nanobeasts Native/Nanobeasts/Features/Onboarding/OnboardingFlowView.swift>), around line 459; `onboardingWantsReminders` in AppStore; [existing notification scheduler](</Users/ervenstnoel/Documents/Nanobeasts Native/Nanobeasts/Services/WorkoutLiveActivityController.swift>).
- [Build configuration](</Users/ervenstnoel/Documents/Nanobeasts Native/project.yml>) and [bundle identity rationale](</Users/ervenstnoel/Documents/Nanobeasts Native/README.md>).

Apple's [required-reason API guidance](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest) describes the manifest requirement. [Review Guideline 5.1.1](https://developer.apple.com/app-store/review/guidelines/#privacy) covers accessible policies and disclosure. Data used only on-device is not automatically “collected” for the store label: use Apple's [App Privacy definitions](https://developer.apple.com/app-store/app-privacy-details/) and [RevenueCat's disclosure guidance](https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy) when completing the answers. The installed RevenueCat manifest declares purchase history; do not assume the whole app qualifies for “Data Not Collected.”

## Validation still needed

**Purchases through TestFlight.** Debug uses RevenueCat Test Store; Release uses an Apple RevenueCat key. The separation is correct, but success in the development build does not validate App Store products. Verify monthly purchase, annual purchase, Restore Purchases, cancellation, expiration, and Premium state after relaunch. Check both native product IDs, the `premium` entitlement, the current offering, pricing, availability, and first-submission review metadata. Apple requires [first In-App Purchases to accompany an app-version submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/).

**Real workouts on both devices.** Existing project records report 117 passing permission, feedback, sync, and route regression checks. Physical iPhone and Watch installation/launch and Watch permission persistence across a process restart were previously verified. These checks were not rerun during this audit. The records explicitly leave two real consecutive outdoor walks and wrist-down route continuity pending. Complete those checks, including:

- No repeated authorization setup on the second walk after a persistent permission grant.
- Live stats with the wrist down and the phone locked; sensible GPS behavior in weak reception.
- Pause/resume, finish, interruption recovery, and Watch/phone disconnection and reconnection.
- A single saved workout/route and a single progression credit after sync; no duplicate records.
- Correct saved history and route sharing, including Photo Picker and system share sheet.
- Clear behavior when Health access or location is denied, location is approximate, or routes are switched off.

See [location persistence verification](</Users/ervenstnoel/Documents/Nanobeasts Native/Design/WatchCompanion/LocationPersistenceReview.md>) and [device integration history](</Users/ervenstnoel/Documents/Nanobeasts Native/Design/WorkoutDeviceIntegration.md>).

**Fresh-user and accessibility pass.** Use a separate tester or simulator without erasing the owner's data. Walk through onboarding, an empty Health history, permission refusal, free progression limits, first hatch/evolution, Premium restoration, and an interrupted network connection. Creature artwork relies on a CDN, so inspect fresh-install and cached-offline behavior. Check VoiceOver, larger text, Reduce Motion, smaller Watch screens, and representative older supported OS versions. These are validation gaps, not observed failures.

**Distribution validation.** Produce a signed App Store archive, inspect embedded Watch/widget entitlements and privacy declarations, validate it, and upload to TestFlight. Today's successful unsigned Release build establishes compilation, not App Store signing, processing, or review acceptance. Version/build values are currently `1.0.0 (1)`; choose an available build number based on the actual App Store Connect record.

## Screenshots and preview

The existing `AppStoreScreenshots/ASC-Ready-6.9` folder contains eight iPhone screenshots. All eight are RGB PNGs at 1290 × 2796, an accepted size for the 6.9-inch screenshot group. Two additional images would bring the set to ten:

1. An active outdoor workout with readable live measurements.
2. A completed workout with its route and sharing experience.

The Watch app needs its own screenshot set. I recommend its creature/Today's Steps home and an active outdoor walk. Existing `Today-home-44mm.png` and `OutdoorWalk-44mm.png` are 368 × 448, an accepted Watch size, but both PNGs contain an alpha channel. Export final opaque copies and verify that their UI matches the submitted build. The Watch slots are separate from the iPhone screenshot slots. Apple requires Watch screenshots and prohibits screenshot alpha channels; see [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

The existing `00-Nanobeasts-Full-App-Tour-ASC.mov` is approximately 27 seconds, 886 × 1920, 30 fps, H.264 High Level 4.0, and 34 MB. Those measured video properties fit Apple's published limits. It contains an AAC stereo track; complete the final audio and visual review and confirm upload processing rather than treating the filename as proof of acceptance. [App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications).

This audit checked asset metadata, not a full frame-by-frame comparison of every older screenshot and preview against today's app. Refresh any captures showing outdated controls or behavior.

## App Store Connect checks that remain unverified

- Correct app record and bundle ID; public name, description, subtitle, keywords, category, copyright, and supported territories.
- Privacy URL, Support URL, and accurate App Privacy answers, including third-party purchase processing and any retained service logs.
- Current age-rating questionnaire; truthful accessibility declarations where provided.
- Paid Apps agreement, tax/banking details, subscription group/products, availability, and subscription review information.
- Export-compliance answers; EU trader status if distributing in the EU.
- Review contact and clear reviewer notes: where to start an outdoor walk, how to use the companion app, why Health/location are requested, how to restore purchases, and how progression works. Explain that no account is required; do not invent reviewer credentials.
- Select the processed build, attach the first subscriptions if applicable, and choose the release timing.

The local Xcode 26.5 / iOS and watchOS 26.5 SDK build meets Apple's current Xcode 26 / SDK 26 upload minimum. [Current Apple requirements](https://developer.apple.com/news/upcoming-requirements/).

## What is already in place

- The combined Release build passed, including the embedded Watch app and widget extension.
- Health, location, motion, and camera purpose descriptions exist for the implemented features.
- Purchase/restore flows and separate development/Release RevenueCat configuration exist.
- Public Privacy, Terms, and Support pages returned HTTP 200 and their content was readable.
- A substantial iPhone screenshot set, a short app preview, Watch captures, and IAP review screenshots already exist.
- No login/account-creation system was found; adding an account system is not part of the release work identified here.

Recommended order: resolve the listing identity, fix the confirmed source/privacy issues, validate purchases and real workouts in the release candidate, finalize screenshots and metadata, then validate and submit the archive.
