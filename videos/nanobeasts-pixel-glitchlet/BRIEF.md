# Pixel Glitchlet splash preview

Status: approved preview direction. Flow: motion-graphics. Category: logo-reveal (mascot brand loop; no reveal effect).

Make a small pixel Glitchlet jog in place, centered on a plain black phone-shaped canvas. Purple body, lime circuit markings, pink eyes, and one bobbing antenna. Use the already generated transparent eight-pose asset. Running poses carry all the motion; add no text, glow, dust, ground, intro, outro, camera motion or effects.

Preview: 1080 × 2340, 30 fps, 3.2 seconds. Display the aligned 96 × 96 mascot frames at 288 × 288 pixels with nearest-neighbor rendering. Eight poses at 10 fps give a 0.8-second cycle; show four cycles with an exact loop boundary. Audio is silent. This is a visual preview, not an app installation request.

Source: assets/glitchlet-run-sheet-source.png. Derived frame names and timeline specification are in shot-plan.json. Registry search is recorded in registry-search.json; its Lottie walk-and-point block does not fit this sprite loop.

## Approved revision — 2026-10-05

Place the white NANOBEASTS wordmark under the approved running Glitchlet. Use the app's subtle grid on black, preserving the original transparent PNG frames and crisp pixel sampling. Wordmark uses the bundled Aldrich font at 24 points, tracking 3, with a 24-point gap under the 104-point sprite canvas. The native splash runs three 0.8-second cycles and dismisses; Reduce Motion uses the first pose for 350 ms. Deliver the native Debug update in place on the connected physical iPhone. Preview keeps looping for review.

## Letter reveal revision — 2026-10-05

Reveal NANOBEASTS from left to right while Glitchlet runs. Reserve the full word width throughout. First letter begins at 120 ms; each following letter starts 85 ms later, with an 180 ms fade and 4-point rise. All ten letters settle by 1.065 seconds; native splash still ends after 2.4 seconds. Reduce Motion displays the full word immediately. Preview uses the registry bottom-up-letters splitter adapted to the existing Aldrich wordmark and a short fade/rise.
