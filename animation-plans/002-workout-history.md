# History and Watch mirror implementation
Scope: Nanobeasts/Features/Settings/WorkoutHistoryView.swift and WatchWorkoutPanel.swift only. Root implements sharing; do not edit WorkoutShareView.swift. Native SwiftUI17+, use existing NanoTheme and Aldrich/SpaceMono. Do not change history persistence/reconciliation, transfers, or Health importing logic.
- History share: remove startsOnRoute parameter; use WorkoutShareComposer(payload:payload).
- List: compact secondary import action for nonempty history; preserve full first-import help in empty state. Recent sessions easy to reach. Make week chart and totals use same calendar-week interval.
- Header Start/History: one matched selection capsule,200ms strong ease-out(0.23,1,0.32,1), reduce-motion awareness,44pt targets. Keep navigation semantics.
- Detail: companion/session identity plus clear steps emphasis, less icon/card clutter, condensed real metrics, route preserved. Share reachable in persistent bottom inset; remove duplicate Share in scroll. Close accessible.
- Imported record icon use readable accent foreground.
- Watch mirror: Nano typography/compact device status/real companion via existing AppStore if available; one-second TimelineView, state.elapsed(at:), currentHeartRate(at:). Correct running/paused/auto-paused/saving/complete copy and GPS enabled/indoor states. Real controls, confirmation for Finish, .97 press with100/160ms timing, no movement under Reduce Motion.
Verification: root builds/signs, runs tests, renders and installs. No source changes outside named files; do not run build or install.
