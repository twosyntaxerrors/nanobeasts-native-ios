# Nanobeasts walk issue log

Captured September 6, 2026, from a walk with the Nano Apple Watch companion.

## WALK-001 — Repeated location / GPS permission requests

**Reported:** Starting an outdoor walk asks for location and route access every time, even after acceptance. Keep the choice and allow changes in Settings. A temporary authorization may ask again after it expires.

**Implemented:** Ask Core Location only while authorization is undetermined. Ask Health only when its authorization-request status says a prompt is needed; request route sharing only when both GPS routes and Save to Health are enabled. Add persistent Nano Watch Settings for GPS routes, auto-pause, milestone alerts, and Health saving. Denied location no longer prevents a workout.

**Permission behavior:** Nanobeasts cannot extend Apple's Allow Once permission or re-prompt after a system denial. Choose Allow While Using App for ongoing access; change a denial in Watch Settings → Privacy & Security → Location Services. Permission-loop reproduction and two consecutive walks still need on-device acceptance testing.

**September 7 follow-up:** The GPS switch was already stored persistently. Corrected a separate background-location configuration defect: `location` was incorrectly in `WKBackgroundModes`, and `allowsBackgroundLocationUpdates` was never enabled. Location is now declared in `UIBackgroundModes`, with background updates enabled. Foreground return restores an approved, interrupted outdoor route without changing the switch or asking again; paused, indoor, finished, route-disabled, and saving sessions cannot restart GPS. Settings explains the actual authorization/precision state instead of repeating permission instructions to an already-authorized user. Home and workout Health authorization checks now share a cancellable queue to avoid overlapping or stale sheets. Actual system authorization is still queried each time; grants are not invented or cached as permanent.

## WALK-002 — Route error after forgetting to end the walk

**Reported:** After returning home, sitting, and showering, finishing showed “Route recording: The operation couldn’t be completed. kCLErrorDomain error 1.”

**Implemented:** Error 1 is Core Location's denied error. Stop that location stream, keep the workout and collected route, and explain how to restore permission. Ignore late location errors after pause or finish. Separate GPS notices from workout-save failures. Resume an authorized stream with a new route segment when permission returns. Poor or missing GPS never triggers automatic pausing.

**Acceptance:** Revoke location during a walk, finish successfully, confirm recorded route retained. Restore permission and confirm separated route segments. Test indoors after an outdoor walk. The original permission loss has not yet been reproduced.

**September 7 follow-up:** A Core Location denied error no longer automatically claims the user revoked permission. Nano rechecks the actual OS state, preserves the route, and treats an interrupted stream with valid permission as recoverable on foreground return.

## WALK-003 — Automatic pause and resume

**Reported:** The walk kept recording while stationary at home. It should pause automatically and resume when walking restarts.

**Implemented:** Core Motion activity and pedometer transition events drive automatic pause after 15 seconds of detected stationary activity, and resume after 3 seconds of detected walking/running. Brief stops and uncertain sensor data do not trigger it. Manual pauses do not auto-resume. Pauses stop step accumulation and route collection, preserve route gaps, and use HealthKit active time for pace and splits. Haptics and an Auto-paused label indicate transitions. Sensor timing varies by device; this is Nano's policy, not a claim of exact Apple Workout parity.

**Acceptance:** Outdoor walk → stop at least 30 seconds → walk again, with wrist lowered and phone locked. Repeat with a manual pause and no phone connection. Deny Motion access and check the explanation. Confirm active time, distance, steps, and route gaps in history.

## WALK-004 — Milestones during a walk

**Reported:** Haptics and an animation for 1,000 steps and each mile, including mile split time.

**Implemented:** Workout-local 1,000-step and whole-mile thresholds. A haptic and seven-second dismissible creature celebration; simultaneous milestones queue. Mile splits use active time interpolated between distance samples. High-water marks and last split time checkpoint with the workout to avoid repeats across recovery. Catch-up alerts are bounded. Finish cancels pending celebrations. Reduce Motion disables the entrance spring.

**Acceptance:** Cross 1,000 steps and one mile, including near-simultaneous thresholds; test with wrist lowered, after pause/resume, and after recovery. Haptic delivery and real-walk split accuracy require the Watch.

## WALK-005 — Watch should feel like Nanobeasts

**Reported:** The companion is plain and does not reflect a pedometer / pocket-pet experience.

**Implemented:** Nano mint and dark surfaces, existing Flarva pixel artwork as a walking buddy, adventure language, prominent steps on the primary metrics page, and creature milestone celebrations. This artwork is decorative; it does not claim to be the user's selected pet or award unearned growth. The workout metrics clock refreshes once a second to avoid unnecessary 30 fps rendering.

**Acceptance:** Check legibility on Apple Watch SE, Settings scrolling, controls, paused state, and milestone dismissal. Follow-up opportunity: sync the user's current pet and actual growth progress from iPhone.

## Verification

- Production motion / milestone policies and backward-compatible snapshot decoding: 26 checks passed.
- Watch sync regressions: 17 checks passed.
- GPS, route persistence, and route export regressions: 37 checks passed.
- Combined signed iPhone and Watch build passed.
- Production metrics and milestone layouts rendered and inspected at 40 mm and 44 mm Watch SE dimensions; see [WatchWalkPreview.png](WatchWalkPreview.png).
- Final signed build installed in place on the user's iPhone 12 (iOS 26.6) and Apple Watch SE (watchOS 26.6), September 6, 2026.
- CoreDevice confirmed successful launch of both existing app bundle identifiers. No app was uninstalled.
- Real-walk acceptance checks above remain pending; installation and policy tests do not verify physical sensor timing, wrist-down haptics, or the reported permission-loop reproduction.
