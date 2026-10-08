# Workout device integration

The iPhone app includes a native watchOS companion. Start a walk, run, or hike
from Nanobeasts on either device. The iPhone's **Start on Apple Watch** button
requests a Watch-owned workout and shows its live measurements and controls.
For that session, only the Watch saves to Health. Do not also start Apple Workout.

Nano's Watch flow uses workout cards, a cancellable three-second countdown, and
a central metrics page modeled on the user's Apple Workout reference video.
Swipe right for pause/resume and finish controls; swipe left for pace, heart rate,
and calories, then again for GPS status. Time, steps, and distance use the main
page. Elapsed time comes from HealthKit, with a one-second visible clock refresh. Pausing freezes the clock. Average pace uses active duration and
measured distance, and stale heart-rate readings display a placeholder. The
recording service runs independently of the selected page.

The Watch records GPS during an active outdoor workout with the wrist lowered.
The phone records GPS during an active outdoor phone workout with the screen
locked. GPS route capture requires location permission and precise location. On Watch, GPS routes are optional; a denied permission still allows the workout to continue. Pauses and GPS
outages create separate route segments rather than invented connecting lines.
Health saving is optional and configured separately on each device.

Completed Watch workouts and their original route samples queue on the Watch
until WatchConnectivity can transfer them. Stable session IDs make repeat
transfers safe. Nanobeasts keeps a local result and route even if Health saving
fails. Health workout imports also preserve the originating Nanobeasts session
ID, so an exported workout does not become a second history row.

Import History enables subsequent automatic Health refreshes. Third-party watch
workouts are available only after their companion app writes them to Apple
Health and the user grants Nanobeasts read access. This is not direct support
for starting a workout on every watch brand. Garmin's Activity API requires
developer-program approval and a consented Garmin Connect integration for full
activity files; it has not been implemented here.

## Physical-device acceptance checks

1. Provision the paired Apple Watch in Xcode, enable Developer Mode, and install
   the NanobeastsWatch target. Installing the iPhone app alone does not verify
   that the Watch is provisioned or that its app runs.
2. Start a short outdoor workout from Nanobeasts on the Watch, approve Health,
   Motion, and Location requests, lower the wrist, and lock the iPhone.
3. Pause, move to a different location, resume, and finish. Confirm one history
   session, the original route, and a gap across the pause. Share the route.
4. With Health saving enabled, check Apple Health and Fitness for the saved
   workout and energy. Ring credit is determined by Apple Health/Fitness.
5. Repeat using Start on Apple Watch from the iPhone; verify remote pause,
   resume, and finish. Repeat with the phone disconnected, then reconnect and
   verify queued history and route delivery without a duplicate.
6. Test an iPhone-only workout with the screen locked, then import Health history
   twice and verify the session count and steps do not increase.

## Current verification

On September 5, 2026, the combined signed iPhone/Watch build passed. After
refreshing the Mac's pairing service and enabling Developer Mode on the Watch,
the update was installed on the physical Apple Watch SE running watchOS 26.6
and installed in place on the paired iPhone. Both apps launched successfully.
The user subsequently completed a Watch walk and confirmed the route was recorded
correctly. Pause/resume gaps, disconnected transfers, live mirroring, and ring
credit still need the dedicated acceptance checks above.

Regression scripts cover history reconciliation, GPS filtering and persistence,
share exports, long Watch route transfers, repeat delivery, and stale history
screens receiving concurrent saves:

```sh
python3 Scripts/verify_workout_history.py
python3 Scripts/verify_workout_routes.py
python3 Scripts/verify_workout_exports.py
python3 Scripts/verify_watch_workout_sync.py
```

References:
- https://developer.apple.com/documentation/HealthKit/building-a-multidevice-workout-app
- https://developer.garmin.com/gc-developer-program/activity-api/

## Workout photo sharing

The September 5 share editor uses one movable block: white Distance, Steps,
and Time, an orange route silhouette, and a small NANOBEASTS wordmark. The
previous growth panel and top badge are removed. Its “Energy” value represented
active calories in kcal; it is no longer included in the export.

Choose a photo or camera image, drag the block, and pinch anywhere on the preview
to resize the stats and route together. Dragging and pinching can work together;
each pinch starts from the current size and stays within the existing size limits.
Arrow buttons and the size slider provide an accessible alternative. Reset restores the
initial placement. Preview and PNG use the same normalized placement and clamp
content inside the canvas. Photo and route exports remain 1080×1920; transparent
PNG exports remain 1080×1350. The photo fills the portrait canvas as before.

The signed iPhone build passed. Eight actual SwiftUI export renders cover photo
orientations, moved/resized overlays, route backgrounds, and transparent PNGs;
placement checks cover size limits and preview/export agreement. The 37 route
regression checks passed. Touch interaction and photo-picker/share-sheet flows
should also be checked on the phone.

## September 6 walk feedback update

See [WalkIssueLog.md](WalkIssueLog.md) for the original reports, implementation,
and physical-walk acceptance checks. Watch Settings now remembers GPS routes,
auto-pause, milestone alerts, and Health saving. Step counting has priority on
the metrics screen, with Nano mint and existing Flarva artwork. The creature is
a decorative walking buddy in that version; the subsequent companion refinement
below replaces it with the current creature.

Motion-driven auto-pause uses 15 seconds of detected stationary activity and
3 seconds of detected walking/running to resume. Manual pauses stay paused.
Sensor latency and wrist-down behavior need a real walk; this does not claim
exact equivalence with Apple's Workout behavior. GPS loss alone never pauses.

Every 1,000 workout steps and each mile triggers a queued haptic / creature
celebration. Mile splits use interpolated distance crossings and HealthKit
active time. Optional checkpoint fields preserve pause ownership and milestone
progress while retaining compatibility with existing Watch transfers.

Run the new production-policy regression suite with:

    python3 Scripts/verify_watch_feedback.py

[WatchWalkPreview.png](WatchWalkPreview.png) shows rendered production metrics
and milestone views at 40 mm and 44 mm Watch SE dimensions, using fixtures.
These are layout renders, not photographs or screenshots from the Watch.

The final combined signed build passed and was installed in place on the
physical iPhone 12 and Apple Watch SE on September 6. CoreDevice confirmed
successful launches on both. All 80 motion/milestone, Watch sync, and route
regression checks passed. The real-walk acceptance checks remain pending.

## Current-creature and readability refinement

The Watch's start screen and step/mile milestones now use a PNG of the current
creature (or egg). iPhone prepares a bounded thumbnail from the existing static
artwork URL and sends its identity, name, revision, and image together using
WatchConnectivity application context. Foreground requests refresh it promptly;
the Watch persists the image for disconnected use. New creature metadata clears
the old image while loading, and delayed older messages cannot overwrite a new
creature. An unsynced Watch shows a sync symbol instead of an unrelated creature.

Workout metrics use 30–32 point default values with single-line labels. The main
page shows active time, steps, and distance; the adjacent effort page shows
average pace, heart rate, and active calories. A compact navigation title gives
the numbers room. Dynamic Type can place a whole unit label below its value,
and very large content can scroll rather than clip or wrap individual words.

Native 40 mm Watch simulator screenshots cover main metrics, effort, milestones,
and larger text in `WatchCompanion/`. Simulator-only debug preview arguments
render the production views without requesting Health access or recording
synthetic workouts. Normal physical-device builds cannot activate these fixtures.

The final signed build passed; 32 feedback/artwork checks and 17 Watch sync checks
passed. The final iPhone update was installed in place and launched; the final
Watch update was installed directly after its connection recovered. Watch launch
verification remains pending because the connection dropped again with network
error 60 / tunnel handshake timeouts. Wake and unlock the Watch with Wi-Fi enabled
and keep it near the iPhone before retrying; it can also be opened manually.

Empty session handling: a workout needs a positive step count, finite positive distance, or finite positive active calories. Elapsed time alone does not qualify. The iPhone discards an empty session before rewards/history/Health saving; the Watch discards its Health builder and reports that nothing was saved. History filters empty rows after reconciliation so Health imports and Watch retries cannot reintroduce them. Existing Health records are not deleted; the local history migration retains its existing backup behavior.

Calendar daily reports use a collapsed native disclosure group for workouts, with the count visible. Opening another day resets it to collapsed.

Validation for empty sessions and Calendar collapse: signed device build passed; history reconciliation and Watch sync regressions passed, including five new activity-policy checks. Installed in place and launched on the physical iPhone 12. Direct Watch installation initially failed with CoreDevice error 4000 / CBErrorDomain 15 (encrypted connection timeout); requires a reachable, unlocked Watch for retry.

Watch delivery resolved: subsequent retry successfully installed the signed Watch app in place and verified launch on the physical Apple Watch SE. Empty-session protection is now delivered to both devices.

## September 7 outdoor walk interface

The outdoor walk main page now pairs the current creature with workout steps and
a horizontal bar toward the next 1,000-step milestone. Active time and distance
remain on that page; pace, heart rate, calories, GPS, and workout controls retain
their existing pages. See [OutdoorWalkReview.md](WatchCompanion/OutdoorWalkReview.md)
for the progress semantics, native screenshots, and verification.

Both final signed builds and 54 feedback/artwork/progress and sync checks passed.
The final iPhone app was installed in place and launched. Direct Watch delivery
initially encountered a CoreDevice network tunnel timeout. The user's September
7 retry succeeded: the final signed Watch app installed in place on the physical
Apple Watch SE, and CoreDevice confirmed launch at 09:55:58 local time. The update
is now delivered and launch-verified on both devices.

## Today home screen refinement

The user's subsequent correction makes Today the Watch entry screen, with the
current creature, daily steps, the personal daily-goal bar, distance, active
calories, and a direct Outdoor Walk button. More workouts opens the existing
picker/settings. Starting a walk switches to the existing live recorder and
metric pages; opening the app alone does not record an activity.

See [TodayHomeReview.md](WatchCompanion/TodayHomeReview.md) for data sources,
permission handling, screenshots, and validation. Both final builds, signatures,
and 63 regression checks passed. The latest Today revision installed in place
on the physical iPhone 12 on the subsequent user retry; CoreDevice confirmed
launch at 10:56:31 on September 7. Watch delivery subsequently succeeded after
restarting the Mac's user-owned CoreDeviceService and remotepairingd processes
to clear an encrypted connection timeout. The final Watch app installed directly
in place on the physical Apple Watch SE, and CoreDevice confirmed launch at
11:03:43. This Today-home revision is now installed and launch-verified on both
devices; no app was uninstalled and no synthetic workout was recorded.

## Location persistence follow-up

Corrected the Watch background-location mode, enabled background GPS updates, and
added foreground recovery for approved active outdoor routes. Settings now reports
actual location/precision authorization; the saved GPS routes switch is retained.
Home and workout Health permission sheets share a cancellable serialized queue.
See [LocationPersistenceReview.md](WatchCompanion/LocationPersistenceReview.md) for
the OS authorization boundaries, 117 passing regression checks, simulator restart
verification, and physical delivery status. The update installed in place and
launched on both devices. The Watch launch retry succeeded at 13:02:41 after its
initial Locked error. Its permission diagnostic confirmed When In Use access,
full accuracy, GPS routes on, and background updates enabled. The user's unlocked
Watch retry resolved the physical restart check: the app installed in place and
launched at 13:35:21, then restarted successfully at 13:35:57 with a new process ID.
Location authorization, precision, GPS preference, and background configuration
were unchanged. Simulator and physical restart checks passed; real-walk
permission-loop acceptance remains pending.
