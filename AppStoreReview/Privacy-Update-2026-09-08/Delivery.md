# Privacy update — September 8, 2026

The updated public policy is live at https://nanobeasts.app/privacy. A fresh browser load verified the September 8 date and all thirteen sections, including GPS/fog, WatchConnectivity, Apple Health, selected photos, route video export, purchase analytics, local notifications, retention, and deletion. The site keeps its existing layout and navigation.

Only `privacy.html` changed in the existing website repository `twosyntaxerrors/nanobeasts-landing`. Published commit: `039e86e6939a0c7c1140c019f96774f4a4a09f6c`. The update was prepared in an isolated checkout; the owner's original website checkout was not modified. The previous and published HTML, structured text, and readable Markdown copy are retained in this directory.

The App Store disclosure preparation file `AppStoreReview/Privacy-Answers-2026-09-07.md` now includes Purchase History for **Analytics and App Functionality**, following RevenueCat's current guidance. It also documents local route handling, sharing, and the newer file-timestamp manifest reason. The App Store Connect questionnaire itself is not yet published or verified: the browser requires Apple sign-in. A sign-in request is pending; no app upload or review submission is involved.

Data-flow evidence: `Nanobeasts/App/NanobeastsApp.swift` (anonymous RevenueCat configuration); `Services/HealthKitClient.swift`, `Services/WorkoutSessionTracker.swift`, `Services/WorkoutHealthSync.swift` (Health access); `Services/WorkoutLocationTracker.swift` (map preparation, background workouts, local route/territory archives); `Services/WorkoutWatchBridge.swift` and `NanobeastsWatch/WatchWorkoutRecorder.swift` (paired-device transfer); `Features/Settings/WorkoutShareView.swift`, `WorkoutRouteReplayView.swift`, and `WorkoutReplayVideo.swift` (photo selection and local sharing); `Models/AppStore.swift` (local state and gameplay reset); `Services/RemoteArtwork.swift` (CDN requests).

The public policy describes app behavior; the disclosure preparation distinguishes that behavior from unverified external provider configurations. It makes no claim of publishing the ASC privacy label or proving all third-party retention policies. Relevant references: [RevenueCat App Privacy](https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy), [Apple App Privacy](https://developer.apple.com/app-store/app-privacy-details/).

No app source, pricing, paywall model, purchase product, device installation, or binary upload was changed during this update.
