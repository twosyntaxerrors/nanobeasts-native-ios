import RevenueCat
import SwiftUI

struct RevenueCatPaywallScreen: View {
    private enum Plan {
        case yearly
        case monthly
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let playerName: String
    var selectedGoals: Set<String> = []
    var primaryGoal: String? = nil
    var selectedBlockers: Set<String> = []
    var isPreview = false
    var onPreviewPurchase: (() -> Void)? = nil
    var onPreviewClose: (() -> Void)? = nil
    var previewMilestone: String? = nil

    @AppStorage("nanobeasts.notifications.setup-reminders") private var setupReminders = false
    @State private var offering: Offering?
    @State private var selectedPlan: Plan = .yearly
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var isLoadingPlans = true
    @State private var yearlyTrialEligibility: IntroEligibilityStatus = .unknown
    @State private var errorMessage: String?
    @State private var previewNotice: String?

    private var copy: OnboardingCopy {
        .forGoals(selectedGoals, primaryGoal: primaryGoal, blockers: selectedBlockers)
    }

    var body: some View {
        PaywallPage(copy: copy, firstName: playerName, tint: NanoTheme.teal,
                    milestone: isPreview ? previewMilestone : nil) {
            topBar
        } offers: {
            offerSection
        } checkout: {
            purchaseFooter
        }
        .background { PaywallBackdrop(tint: NanoTheme.teal).ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .task { await loadOffering() }
        .alert("Preview", isPresented: Binding(get: { previewNotice != nil },
            set: { if !$0 { previewNotice = nil } })) {
            Button("OK") { previewNotice = nil }
        } message: { Text(previewNotice ?? "") }
    }

    private var offerSection: some View {
        VStack(spacing: 16) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 18)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                PaywallPlanCard(title: "MONTHLY", price: monthlyAmount, period: "/month",
                    detail: "No free trial", selected: selectedPlan == .monthly, tint: NanoTheme.teal) {
                    withAnimation(.snappy(duration: 0.25)) { selectedPlan = .monthly }
                }
                PaywallPlanCard(title: "YEARLY", price: yearlyWeeklyEquivalent ?? yearlyAmount,
                    period: yearlyWeeklyEquivalent == nil ? "/year" : "/week",
                    detail: yearlyDetail, badge: yearlySavingsBadge,
                    accessibilityBillingDetail: yearlyWeeklyEquivalent == nil ? nil : "\(yearlyAmount) billed yearly",
                    highlightsDetail: eligibleYearlyTrialDuration != nil,
                    selected: selectedPlan == .yearly, tint: NanoTheme.teal) {
                    withAnimation(.snappy(duration: 0.25)) { selectedPlan = .yearly }
                }
            }
            .disabled(isPurchasing || isRestoring)
            .padding(.top, 10)

            if isLoadingPlans {
                HStack(spacing: 8) { ProgressView(); Text("Loading subscription plans…") }
                    .font(.caption).foregroundStyle(NanoTheme.secondaryText)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(NanoTheme.pink)
                    .multilineTextAlignment(.center)
                if !isLoadingPlans && (monthlyPackage == nil || yearlyPackage == nil) {
                    Button("Try again") { Task { await loadOffering() } }
                        .font(.caption.weight(.semibold)).tint(NanoTheme.teal)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private var purchaseFooter: some View {
        VStack(spacing: 12) {
            PaywallCheckout(title: purchaseButtonTitle, summary: purchaseSummary,
                renewalNotice: renewalDisclosure, tint: NanoTheme.teal,
                billingPrice: annualBillingPrice, billingLeadIn: annualBillingLeadIn,
                isPurchasing: isPurchasing, isRestoring: isRestoring,
                isDisabled: isPurchasing || isRestoring || isLoadingPlans || selectedPackage == nil,
                isRestoreDisabled: isPurchasing || isRestoring || isLoadingPlans,
                onPurchase: { Task { await purchaseSelectedPlan() } },
                onRestore: { Task { await restore() } })
            if setupReminders && !isPreview {
                Button("Turn off setup reminders") {
                    NanoNotifications.shared.setSetupReminderPreference(false)
                    setupReminders = false
                }
                .font(.caption).foregroundStyle(NanoTheme.secondaryText)
                .frame(minHeight: 44)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                if isPreview, let onPreviewClose { onPreviewClose() }
                else { dismiss() }
            } label: {
                SolarImage(.closeCircle, size: 24)
                    .frame(width: 44, height: 44)
            }
            .disabled(isPurchasing || isRestoring)
            .accessibilityLabel(isPreview ? "Close preview paywall" : "Back to your plan")
            .buttonStyle(.plain).foregroundStyle(NanoTheme.secondaryText)
            Spacer()
            if isPreview {
                Text("PREVIEW · NO CHARGE").font(.system(size: 9, weight: .medium))
                    .foregroundStyle(NanoTheme.secondaryText)
            }
#if DEBUG
            if !isPreview && isUsingRevenueCatTestStore {
                Text("TEST PURCHASE · NO CHARGE").font(.system(size: 9, weight: .medium))
                    .foregroundStyle(NanoTheme.secondaryText)
            }
#endif
        }
    }

    private var yearlyPrice: String {
        yearlyPackage.map {
            "\($0.storeProduct.localizedPriceString)/year"
        } ?? (isLoadingPlans ? "Loading…" : "Unavailable")
    }

    private var monthlyPrice: String {
        monthlyPackage.map {
            "\($0.storeProduct.localizedPriceString)/month"
        } ?? (isLoadingPlans ? "Loading…" : "Unavailable")
    }

    private var yearlyDetail: String {
        if let duration = eligibleYearlyTrialDuration {
            return "Free trial for \(duration)"
        }
        return "Billed yearly"
    }

    private var yearlySavingsBadge: String? {
        guard let annual = yearlyPackage?.storeProduct,
              let monthly = monthlyPackage?.storeProduct,
              let currency = annual.currencyCode,
              currency == monthly.currencyCode,
              annual.price > 0, monthly.price > 0 else { return nil }
        let annualValue = NSDecimalNumber(decimal: annual.price).doubleValue
        let monthlyValue = NSDecimalNumber(decimal: monthly.price).doubleValue
        let savings = Int(((1 - annualValue / (monthlyValue * 12)) * 100).rounded())
        return savings > 0 ? "SAVE \(savings)%" : nil
    }

    private var eligibleYearlyTrialDuration: String? {
        guard yearlyTrialEligibility == .eligible,
              let trial = yearlyPackage?.storeProduct.introductoryDiscount,
              trial.paymentMode == .freeTrial else { return nil }

        let count = trial.subscriptionPeriod.value * trial.numberOfPeriods
        switch trial.subscriptionPeriod.unit {
        case .day:
            return "\(count) \(count == 1 ? "day" : "days")"
        case .week:
            return "\(count * 7) days"
        case .month:
            return "\(count) \(count == 1 ? "month" : "months")"
        case .year:
            return "\(count) \(count == 1 ? "year" : "years")"
        @unknown default:
            return nil
        }
    }

    private var purchaseButtonTitle: String {
        if isLoadingPlans { return "Loading plans…" }
        if selectedPackage == nil { return "Plan unavailable" }
        if selectedPlan == .yearly, eligibleYearlyTrialDuration != nil {
            return localizedTrialZeroPrice.map { "Try for \($0)" } ?? "Start your free trial"
        }
        return "Start your journey"
    }

    private var localizedTrialZeroPrice: String? {
        guard let formatter = yearlyPackage?.storeProduct.priceFormatter?.copy() as? NumberFormatter else {
            return nil
        }
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber.zero)
    }

    private var purchaseSummary: String {
        guard !isLoadingPlans, selectedPackage != nil else { return "" }
        if selectedPlan == .yearly {
            if let duration = eligibleYearlyTrialDuration {
                return "\(duration) free, then \(yearlyPrice)."
            }
            return "\(yearlyPrice), billed today."
        }
        return "\(monthlyPrice), billed today. No free trial."
    }

    private var renewalDisclosure: String {
        guard !isLoadingPlans, selectedPackage != nil else { return "" }
        if selectedPlan == .yearly, eligibleYearlyTrialDuration != nil {
            return "Renews automatically. Cancel at least 24 hours before your trial ends to avoid being charged."
        }
        return "Renews automatically until cancelled."
    }

    private var yearlyAmount: String {
        yearlyPackage?.storeProduct.localizedPriceString ?? (isLoadingPlans ? "Loading…" : "Unavailable")
    }

    /// A comparison only. The annual amount below checkout remains the charge.
    /// Use the product's period and currency formatter, including zero-decimal currencies.
    private var yearlyWeeklyEquivalent: String? {
        guard !isLoadingPlans, let annual = yearlyPackage?.storeProduct,
              annual.price > 0, let period = annual.subscriptionPeriod,
              period.unit == .year, period.value == 1,
              let formatter = annual.priceFormatter?.copy() as? NumberFormatter else { return nil }
        let weeks = period.numberOfUnitsAs(unit: .week)
        guard weeks > 0 else { return nil }
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSDecimalNumber(decimal: annual.price / weeks))
    }

    private var annualBillingPrice: String? {
        guard selectedPlan == .yearly, !isLoadingPlans, yearlyPackage != nil else { return nil }
        return yearlyPrice
    }

    private var annualBillingLeadIn: String {
        if let duration = eligibleYearlyTrialDuration { return "\(duration) free, then" }
        return "Billed today, then annually"
    }

    private var monthlyAmount: String {
        monthlyPackage?.storeProduct.localizedPriceString ?? (isLoadingPlans ? "Loading…" : "Unavailable")
    }

    private var monthlyPackage: Package? {
        offering?.monthly
            ?? offering?.availablePackages.first {
                $0.storeProduct.productIdentifier == AppStore.premiumMonthlyProductID
            }
    }

    private var yearlyPackage: Package? {
        offering?.annual
            ?? offering?.availablePackages.first {
                $0.storeProduct.productIdentifier == AppStore.premiumYearlyProductID
            }
    }

    private var selectedPackage: Package? {
        switch selectedPlan {
        case .yearly: yearlyPackage
        case .monthly: monthlyPackage
        }
    }

#if DEBUG
    private var isUsingRevenueCatTestStore: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String)?
            .hasPrefix("test_") == true
    }
#endif

    @MainActor
    private func loadOffering() async {
        isLoadingPlans = true
        yearlyTrialEligibility = .unknown
        errorMessage = nil
        defer { isLoadingPlans = false }
        // A replay models a new eligible customer, independent of prior test purchases.
        // It uses the same offer-formatting code, and the purchase action remains simulated.
        if isPreview {
            offering = PaywallPreviewOffering.make()
            yearlyTrialEligibility = .eligible
            return
        }
        guard Purchases.isConfigured else {
            errorMessage = "RevenueCat is not configured for this build."
            return
        }

        do {
            let offerings = try await Purchases.shared.offerings()
            offering = offerings.current
            if monthlyPackage == nil || yearlyPackage == nil {
                errorMessage = "The current RevenueCat offering is missing a monthly or yearly plan."
            }
            if let product = yearlyPackage?.storeProduct {
                yearlyTrialEligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(product: product)
            }
        } catch {
            errorMessage = "RevenueCat could not load the plans. Please check your connection and try again."
        }
    }

    @MainActor
    private func purchaseSelectedPlan() async {
        guard !isLoadingPlans, !isPurchasing, !isRestoring, let selectedPackage else { return }
        if isPreview {
            onPreviewPurchase?()
            return
        }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: selectedPackage)
            guard !result.userCancelled else { return }

            await store.applyRevenueCatPurchase(result.customerInfo)
            if store.isPremium {
                dismiss()
            } else {
                errorMessage = "Your purchase is still pending confirmation."
            }
        } catch {
            errorMessage = purchaseErrorMessage(for: error)
        }
    }

    @MainActor
    private func restore() async {
        guard !isPreview else {
            previewNotice = "Restore is simulated in this preview. Your existing subscription is unchanged."
            return
        }
        isRestoring = true
        errorMessage = nil
        defer { isRestoring = false }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            await store.applyRevenueCatCustomerInfo(customerInfo)
            if store.isPremium {
                dismiss()
            } else {
                errorMessage = "No active Nanobeasts subscription was found for this Apple Account."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func purchaseErrorMessage(for error: Error) -> String {
#if DEBUG
        let nsError = error as NSError
        let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        let productID = selectedPackage?.storeProduct.productIdentifier ?? "unknown"
        print(
            """
            [Nanobeasts StoreKit] Purchase failed
            product: \(productID)
            error: \(nsError.domain) (\(nsError.code)) \(nsError.localizedDescription)
            underlying: \(underlyingError?.domain ?? "none") \
            (\(underlyingError?.code ?? 0)) \
            \(underlyingError?.localizedDescription ?? "none")
            userInfo: \(nsError.userInfo)
            """
        )
#endif

        guard let revenueCatError = error as? RevenueCat.ErrorCode else {
            return error.localizedDescription
        }

        switch revenueCatError {
        case .productNotAvailableForPurchaseError:
#if DEBUG
            let diagnostic = purchaseDiagnostic(for: error)
            return """
            Apple’s sandbox returned “product unavailable” after loading this plan. \
            Your tester settings are correct; this is an App Store product-state \
            rejection. Diagnostic: \(diagnostic)
            """
#else
            return "This plan is temporarily unavailable. Please try again shortly."
#endif
        case .purchaseNotAllowedError:
            return "Purchases are not allowed for this Apple Account or device."
        case .paymentPendingError:
            return "Your purchase is pending Apple confirmation. Premium will unlock automatically once approved."
        case .storeProblemError, .networkError:
            return "The App Store could not complete the purchase. Please try again in a moment."
        default:
            return error.localizedDescription
        }
    }

    private func purchaseDiagnostic(for error: Error) -> String {
        let nsError = error as NSError
        let productID = selectedPackage?.storeProduct.productIdentifier ?? "unknown"
        let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError

        if let underlyingError {
            return """
            \(productID) · \(nsError.domain) \(nsError.code) · \
            \(underlyingError.domain) \(underlyingError.code)
            """
        }

        return "\(productID) · \(nsError.domain) \(nsError.code)"
    }
}
