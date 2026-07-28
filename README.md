# Nanobeasts for iOS

Nanobeasts is a native SwiftUI iPhone app that turns Apple Health step data into creature hatching and evolution progress.

## What is included

- Native SwiftUI tabs for Lab, Stats, Dex, and Settings
- The Professor Nano onboarding flow and a live RevenueCatUI paywall
- HealthKit read authorization for `HKQuantityTypeIdentifier.stepCount`
- Historical HealthKit trends for analytics, with post-install steps isolated for badge and evolution progress
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

HealthKit returns meaningful step history on a physical device. The Simulator can build and launch the app, but it may have no step samples. Creature and egg artwork is fetched from `https://assets.nanobeasts.app`; no creature artwork ships in the app bundle.

Animated artwork follows the same R2 convention as the React Native app:

- Creatures: `images/idle-animations-optimized/<name>-idle-animation.webp`
- Eggs: `images/egg-animations-optimized/<name>-egg-animation.webp`
- Tutorial egg: `images/egg-animations-optimized/tutorial-egg-animation.webp`

The SwiftUI app downloads these assets through SDWebImage and plays them in a transparent native `SDAnimatedImageView` using the libwebp coder. A static R2 image is shown only while the complete animation loads or if the animated request fails. The only app-owned raster bundled with the target is the native app icon.

RevenueCat uses the existing iOS public SDK key and the project's configured offering. Test purchases require the corresponding App Store sandbox products or a StoreKit test configuration.

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
