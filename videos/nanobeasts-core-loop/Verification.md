# Video verification

## Original 20-second version

- Matches the existing onboarding demo's 1080 × 1666 aspect and 20-second runtime.
- No Simulator used. No iPhone application build or App Store upload requested for this video draft.
- HyperFrames full check: zero lint errors/warnings, zero runtime errors/warnings, zero layout errors/warnings, zero motion errors/warnings. All 108 checked text combinations pass contrast.
- Five layout information notices occur only during the intentional 0.38-second Home→Evolution crossfade.
- Reviewed snapshots at Home, transformation, Devicore hold, fog replay, Field Dex, badge reveal, and loop return.
- Fixed GSAP immediate-render behavior on the loop-return tween so the first Home screen and headline are visible from frame zero.
- Catalog numbers match CreatureCatalog: Glitchlet #023, Devicore #024, Tutoria #001, Aquablossom #005.
- Illustrative progress: daily steps 4,680→5,000 and 320 remaining toward the current evolution. This does not represent the full species evolution requirement.
- Existing animated artwork is sampled deterministically from alpha-preserving spritesheets.
- Route clip comes directly from the app's existing example video export, compressed from 18 to 6 seconds. It includes the Devicore marker and final stats.
- Render uses a single worker to limit memory pressure.

## Final export

- Master rendered successfully: 20.000 seconds, 1080 × 1666, 30 fps, about 9.2 MB.
- Streaming MP4: H.264, yuv420p, no audio, fast-start metadata, 2,348,281 bytes (about 2.35 MB).
- Inspected a contact sheet extracted from the final master; the Home UI, actual evolution motion, recorded route playback, collection, and badge all render correctly.
- Current production reference: 24,092,694-byte HEVC MOV. The new streaming file is about 90% smaller at the same canvas size and duration.

## Revised 27-second version

- Greeting changed from Alex to Sinatra; original approved videos preserved.
- Added a seven-second segment at 14.65–21.65 seconds: Activity Stats and monthly calendar, a continuous scroll, then animated Step insights.
- Reproduces the current app's movement history, calendar, daily average, weekly bars, daily goal, prior-week comparison, total steps, and goal days.
- Illustrative values reconcile: the seven displayed days total 44,100 steps, average 6,300, and meet a 5,000-step goal on six days. The 126,150-step calendar total is below the 135,971 lifetime total.
- Full HyperFrames check passes with zero errors and zero warnings across lint, runtime, layout, and motion. All 143 text contrast checks pass WCAG AA.
- Thirty layout information notices are from intentional scene crossfades and clipped scrolling content. Snapshot review confirms the settled layouts remain readable.
- Inspected Sinatra's greeting, the monthly calendar, the completed insights chart, badge reveal, and loop return at their revised timings.
- Rendering uses one worker. No Simulator, application install, R2 replacement, or App Store upload is part of this video revision.

### Revised final export

- Master render succeeded in 3m 53s: 27.000 seconds, 1080 × 1666, 30 fps, 12,006,075 bytes.
- Optimized streaming MP4: H.264, yuv420p, no audio, fast-start metadata, 3,006,784 bytes (about 3 MB).
- Inspected six frames extracted from the actual optimized MP4, including Sinatra, evolution, fog playback, Activity Stats, Step insights, and the badge reveal. Output matches the intended scenes.
- Contact sheet: `renders/Revision-v2-Contact-Sheet.jpg`.
