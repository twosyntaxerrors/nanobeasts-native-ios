# Splash animation refinement — September 6, 2026

Applied the emil-design-eng and review-animations skills. Inspected all four
sampled frames from the user's 2.17-second iPhone recording. The old Path
connected its two arcs with a straight chord, making the dotted outline look
flattened as it rotated.

| Before | After | Why |
| --- | --- | --- |
| Two partial arcs in a single stroked Path | 48 separate round dots, equally spaced around one radius | A complete circle with no joining chord or uneven dash seam. AppRootView.swift:812 |
| Secondary ring scaled from fractional progress and snapped at each integer | One ring with fixed geometry and independent linear rotation | Keeps the silhouette stable throughout the morphs. AppRootView.swift:722 |
| 0.72 entrance scale with a 520 ms spring | 0.96 entrance scale with a 240 ms strong ease-out | A restrained, responsive introduction. AppRootView.swift:772 |
| Fractional node pulses and opposing X/Y warp | Small continuous sinusoidal pulse and unwarped interpolation | Eliminates stage-boundary jumps and unnecessary distortion. AppRootView.swift:899 |
| 460 ms morphs coupled to letter groups, with a 700 ms end hold | Four 240 ms morphs, 60 ms settling beats, 120 ms end hold | Preserves the evolution idea in a roughly 1.5-second introduction. AppRootView.swift:781 |
| Letter bounce, strong glow, and a haptic on every letter | 70 ms letter stagger, 180 ms opacity/color transitions, restrained glow, no launch haptics | Less distracting during repeated launches. AppRootView.swift:799 |
| 340 ms exit | 180 ms strong ease-out exit | Gets to the app quickly. AppRootView.swift:115 |
| Reduced-motion completion could run after task cancellation | 350 ms static version with cancellation checked before completion | Honors Reduce Motion and prevents stale completion callbacks. AppRootView.swift:764 |

## Performance

The circular ring is a separate static Shape animated by rotation. The small
144-point Canvas remains for the seven-node evolution morph; it is bounded to
the brief launch sequence and does not animate layout dimensions. No additional
media, dependency, or asset decoding was introduced. Device frame time has not
been profiled, so this review does not claim a measured performance improvement.

## Interruptibility and timing

The sequence uses structured tasks. Cancellation stops sleeps and the wordmark
child task, and skips completion. Entrance, individual morphs, wordmark reveals,
and exit are all under 300 ms. The total introduction is about 1.5 seconds;
the ring's 1.5-second linear movement accompanies that sequence.

## Origin, physicality, and cohesion

All dots share the same radius and center; no nonuniform scale is applied to the
ring. The selected Nano accent, cyan/white molecule nodes, wordmark, and
atom-to-organism story are retained. The shape responds to a non-square proposal
using the smaller dimension.

## Accessibility

Reduce Motion shows the final form without rotation, morphing, bounce, or pulse,
then uses the same short opacity exit. No repeated startup haptics remain.

**Decision: Approve.** No unresolved motion findings in this change.

## Verification

- Signed iPhone build, including the existing embedded companion, passed.
- Production mark rendered at progress 0, 0.5, 1.5, 3, and 4 for direct comparison.
- Full production splash layout rendered at 390 × 844 points using a final-state fixture.
- Review artifacts are SwiftUI renders, not screenshots from the connected phone.
- Physical iPhone installation and launch recorded below.

[Before/after stages](SplashAnimationComparison.png)
[Final splash layout](SplashAnimationPreview.png)

Source: [AppRootView.swift](../Nanobeasts/App/AppRootView.swift).

Installed in place on the connected iPhone 12 (iOS 26.6) at 11:41 AM.
CoreDevice confirmed successful launch of com.twosyntaxerrors.nanobeasts.native.
Existing app data was preserved; no uninstall was performed.
