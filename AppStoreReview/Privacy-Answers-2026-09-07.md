# App Privacy preparation

Updated September 8, 2026 for route replay/video sharing and the Build 10 onboarding changes. See `Privacy-Update-2026-09-08/` for the updated public policy and supporting data-flow notes.

The native app uses RevenueCat's anonymous customer identity to manage subscriptions. Its bundled SDK manifest declares purchase history for app functionality, not linked to identity and not used for tracking. No player name, Health samples, GPS routes, or workout measurements are passed to RevenueCat by Nanobeasts.

| App Store privacy field | Answer supported by the current build |
| --- | --- |
| Data collected | Purchase History, through RevenueCat |
| Purpose | App Functionality (subscription entitlement and restoration) and Analytics (RevenueCat customer history, charts, and experiments) |
| Linked to identity | No, for the current anonymous RevenueCat integration |
| Tracking | No |
| Health, fitness and precise workout location | Used on the user's iPhone/Watch and in Apple Health; no app-operated upload of those samples |
| Notification preference and onboarding draft | Name, answers, consent, saved position, and bounded setup-reminder schedule stay locally; local notifications, no remote push service |

RevenueCat's current Apple App Privacy guidance says all RevenueCat users must select both App Functionality and Analytics for Purchase History. This corrects the earlier document's treatment of Analytics as optional. Reassess these answers before adding login, customer attributes, attribution, crash-reporting, or other analytics services. Anonymous identity and no tracking assume no identifying customer attributes or advertising integrations are configured outside the app; inspect those integrations if they are changed.

These answers are a prepared disclosure, not a claim that the App Privacy questionnaire has been published. The public App Store Connect API cannot publish or reliably verify it. The browser reached Apple's sign-in page, so the published questionnaire still needs an authenticated browser check.

App-owned privacy manifests are included for iPhone, Watch, and the widget extension. UserDefaults reasons are CA92.1 for private app preferences and 1C8F.1 for the iPhone/widget shared App Group. RevenueCat and SDWebImage retain their own manifests. The iPhone manifest also declares FileTimestamp reason C617.1 for video-export cleanup within the app's container.

GPS coordinates, workout measurements, checkpoints, and explored-map history are used locally and transferred between the paired Watch/iPhone through Apple services. Apple Health can retain authorized samples independently. Replay videos are rendered locally and sent only when the user chooses a destination in the system share sheet; user-initiated disclosure and local processing are distinct from automatic developer collection. Map requests and artwork delivery use Apple and content-delivery services. Do not equate this with an unconditional claim that every service receives no technical data: hosting/CDN request-log retention and any external RevenueCat integrations should be reflected if their configured practices expand collection.

The public policy explains local files, Apple Health retention, independent copies on paired devices, temporary exports, selected photos, and user-chosen share destinations. Resetting gameplay does not delete every workout/route or cancel purchases. Completed export files older than 24 hours are eligible for cleanup on a later export; they are not guaranteed to disappear exactly 24 hours after creation.

Sources: [RevenueCat App Privacy](https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy), [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/), [Apple required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

Build 10 adds separately disclosed setup reminder consent, five distinct local notifications spaced two days apart, and opt-out during setup/paywall as well as Settings. Trial activation/purchase/completion cancels the campaign. The public policy’s notification paragraph was expanded and verified in Brave to describe these setup reminders (website commit 1b8831b). No HealthKit data is used to personalize campaign messages.
