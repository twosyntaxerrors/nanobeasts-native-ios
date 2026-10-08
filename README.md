# Nanobeasts for iOS

Nanobeasts is a native SwiftUI iPhone app that turns Apple Health step data into creature hatching and evolution progress.

## What is included

- Native SwiftUI tabs for Lab, Stats, Dex, and Settings
- The Professor Nano onboarding flow and a custom Nanobeasts paywall backed by RevenueCat
- HealthKit read authorization for `HKQuantityTypeIdentifier.stepCount`
- Historical HealthKit trends for analytics, with post-install steps isolated for badge and evolution progress
- Native workouts for HIIT, walking, running, cycling, hiking, and indoor cardio with steps, distance, energy, routes, HealthKit saving, and Live Activities
- Post-workout discovery recaps plus photo, route, and transparent-style 9:16 share cards
- Daily step history, live refresh, pedometer fallback, and HealthKit observer updates
- Persistent hatch/evolution progress backed by `UserDefaults`
- The original Nanobeasts creature-family JSON with transparent idle animations streamed from the existing Cloudflare R2 domain
- Native memory and on-disk caching for R2 artwork (48 MB memory / 256 MB disk ceiling)
- A Dex with discovered creatures plus obscured, non-identifying locked specimens
- Small and medium WidgetKit progress widgets backed by the shared App Group
- A complete Xcode project generated from `project.yml`

## Run

1. Open `Nanobeasts.xcodeproj`.
2. Select the Nanobeasts target and choose your Apple Developer team.
3. Run on an iPhone, then tap **Connect Apple Health**.

HealthKit returns meaningful step history on a physical device. The Simulator can build and launch the app, but it may have no step samples. Gameplay creature and egg artwork is fetched from `https://assets.nanobeasts.app`; the promotional win-back and streak artwork is bundled separately.

Animated artwork follows the same R2 convention as the React Native app:

- Creatures: `images/idle-animations-optimized/<name>-idle-animation.webp`
- Eggs: `images/egg-animations-optimized/<name>-egg-animation.webp`
- Tutorial egg: `images/egg-animations-optimized/tutorial-egg-animation.webp`

The SwiftUI app downloads these assets through SDWebImage and plays them in a transparent native `SDAnimatedImageView` using the libwebp coder. A static R2 image is shown only while the complete animation loads or if the animated request fails. The dismissal offer uses a separate bundled, smiling Glitchlet illustration so its mascot appears offline. The streak card composites a separate, reference-based Flarva expression edit inside its procedural animated fire. Promotional artwork is bundled for offline use and does not replace gameplay artwork.

RevenueCat must use a separate iOS app for the native bundle identifier,
`com.twosyntaxerrors.nanobeasts.native`. Set that app's public SDK key in
`REVENUECAT_PUBLIC_SDK_KEY` in `project.yml`, then configure the
native offerings with these packages:

- `nanobeasts_native_lifetime`: `$rc_monthly` backed by `nanobeasts_native_premium_monthly` ($4.99/month US), and `$rc_lifetime` backed by `nanobeasts_native_premium_lifetime` ($29.99 US)
- `nanobeasts_native_lifetime_winback`: `nanobeasts_native_premium_lifetime_winback` ($19.99 US)

The two lifetime products are non-consumables granting the `premium` entitlement permanently. Monthly is an auto-renewing subscription granting the same entitlement.
The native app selects these offerings explicitly. A small win-back popup appears when
someone closes the standard paywall, when both products are available and the
localized discount is lower. Prices displayed in the app always come from StoreKit.
Existing yearly purchases retain their access and restore support.
The shared current offering and React Native products remain separate.

Settings → Paywall Comparison opens the OG and new layouts without changing the
live purchase screen. Both use simulated US products ($4.99 monthly, $29.99 lifetime,
and the $19.99 dismissal offer); purchase and restore never call RevenueCat in
these previews. The new layout uses a creature evolution visual, shorter benefits,
an always-visible checkout at standard text sizes, and “Unlock Forever.” Its
lifetime comparison is derived from the same-currency monthly and lifetime prices.
Run `python3 Scripts/verify_paywall_preview.py` and
`python3 Scripts/verify_subscription_pricing.py` to check purchase isolation and billing copy.

To regenerate the project after changing `project.yml`:

```sh
xcodegen generate
```

The bundle identifier is `com.twosyntaxerrors.nanobeasts.native`. It is intentionally separate from the React Native app (`com.twosyntaxerrors.nanobeasts`) so both versions can be installed and tested side by side.

The widget extension uses `group.com.twosyntaxerrors.nanobeasts.native`. The app publishes a JSON snapshot and the current static creature frame to the shared container, then reloads the `NanobeastsProgressWidget` timeline.

## TestFlight distribution

Build and upload this native project directly through Xcode. Do not use EAS for the Swift app.

1. Open `Nanobeasts.xcodeproj` in Xcode.
2. Select **Any iOS Device (arm64)** as the run destination.
3. Choose **Product → Archive**.
4. In Organizer, select the new archive and choose **Distribute App → App Store Connect → Upload**.

EAS remains reserved for builds from the React Native repository unless explicitly requested.
