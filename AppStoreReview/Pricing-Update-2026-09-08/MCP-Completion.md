# RevenueCat MCP completion

Completed September 8, 2026 after owner authorization in Brave and Keychain approval. Connected to the official RevenueCat MCP server using the approved OAuth credential kept only in the client process's memory. Native MCP discovery was unavailable in the running task, so an authenticated Streamable HTTP MCP client called the same server's `tools/list` and `tools/call` endpoints. No customer purchase or paid transaction was performed.

## Current configuration

Project: `proj83b947c7` (dashboard name `X`). Current offering: `ofrngb73fbef039`, identifier `nanobeasts_pro_paywall_draft`.

| Store / plan | Product | Price | Trial |
| --- | --- | --- | --- |
| Native App Store monthly | `prod431d497fe4` / `nanobeasts_native_premium_monthly` | US $4.99/month | None |
| Native App Store yearly | `prod3e863cf11f` / `nanobeasts_native_premium_yearly` | US $29.99/year | 1 week for eligible customers |
| Test Store monthly | `prod7c2b2aad28` / `nanobeasts_test_premium_monthly_v2` | $4.99/month | None |
| Test Store yearly | `prod63d647dfe8` / `nanobeasts_test_premium_yearly_v2` | $29.99/year | `P1W`, eligibility `never_subscribed` |

The Test Store's existing currency prices cannot be changed, so new products were created following [RevenueCat's documented replacement workflow](https://www.revenuecat.com/docs/test-and-launch/sandbox/test-store#changing-test-store-products-and-prices). Previous test products remain attached to Premium for purchase history but are detached from the current packages.

- Monthly package `pkge2cf9c45915` now uses the new monthly Test Store product.
- Annual package `pkge949cc04b7a` now uses the new yearly Test Store product.
- Both new test products were attached to `entlf0ee1d6d28` (`premium`).
- Native and Expo product associations in both packages were verified unchanged. The Expo-only bounce offer remains untouched.
- MCP `get-product-store-state` independently confirmed the native App Store $4.99/$29.99 prices and `ONE_WEEK` yearly trial. Both products remain ready to submit, not submitted.
- Read-only SDK endpoints returned the new Test Store identifiers, exact price micros `4990000` and `29990000`, a null monthly trial, and a yearly trial with `period_duration: P1W`, one cycle, no paid introductory phase.

## Remote paywall

Paywall `pwcb5cf4da5e2d4ca2` is shared with the Expo setup. Prepared unpublished draft revision **336** with a visible `BEST VALUE` annual badge, dynamic prices and a conservative `Subscribe` CTA. The remote editor could not guarantee annual-only/free-only offer conditions, so trial-specific CTA/footer overrides were removed from this draft. Native build 9's custom SwiftUI paywall remains the shipping implementation and has explicit yearly-only, confirmed-eligibility free-trial messaging.

Verified the published component configuration, revision **334**, is byte-for-byte unchanged. One unused `SAVE 54%` localization remains unbound in the draft dictionary; the visible badge is corrected. Do not publish this shared template as part of the native app submission. The native app does not render it.

## Device and release state

Build 9 had already been installed and launched on the physical iPhone in the preceding turn. After the server changes, rediscovered the connected iPhone and relaunched Nanobeasts successfully at 18:32 EDT to refresh its configuration. Receipt: `iPhone-Refresh-After-RevenueCat.json`. No app data was cleared. No actual subscription was purchased, no binary uploaded, and no review submission made. The separately discussed hard-paywall access model remains a future app-code change.

MCP receipts are `mcp-*.json`; current SDK readbacks are `debug-test-store-offerings-after.json` and `debug-test-store-products-after.json`.
