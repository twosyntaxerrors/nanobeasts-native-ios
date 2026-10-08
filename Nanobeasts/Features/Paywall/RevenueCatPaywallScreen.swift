import RevenueCat
import SwiftUI

struct RevenueCatPaywallScreen: View {
    private enum Plan { case monthly, lifetime }
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
    var design: PaywallDesign = .original

    @AppStorage("nanobeasts.notifications.setup-reminders") private var setupReminders = false
    @State private var offering: Offering?
    @State private var winbackOffering: Offering?
    @State private var showsWinback = false
    @State private var hasShownWinback = false
    @State private var selectedPlan: Plan = .lifetime
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var isLoadingPlans = true
    @State private var errorMessage: String?
    @State private var previewNotice: String?

    private var copy: OnboardingCopy {
        .forGoals(selectedGoals, primaryGoal: primaryGoal, blockers: selectedBlockers)
    }

    var body: some View {
        paywallContent
        .blur(radius: showsWinback ? 10 : 0)
        .disabled(showsWinback)
        .accessibilityHidden(showsWinback)
        .overlay {
            if showsWinback {
                ZStack {
                    Color.black.opacity(0.78).ignoresSafeArea()
                    winbackPopup
                }.transition(.opacity)
            }
        }
        .background { PaywallBackdrop(tint: NanoTheme.teal).ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .task { await loadOffering() }
        .alert("Preview", isPresented: Binding(get: { previewNotice != nil },
            set: { if !$0 { previewNotice = nil } })) {
            Button("OK") { previewNotice = nil }
        } message: { Text(previewNotice ?? "") }
    }

    @ViewBuilder private var paywallContent: some View {
        switch design {
        case .original:
            PaywallPage(copy: copy, firstName: playerName, tint: NanoTheme.teal,
                        milestone: isPreview ? previewMilestone : nil) {
                topBar
            } offers: {
                offerSection
            } checkout: {
                purchaseFooter
            }
        case .refined:
            RefinedPaywallPage(family: evolutionFamily, tint: NanoTheme.teal) {
                topBar
            } offers: {
                offerSection
                if let lifetimeComparison, selectedPlan == .lifetime {
                    Text(lifetimeComparison)
                        .font(.caption).foregroundStyle(NanoTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } checkout: {
                purchaseFooter
            }
        }
    }

    private var evolutionFamily: CreatureFamily {
        if store.currentFamily.stages.filter({ !$0.isEgg }).count >= 2 {
            return store.currentFamily
        }
        return store.catalog.families.first { $0.stages.filter { !$0.isEgg }.count >= 2 }
            ?? store.currentFamily
    }

    private var winbackPopup: some View {
        LifetimeWinbackPopup(amount: winbackAmount, standardAmount: lifetimeAmount,
            tint: NanoTheme.teal, discountPercent: winbackDiscountPercent, errorMessage: errorMessage,
            isPurchasing: isPurchasing, isDisabled: isPurchasing || isRestoring,
            onPurchase: { Task { await purchaseSelectedPlan(package: winbackPackage) } },
            onDismiss: closePaywall)
        .padding(.horizontal, 24)
    }

    private var offerSection: some View {
        VStack(spacing: 16) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 18)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                PaywallPlanCard(title: "MONTHLY", price: monthlyAmount, period: "/month",
                    detail: "Billed monthly", selected: selectedPlan == .monthly, tint: NanoTheme.teal) {
                    withAnimation(.snappy(duration: 0.25)) { selectedPlan = .monthly }
                }
                PaywallPlanCard(title: "LIFETIME", price: lifetimeAmount,
                    period: standardPackage == nil || isLoadingPlans ? "" : " once",
                    detail: "Yours forever. No renewal.", badge: "BEST VALUE",
                    selected: selectedPlan == .lifetime, tint: NanoTheme.teal) {
                    withAnimation(.snappy(duration: 0.25)) { selectedPlan = .lifetime }
                }
            }
            .disabled(isPurchasing || isRestoring)
            .padding(.top, 10)

            if isLoadingPlans {
                HStack(spacing: 8) { ProgressView(); Text("Loading plans…") }
                    .font(.caption).foregroundStyle(NanoTheme.secondaryText)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(NanoTheme.pink)
                    .multilineTextAlignment(.center)
                if !isLoadingPlans && (monthlyPackage == nil || standardPackage == nil) {
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
                renewalNotice: purchaseDisclosure, tint: NanoTheme.teal,
                reassurance: selectedPlan == .monthly ? "Cancel anytime" : "One-time purchase",
                isPurchasing: isPurchasing, isRestoring: isRestoring,
                isDisabled: isPurchasing || isRestoring || isLoadingPlans || selectedPackage == nil,
                isRestoreDisabled: isPurchasing || isRestoring || isLoadingPlans,
                spacing: design == .refined ? 8 : 12,
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
                if !hasShownWinback, canOfferWinback {
                    hasShownWinback = true
                    errorMessage = nil
                    showsWinback = true
                } else { closePaywall() }
            } label: {
                SolarImage(.closeCircle, size: 24)
                    .frame(width: 44, height: 44)
            }
            .disabled(isPurchasing || isRestoring)
            .accessibilityLabel(isPreview ? "Close preview paywall" : "Back to your plan")
            .buttonStyle(.plain).foregroundStyle(NanoTheme.secondaryText)
            Spacer()
            if isPreview {
                Text("\(design.previewTitle) · NO CHARGE").font(.system(size: 9, weight: .medium))
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

    private var lifetimeAmount: String {
        guard !isLoadingPlans else { return "Loading…" }
        return standardPackage?.storeProduct.localizedPriceString ?? "Unavailable"
    }

    private var purchaseButtonTitle: String {
        if isLoadingPlans { return "Loading…" }
        if selectedPackage == nil { return "Plan unavailable" }
        return selectedPlan == .monthly ? "Start your journey" : "Unlock Forever"
    }

    private var lifetimeComparison: String? {
        guard !isLoadingPlans, let lifetime = standardPackage?.storeProduct,
              let monthly = monthlyPackage?.storeProduct, monthly.price > 0,
              let currency = lifetime.currencyCode, currency == monthly.currencyCode else { return nil }
        let payments = NSDecimalNumber(decimal: lifetime.price / monthly.price).doubleValue
        guard payments.isFinite, payments >= 1 else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        guard let count = formatter.string(from: NSNumber(value: payments.rounded())) else { return nil }
        return "About \(count) monthly payments. Yours forever."
    }

    private var purchaseSummary: String {
        guard !isLoadingPlans, selectedPackage != nil else { return "" }
        return selectedPlan == .monthly
            ? "\(monthlyAmount)/month, billed today."
            : "\(lifetimeAmount), paid once for lifetime access."
    }

    private var purchaseDisclosure: String {
        guard !isLoadingPlans, selectedPackage != nil else { return "" }
        return selectedPlan == .monthly
            ? "Renews automatically until cancelled."
            : "Billed today. No recurring payments."
    }

    private var monthlyAmount: String {
        monthlyPackage?.storeProduct.localizedPriceString ?? (isLoadingPlans ? "Loading…" : "Unavailable")
    }

    private var winbackAmount: String {
        winbackPackage?.storeProduct.localizedPriceString ?? "Unavailable"
    }

    private var winbackDiscountPercent: Int? {
        guard canOfferWinback, let standard = standardPackage?.storeProduct,
              let winback = winbackPackage?.storeProduct else { return nil }
        // Round down so the headline never overstates the localized discount.
        let percentage = NSDecimalNumber(decimal: (standard.price - winback.price) / standard.price * 100).doubleValue
        guard percentage.isFinite, percentage >= 1, percentage < 100 else { return nil }
        return Int(percentage.rounded(.down))
    }

    private var monthlyPackage: Package? {
        offering?.availablePackages.first {
            $0.storeProduct.productIdentifier == AppStore.premiumMonthlyProductID
                && $0.storeProduct.subscriptionPeriod?.unit == .month
                && $0.storeProduct.subscriptionPeriod?.value == 1
        }
    }

    private var standardPackage: Package? {
        offering?.availablePackages.first {
            $0.storeProduct.productIdentifier == AppStore.premiumLifetimeProductID
                && $0.storeProduct.productType == .nonConsumable
        }
    }

    private var winbackPackage: Package? {
        winbackOffering?.availablePackages.first {
            $0.storeProduct.productIdentifier == AppStore.premiumLifetimeWinbackProductID
                && $0.storeProduct.productType == .nonConsumable
        }
    }

    private var selectedPackage: Package? {
        selectedPlan == .monthly ? monthlyPackage : standardPackage
    }

    private var canOfferWinback: Bool {
        guard !isLoadingPlans, let standard = standardPackage?.storeProduct,
              let winback = winbackPackage?.storeProduct,
              let currency = standard.currencyCode, currency == winback.currencyCode else { return false }
        return winback.price > 0 && standard.price > winback.price
    }

    private func closePaywall() {
        if isPreview, let onPreviewClose { onPreviewClose() }
        else { dismiss() }
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
        errorMessage = nil
        defer { isLoadingPlans = false }
        // Replay products never reach the real purchase action.
        if isPreview {
            offering = PaywallPreviewOffering.make()
            winbackOffering = PaywallPreviewOffering.make(isWinback: true)
            return
        }
        guard Purchases.isConfigured else {
            errorMessage = "RevenueCat is not configured for this build."
            return
        }

        do {
            let offerings = try await Purchases.shared.offerings()
            guard !Task.isCancelled else { return }
            offering = offerings.all[AppStore.lifetimeOfferingID]
            winbackOffering = offerings.all[AppStore.lifetimeWinbackOfferingID]
            if standardPackage == nil || monthlyPackage == nil {
                errorMessage = "Plans are temporarily unavailable. Please try again shortly."
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Couldn’t load plans. Check your connection and try again."
        }
    }

    @MainActor
    private func purchaseSelectedPlan(package: Package? = nil) async {
        guard !isLoadingPlans, !isPurchasing, !isRestoring, let purchasePackage = package ?? selectedPackage else { return }
        if isPreview {
            if let onPreviewPurchase { onPreviewPurchase() }
            else {
                previewNotice = "Preview only: \(purchasePackage.storeProduct.localizedPriceString)\(purchasePackage.storeProduct.productType == .nonConsumable ? " once for lifetime access" : " per month"). No purchase was made."
            }
            return
        }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: purchasePackage)
            guard !result.userCancelled else { return }

            await store.applyRevenueCatPurchase(result.customerInfo)
            if store.isPremium {
                dismiss()
            } else {
                errorMessage = "Your purchase is still pending confirmation."
            }
        } catch {
            errorMessage = purchaseErrorMessage(for: error, productID: purchasePackage.storeProduct.productIdentifier)
        }
    }

    @MainActor
    private func restore() async {
        guard !isPreview else {
            previewNotice = "Restore is simulated in this preview. Your existing purchases are unchanged."
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
                errorMessage = "No Nanobeasts Pro purchase was found for this Apple Account."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func purchaseErrorMessage(for error: Error, productID: String) -> String {
#if DEBUG
        let nsError = error as NSError
        let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
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
            let diagnostic = purchaseDiagnostic(for: error, productID: productID)
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

    private func purchaseDiagnostic(for error: Error, productID: String) -> String {
        let nsError = error as NSError
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
