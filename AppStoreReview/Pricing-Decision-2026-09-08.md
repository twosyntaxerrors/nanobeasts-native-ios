# Launch pricing recommendation

**Later update:** The owner explicitly approved the hard paywall, and build 10 now implements it with saved-plan return for onboarding abandoners and a renewal screen for expired subscribers. Prices and trial eligibility below are unchanged. See the [current delivery record](../Design/Onboarding-2026-09-08/Delivery.md). Statements below describing the hard gate as unimplemented are historical.

Status: pricing configuration completed with owner authorization on September 8. App Store Connect has $4.99/month with no trial and $29.99/year with seven days free, including Apple's equalized prices and the yearly trial in all 175 current subscription territories. RevenueCat MCP is authenticated and verified the same production configuration. Replacement Test Store products now serve $4.99/month with no trial and $29.99/year with a seven-day free trial through the current offering. Both grant Premium. Build 9's custom paywall uses store-driven pricing and eligibility copy; it was installed and launched on the physical iPhone, then relaunched after the RevenueCat changes. The shared remote paywall has a corrected unpublished draft; its published version and Expo products are unchanged. See [delivery record](Pricing-Update-2026-09-08/Delivery.md) and [MCP completion](Pricing-Update-2026-09-08/MCP-Completion.md). App uploads and review submission remain on hold. The separately discussed hard gate is not implemented by this pricing update.

## Latest owner direction and recommendation

The owner favors the subsequent hard-paywall proposal and explicitly excludes the optional $19.99 first-year alternative. Confirmed US plans: yearly with seven days free, then $29.99/year; monthly at $4.99/month immediately. The owner explicitly chose to offer the trial only on yearly. Pricing and the Apple trial are now configured as described above; the full-app hard gate is still a separate, unimplemented change. Apple permits introductory offers on both products, but a person can redeem only one introductory offer per subscription group.

The owner is considering whether to replace the free trial with a $0.99 paid introduction. Recommendation: retain the seven-day yearly free trial for launch, and consider a paid introduction later based on revenue per install, full-price conversion, retention, refunds, and acquisition cost. No paid-trial selection has been made. Do not treat a higher percentage of trial users converting as sufficient evidence if substantially fewer users enter the trial.

Apple's standard monthly/yearly introductory offers support $0.99 for the first month, followed by the normal recurring price. A seven-day paid introductory period is supported through a weekly subscription's pay-as-you-go offer, not as the standard paid introduction on these monthly/yearly products. A seven-day free trial is supported on both. Source: [Apple introductory-offer duration and eligibility table](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/).

Research found a relevant August 29, 2026 X discussion by Nick (@ereniroh), quoting Chad (@ChadAppDev), through [a public mirror](https://www.sotwe.com/ereniroh). Nick proposes testing a $1 trial for better paid-ad purchase signals while acknowledging fewer paywall conversions. This is a hypothesis, not reported experimental results; the direct X search required login. [David Vargas's March 2026 RevenueCat article](https://www.revenuecat.com/blog/growth/free-trials-dont-make-sense-anymore) discusses $0.99 first-month offers primarily in the context of paid acquisition. His [July 2025 case study](https://www.revenuecat.com/blog/growth/introductory-offers-apps) reports a large acquisition improvement alongside lower early subscriber value, a new feature, and a TikTok trend, so it does not isolate a paid trial's causal effect. The hard-paywall benchmarks below do not compare free versus $0.99 trials.

## Earlier freemium recommendation (superseded by the direction above)

Keep free activity tracking and the existing allowance of 2,500 creature-progression steps per day. The paywall remains dismissible. Pro removes the progression limit. Recommend US prices of **$4.99/month** and **$29.99/year**, with yearly selected and the full annual charge clearly visible. These are proposed prices, not a claim that they are configured.

The first family already has a 250-step hatch and 500-step later stages, giving a new free user a chance to experience the creature lifecycle before the daily cap. The cap should limit progression credit, not suppress recorded steps, saved routes, access to prior activity, or permission controls. The user can dismiss an offer while the paid-feature limit remains enforced. A full-app hard paywall is a different access model and would remove that free experience.

This recommendation prioritizes experiencing the creature, sharing routes, and building a returning audience before asking everyone to subscribe. It is a product hypothesis, not a demonstrated revenue optimum. A competitor's revenue does not establish that its paywall caused its success. No new experimentation infrastructure or broad testing project is proposed before launch.

## Lifetime and discounts

- Do not add lifetime in the first release by default. It adds a new non-consumable product and entitlement case while the existing subscriptions are already prepared.
- $19.99 lifetime can be a deliberate one-time-purchase business model or a genuinely limited founding offer. Beside a $29.99/year subscription with identical benefits, however, it gives committed customers a cheaper permanent option and can sharply reduce future renewal revenue. It is not automatically unprofitable; the right answer depends on acquisition/support/content costs and retention, which are not yet known.
- If lifetime is essential, a starting hypothesis around $59.99 alongside $29.99/year is more internally consistent. Define the permanent entitlement clearly and honor it for purchasers. Do not sell lifetime and later convert those purchasers to subscribers for the same promised access.
- Use the annual saving as the first discount: 12 × $4.99 = $59.88; $29.99/year saves $29.89, approximately 49.92%. Display the saving calculated from the actual localized products. No invented original price, perpetual countdown, or automatic discount merely for dismissing the offer is needed.
- Copy at the cap should distinguish recorded activity from game progress, for example: “All your steps are tracked. Your free evolution progress resets tomorrow.” Action: “Unlock unlimited evolution.”

## Competitor evidence, US storefront checked September 8, 2026

| App | Public listing evidence | Limit of that evidence |
| --- | --- | --- |
| StepsApp | PRO Monthly $5.99 and $4.99; PRO Yearly $32.99 and $19.99, plus other products. Free app with paid Pro functionality. | The list includes several SKUs and does not identify the exact offer shown to every new user. |
| Steps & Beasts | Lifetime products $24.99, $39.99, $49.99; annual/yearly entries $9.99, $17.90, $19.99, $29.99; other periodic products. | Establishes both models exist, not which SKU is the current default or highest-converting offer. |
| Fantasy Hike | Unlimited Distance $6.99 and recurring Premium product entries. | A one-time feature unlock is not necessarily lifetime access to every Premium feature. |

Sources: [StepsApp](https://apps.apple.com/us/app/stepsapp-pedometer/id1037595083), [Steps & Beasts](https://apps.apple.com/us/app/step-tracker-steps-beasts/id6670788226), [Fantasy Hike](https://apps.apple.com/us/app/fantasy-hike/id1557127861).

[RevenueCat's 2026 report](https://www.revenuecat.com/state-of-subscription-apps) reports median day-35 download-to-paid conversion of 10.7% for hard-paywall apps versus 2.1% for freemium, with wide variation. This is observational across different apps, not a randomized comparison of two Nanobeasts paywalls. It supports taking the hard-paywall option seriously, but does not establish the best model for this creature-collection app.

## Owner's release constraints

- Do not upload the current app yet; further changes may follow.
- Account readiness is considered fine by the owner; no repeat general account audit requested.
- The owner reports smooth physical-device development testing and does not want another open-ended test/feature cycle. Treat that as acceptance of the present product behavior, rather than claiming that previously unmeasured cases were independently verified.
- Privacy disclosures may be updated now, independently of pricing or binary upload.
