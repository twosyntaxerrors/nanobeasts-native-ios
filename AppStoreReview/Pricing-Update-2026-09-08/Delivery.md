# Subscription pricing update — September 8, 2026

**Completed after the owner signed in through Brave:** RevenueCat MCP is now authenticated. Current Test Store prices and annual trial match the production plans, with successful SDK readback and an iPhone relaunch. See [MCP completion](MCP-Completion.md) for identifiers and verification. The initial authorization blocker below is resolved.

## Completed

Only native App Store Connect app **6794927950**, bundle **com.twosyntaxerrors.nanobeasts.native**, was changed. The Expo listing and products were not modified. No binary was uploaded and no review submission was made.

| Plan | Existing product | US price | Introductory offer |
| --- | --- | --- | --- |
| Monthly | nanobeasts_native_premium_monthly / 6796105139 | $4.99/month | None; billed immediately |
| Yearly | nanobeasts_native_premium_yearly / 6796104976 | $29.99/year | 7 days free for eligible subscribers |

- Both price changes succeeded in all **175** existing subscription territories using Apple's price equalization from the US base. Read back 175 unique effective prices for each product. All yearly price-point IDs match the saved equalization plan.
- Created and read back **175** unique yearly introductory offers, including the US. Every offer has `ONE_WEEK`, `FREE_TRIAL`, one period, start date September 8, 2026, and no scheduled end. Apple's initial request returned server errors for 92 territories; a targeted retry completed all 92, with no failures. The monthly product has no introductory offers.
- Both products remain `READY_TO_SUBMIT`. This is product configuration, not approval or a review submission.
- RevenueCat's production current offering is `nanobeasts_pro_paywall_draft`. Its `$rc_monthly` and `$rc_annual` packages reference the correct native App Store products. Both map to the `premium` entitlement. Initially verified via RevenueCat's read-only SDK endpoints; subsequently confirmed through authenticated RevenueCat MCP, including live App Store price and trial state.

## App delivery and checks

- Custom SwiftUI paywall uses localized store prices, with no hardcoded US fallback prices. Missing prices now show loading/unavailable states with a retry action.
- Savings are calculated from actual yearly versus 12 monthly prices in the same currency: the new US pair rounds to **50%**. The fixed `SAVE 54%` label is removed from the app's custom paywall.
- Annual free-trial copy requires both a free introductory offer on the product and confirmed RevenueCat eligibility. Duration comes from that offer. Unknown/ineligible users are not promised a trial. Monthly says no free trial and immediate billing.
- Shows the full yearly renewal amount and Apple's 24-hour trial-cancellation guidance. The existing screen layout and dismissible access model remain in place; this update does not implement the separately discussed hard gate.
- **32 pricing and trial-copy assertions passed**, covering eligibility states, paid vs free introductions, monthly selection, localized prices, currency mismatch, savings, and unavailable products. The harness executes the actual computed properties from the shipping view with fixture data types.
- Signed Debug **build 9** succeeded. Installed in place on the discovered physical iPhone 12 and launched successfully (process 7472). No uninstall or user-data reset. Installation and launch receipts are saved here.

## RevenueCat follow-up completed

Added the official MCP server, `https://mcp.revenuecat.ai/mcp`, through Codex's MCP CLI. The first OAuth attempt timed out; the follow-up completed successfully through the owner's signed-in Brave browser. Authenticated MCP calls were used to read store state, create/configure replacement Test Store products, attach them to Premium and the existing packages, and prepare the remote paywall draft.

Resolution of the initially found discrepancies:

1. **Development Test Store:** existing prices are immutable. Created `nanobeasts_test_premium_monthly_v2` at $4.99/month without a trial and `nanobeasts_test_premium_yearly_v2` at $29.99/year with a `P1W` free trial. Both grant Premium and replace only the previous Test Store products in the current offering. Read back the exact new price/trial data through both MCP and SDK endpoints. Old products remain for historical test purchases, outside the current packages.
2. **Remote RevenueCat paywall:** saved unpublished draft revision 336. Its visible annual badge is `BEST VALUE` and recurring prices remain dynamic. The draft uses `Subscribe` and normal recurring-price copy, avoiding unsupported conditional free-trial claims in the shared template. The shipping native app's custom SwiftUI paywall already handles yearly-only trial eligibility. One unreferenced legacy `SAVE 54%` localization remains in the remote draft's dictionary; it is not bound to a displayed component. Published remote revision 334 is byte-for-byte unchanged to preserve Expo's published template. Pre-existing remote-template preview issues (player-name fallback, monthly preview price, Terms URL) need review only if adopting/publishing RevenueCatUI later; they are not the native custom paywall.
3. **Discount offering:** authenticated inspection established that `nanobeasts_bounce_save` belongs to the preserved Expo setup and contains its yearly-saver product. It has no native or Test Store product. Left it intact; no $19.99 native offer was created.

No RevenueCat sign-in blocker remains. App uploads, product review submission, and localization remain on hold. No full-app hard gate was added by this pricing task.

## Evidence

- `pricing-summary-after.json`, `monthly-prices-after.json`, `yearly-prices-after.json`
- `yearly-trials-after.json`, `monthly-trials-after.json`, trial creation/retry receipts
- `native-app-store-offerings.json`, `native-entitlement-mapping.json`
- `debug-test-store-offerings.json`, `debug-test-store-products-before.json`
- `device-build.log`, `iPhone-Install-Build9.json`, `iPhone-Launch-Build9.json`, `pricing-copy-checks.txt`
- [Apple trial cancellation guidance](https://support.apple.com/en-us/118428)
