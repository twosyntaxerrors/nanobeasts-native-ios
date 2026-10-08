# Nanobeasts Field Demo

A 27-second silent opening demo, in the existing 1080 × 1666 video format.

1. Walking progress counts toward Glitchlet's evolution.
2. The existing R2 animation transforms Glitchlet into Devicore.
3. An actual route-replay export clears the fog and displays workout stats.
4. Activity Stats shows movement history and the monthly calendar, then scrolls into animated step insights and goal history.
5. The Field Dex and an earned streak badge reward the walking habit.

The greeting uses Sinatra. This revision preserves the approved phone proportions and original scenes, adding seven seconds for stats and insights.

The 27-second revision was approved for onboarding on September 9, 2026. It is hosted at `https://assets.nanobeasts.app/videos/onboarding/nanobeasts-field-demo-v2.mp4`, and FieldDemoView now uses that URL. No media was added to the app bundle. Delivery records are in `Design/Onboarding-Demo-Delivery-2026-09-09/` at the repository root.

Home, Stats, and Dex are motion reconstructions of the current app interface with illustrative progress data; they are not new physical-device recordings. The stats example is internally consistent: 44,100 weekly steps, a 6,300 daily average, and six days meeting a 5,000-step goal. Creature artwork and the evolution animation come from the app's existing R2 assets. The route scene uses the existing demo workout export. Provenance: `.hyperframes/asset-provenance.json`.

Source: `index.html`. Revised video: `renders/Nanobeasts-Onboarding-Demo-v2.mp4`. Optimized encode: `renders/Nanobeasts-Onboarding-Demo-v2-Streaming.mp4`. The original 20-second exports remain available under their unversioned filenames; their source is preserved in `revisions/v1/`.

The master timeline uses deterministic sprite sheets, count-ups, opacity transitions, and native video playback through HyperFrames. No narrated audio; the first onboarding screen already mutes its demo. Get Started remains outside the video.

Fonts, sprites, and footage in `assets/` are render inputs only. The hosted bytes match the approved streaming export. The app displays the complete video with aspect-fit playback to preserve the captions and stats.

## v3 (October 4, 2026)

Matches the landing page cut at nanobeasts.app: the baked-in "FIELD DEMO" label and bottom progress rail are removed so the app can show a time-left countdown in the top-right corner instead (`DemoCountdownOverlay`). Scenes and timing are unchanged from v2, whose source is preserved in `revisions/v2/`. Master: `renders/Nanobeasts-Onboarding-Demo-v3.mp4`. Streaming encode (H.264, yuv420p, CRF 26, fast-start, silent, 1080 × 1666, 2,265,959 bytes): `renders/Nanobeasts-Onboarding-Demo-v3-Streaming.mp4`, to be hosted at `https://assets.nanobeasts.app/videos/onboarding/nanobeasts-field-demo-v3.mp4`. The v2 object stays on R2 for rollback.

## v4 (October 6, 2026)

Stats and Dex chapters rebuilt to match the redesigned app. Insights (14.65–21.65s) now scrolls the numbered Activity Log (calendar with goal-days, streak and best chips) into Trends (W/M/Y range, glowing best-day bar, goal line, goal days / total / vs-previous strip) and ends on Rhythm (5–7 PM peak). Collect (21.65–26.25s) shows the Field Dex gallery: catalog ring, type chips, type-tinted tiles with a silhouette and "?" slots, and the reward toast uses the text-free 5-day streak badge. Home, Evolve and Explore are unchanged; timing is unchanged. Added creature art from R2 (Ampunch, Ampact, Hydralilly); the original 5-day badge is kept as `assets/streak-5-with-text.png`. CLI pin moved 0.8.3 → 0.8.137 (check passes; render with Node 22). Master: `renders/Nanobeasts-Onboarding-Demo-v4.mp4`. Streaming encode (H.264, yuv420p, CRF 26, fast-start, silent, 1080 × 1666, 2,229,153 bytes): `renders/Nanobeasts-Onboarding-Demo-v4-Streaming.mp4`, to be hosted at `https://assets.nanobeasts.app/videos/onboarding/nanobeasts-field-demo-v4.mp4`. v3 stays on R2 for rollback.

## v5 (October 7, 2026)

The Explore chapter (9–14.65s) no longer plays the fog route-replay export. It is rebuilt to match the tile trail: a dark Mission District map (San Francisco, deliberately not a real user's neighborhood) with earlier walks painted softly, today's walk painting 40 accent tiles in walking order behind a moving location dot, the zone badge ("Mission St", "Mission District") counting 76.9% → 96.2% of streets, flipping to "Mastered" at 90%, and a "Zone mastered" card at 13.35s. The live walk card's time, miles and steps count up with it. Footer: "Walk your streets. Master your neighborhood." The map, earlier-walk layer and tile polygons are generated with the app's own WorkoutHexGrid, WorkoutTrailPainter and zone-streets cache (`assets/explore-map.png`, `assets/explore-walk.json`). Other chapters and timing are unchanged; v4's source is in `revisions/v4/`. Master: `renders/Nanobeasts-Onboarding-Demo-v5.mp4`. Streaming encode (H.264, yuv420p, CRF 26, fast-start, silent, 1080 × 1666, 2,342,426 bytes): `renders/Nanobeasts-Onboarding-Demo-v5-Streaming.mp4`, hosted at `https://assets.nanobeasts.app/videos/onboarding/nanobeasts-field-demo-v5.mp4`. v4 stays on R2 for rollback.
