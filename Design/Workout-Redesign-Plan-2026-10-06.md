# Workout tab redesign — implemented

Status 2026-10-06: implemented from the Bump Mobbin reference (https://mobbin.com/screens/d9565238-ad94-4f4a-bd07-00b9bc6a7a56). Signed Debug device build passed with GCC_OPTIMIZATION_LEVEL=s, installed in place on the connected iPhone 12, and launch verified by CoreDevice. The six requested workout regression suites and 100 production hex fog checks passed. Delivery evidence is saved in Workout-Redesign-2026-10-06/. Live GPS and remote Watch controls still require real-workout acceptance testing.

## User decisions
- Copy Bump's look: a soft blue fog over a light map, revealed hexagon tiles with a white rim, the neighborhood name (sticker style, top-left) and a "% explored" pill.
- Improve the whole workout UI, including "View Watch Workout" (WatchWorkoutPanel.swift).
- No leaderboards yet. Keep it simple: whatever looks best and is easiest to understand at a glance.

## Fog engine (WorkoutPreviewView.swift, `WorkoutTerritoryOverlay` / `WorkoutTerritoryRenderer`)
- Replace the corridor strokes, `WorkoutRouteNetwork` and `RouteStraightener` with a hex grid. Storage stays the same: routes are still stored and hexes are derived from them, so there's no migration.
- Pointy-top axial hexes in MKMapPoint space. Circumradius R = 20 m, scaled per 1° latitude band. Key = (band, q, r).
- Reveal: sample each segment every R/2. Skip segments longer than 1.5 km (GPS jumps). Don't bridge route breaks.
- Draw order:
  1. Fog fill.
  2. Current district tint and outline.
  3. White rims for old hexes and accent-colored rims for this walk's hexes (rim width = min(4/zoom, 0.35·R)).
  4. destinationOut fill of all revealed hexes.
- Bucket hexes in 16×16 chunks for tile culling. Remove the display-link tip animation. `updateRoute` returns the dirty rect of newly revealed hexes.
- District = a large hex with D = 20R, so 400 tiles per district. % explored = revealed tiles in the district / 400, with counts kept per district. Label the district with a reverse-geocoded subLocality. Deployment target is iOS 17, so use CLGeocoder, cached per district.
- Colors:
  - Light mode: fog (0.60, 0.64, 0.97, a 0.62).
  - Dark mode: (0.24, 0.26, 0.62, a 0.62).
  - Pass an `isDark` flag and the resolved accent into the overlay snapshot. Update the fogCover color to match.
- Workout should follow the app's appearance: remove `.preferredColorScheme(.dark)` at WorkoutPreviewView.swift:335 and replace `.white` text with NanoTheme.text (WorkoutHistoryView also has 15 `.white` uses).

## Screens
- **Setup:** full-bleed map, the neighborhood sticker, and the explored pill. The bottom bar has an activity chip, a goal chip, a gear icon (Haptic and Health toggles in a small sheet), and a big Start button with an Apple Watch button beside it. While a Watch workout is active, the bar becomes "Watch workout · time · View".
- **Picker and goal:** become sheets (medium/large detents) instead of phases. The picker is one grouped Outdoor/Indoor list; tapping an item selects it and dismisses.
- **Live:** the map stays full-screen. A floating stats card shows Time, Distance and Steps, the creature ring, a goal progress bar, and an expand button for the big-numbers view (indoor workouts always use the big-numbers view). Add a "+N new tiles · X% explored" chip. Pause is full-width and always visible.
- **Paused:** keep the stats and map visible with the map dimmed. Resume is the primary button. Finish is press-and-hold, with an accessibility action that ends the workout directly.
- **Summary:**
  - Map hero fitted to the route, with hexes.
  - Title and date, then a highlight: "+N new tiles · <neighborhood> now X%".
  - Stats grid and a condensed companion recap.
  - A small Health status line.
  - Share is the primary button and Replay is secondary. Remove "Do It Again".
  - Compute new tiles before `locationTracker.stopWorkout`.
- **Watch panel:** the same live layout, using `bridge.liveRoute` on the map, heart rate in the stats card, and Pause/Resume plus hold-to-finish.
- **Tour:** update the copy to drop "pink fog", "Show map" and "menu handle".

## Also
- Delete dead views: WorkoutFogWalkthroughVisual, WorkoutMiniMapRoads, WorkoutSetupWalkthroughVisual, WorkoutControlsWalkthroughVisual, WorkoutCapabilityStrip/Item, WorkoutCreatureBadge, WorkoutMiniBadge, WorkoutSummaryTile.
- WorkoutReplayVideo.swift (around line 320): switch the share video's fog to hexes with the new color.
- WorkoutRouteReplayView: change the "pink fog" accessibility strings.
- Rewrite Scripts/verify_fog_rendering.py for hexes (the slice starts at `struct WorkoutRouteLine {`). Re-run verify_workout_video, verify_workout_replay, verify_watch_workout_sync, verify_workout_history, verify_workout_exports and verify_workout_routes.
- Finish with a Debug device build using GCC_OPTIMIZATION_LEVEL=s, then install and launch on the iPhone.
