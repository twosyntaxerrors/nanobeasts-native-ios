# Final submission readiness — September 8, 2026

**Later update:** Build 10 implements the approved hard paywall, saved onboarding, opt-in setup reminders, workout coach marks, and revised activity projections. The draft description and reviewer notes now match that behavior; the public privacy policy has also been updated. See the [current delivery record](../Design/Onboarding-2026-09-08/Delivery.md) for device/build evidence and remaining work. The audit below is historical. Upload and submission remain on hold.

Read-only audit after pricing synchronization. No app upload, review submission, or app source change was performed. Upload and submission remain on hold at the owner's request.

## Verified now

- Native app: Nanobeasts, ASC `6794927950`, bundle `com.twosyntaxerrors.nanobeasts.native`.
- Live `asc validate` for version `32278c73-aaf4-41a9-b5c4-d168047ab1d1`: zero errors, zero blocking checks, four warnings, one informational check. This validates the existing submission metadata, not the newer local binary or app behavior.
- Version 1.0 remains `PREPARE_FOR_SUBMISSION`. The draft review submission is `READY_FOR_REVIEW`; it has not been sent to Apple.
- The latest uploaded build remains 4 (`VALID`). Local project/build delivery is 9, including the corrected store-driven paywall prices and yearly-only trial copy.
- Monthly and yearly subscriptions are `READY_TO_SUBMIT`. Two warnings concern optional subscription promotional images; these do not require more ordinary App Store screenshots.
- Public privacy policy update is complete. App Store Connect's App Privacy publication state remains unverified: opening its page in Brave redirected to Apple sign-in. The public API cannot verify this state.
- Pricing configuration is complete per `Pricing-Update-2026-09-08/Delivery.md` and `MCP-Completion.md`: US $4.99/month without trial, $29.99/year with seven days free for eligible yearly subscribers.

## Remaining work

1. **Implement the chosen hard paywall before packaging the final build.** The current paywall still has a close button, and `AppRootView.handlePaywallDismissed()` completes onboarding without requiring an active entitlement. Pricing configuration did not change this access model. Subscription expiration, restoration, and paired Watch access should follow the final access policy. This is a mismatch with the owner's selected business model, not an Apple requirement to use hard paywalls.
2. **Verify/publish the ASC App Privacy answers.** The website policy, privacy manifests, and Apple questionnaire are separate. Prepared answers are in `Privacy-Answers-2026-09-07.md`; publication needs an authenticated Apple browser session.
3. **Prepare and validate a final Release archive; upload and select it only after the owner's go-ahead.** Build 4 on ASC does not include the latest local changes. A focused Apple sandbox/TestFlight check of yearly trial eligibility, immediate monthly billing, purchase restoration, and entitlement expiry is recommended; the installed development build uses RevenueCat Test Store. No broad new feature-testing cycle is proposed.
4. **Finish the review package around the final behavior.** Review notes currently describe a dismissible freemium paywall and 2,500-step daily cap. Update them after the access model changes, include the route replay/share flow, and ensure the app version, monthly/yearly subscriptions, and their group are together in the review draft before submission.

Pricing, screenshot redesign, localization, and further feature development are not additional launch tasks identified by this audit. Account readiness and prior physical development testing are accepted as stated by the owner.

References: [Apple first subscription submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/), [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/).
