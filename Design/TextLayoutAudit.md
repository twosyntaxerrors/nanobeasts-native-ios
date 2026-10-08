# Text layout audit — September 5, 2026

Reviewed the iPhone view sources and the Watch/Live Activity workout surfaces
for fixed label widths, fixed text heights, truncated prose, and unprotected
short labels/numeric values.

Changes:
- Share style and photo controls use a horizontal layout with a vertical fallback.
  The share header stacks at accessibility text sizes. Shorter share/copy action
  labels retain their meaning; buttons reserve sufficient height and padding.
- Workout buttons, headers, metric labels, goals, timers, and history rows keep
  compact text together with scaling within their available space. History dates
  reserve their intrinsic width. The walking tempo strip can grow vertically.
- Watch workout names, step totals, summary labels, GPS status, and controls have
  single-line sizing. The Health toggle uses the shorter visible label “Save to
  Health” while retaining “Save to Apple Health” for accessibility.
- Live Activity workout names, timer, and unit labels have single-line sizing.
- Settings, onboarding, and Health error/help text can grow instead of ending at
  an arbitrary two-line limit. Lab/Stats metric labels and values, badges, and
  existing one-line profile/status labels have sizing fallbacks. Badge cards grow
  vertically and retain two lines for multiword names; single-word names stay on
  one line. Existing Dex name and stage-label fit handling was reviewed.

Verification:
- Combined signed iPhone/Watch/widget build passed.
- Actual production share controls rendered at 240, 320, and 390 points wide;
  inspected both horizontal and vertical layouts. These are macOS SwiftUI renders
  with the production font, not evidence of iOS Dynamic Type behavior.
- Eight production export renders and normalized overlay bounds checks passed.
- Reference renders are in build/TextLayoutAudit (local build artifacts).

Limits: this is a source audit with focused render checks, not an exhaustive
physical-device UI traversal of every data value, localization, and text size.

Delivery: the final app was installed in place on the physical iPhone. Launch
verification was blocked by the phone being locked. Watch installation hit two
wireless tunnel timeouts; refreshed the current-user pairing service and asked
for both devices to be unlocked/nearby to finish delivery.

Follow-up: the installed iPhone app launched successfully on the physical device
at 22:20 on September 5. This verifies launch, not a complete UI traversal.

Watch delivery completed: on September 5 at 22:35, devicectl confirmed the
updated Nano app installed on the physical Apple Watch SE and launched
successfully. Both iPhone and Watch installations and launches are now verified.
This does not extend the visual audit coverage described above.
