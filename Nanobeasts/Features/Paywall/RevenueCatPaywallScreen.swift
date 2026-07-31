import RevenueCat
import SwiftUI

struct RevenueCatPaywallScreen: View {
    private enum Plan {
        case yearly
        case monthly
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store

    let playerName: String

    @State private var offering: Offering?
    @State private var selectedPlan: Plan = .yearly
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    topBar

                    Text("YOUR NANOBEASTS ARE READY")
                        .font(NanoFont.aldrich(11))
                        .tracking(1.6)
                        .foregroundStyle(NanoTheme.teal)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(NanoTheme.teal.opacity(0.07), in: Capsule())
                        .overlay(Capsule().stroke(NanoTheme.teal.opacity(0.3)))

                    VStack(spacing: 9) {
                        Text("\(displayName), take the first step towards evolution")
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text("Turn everyday movement into a collection that grows with you.")
                            .foregroundStyle(NanoTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    VStack(spacing: 15) {
                        BenefitRow(
                            icon: "figure.walk.motion",
                            title: "Grow with your Nanobeasts",
                            detail: "Every step counts toward evolving your Nanobeasts, while supporting your own goals."
                        )
                        BenefitRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Progress you can see",
                            detail: "Track the stats you care about, making it easy to stay consistent and see progress."
                        )
                        BenefitRow(
                            icon: "sparkles",
                            title: "New drops to keep you motivated",
                            detail: "New eggs and evolutions updated regularly, so you never run out."
                        )
                    }
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26).stroke(NanoTheme.teal.opacity(0.22)))
                    .padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        PlanCard(
                            eyebrow: "YEARLY",
                            price: yearlyPrice,
                            detail: yearlyDetail,
                            badge: "SAVE 54%",
                            selected: selectedPlan == .yearly
                        ) {
                            withAnimation(.snappy(duration: 0.25)) {
                                selectedPlan = .yearly
                            }
                        }

                        PlanCard(
                            eyebrow: "MONTHLY",
                            price: monthlyPrice,
                            detail: "Billed monthly",
                            badge: nil,
                            selected: selectedPlan == .monthly
                        ) {
                            withAnimation(.snappy(duration: 0.25)) {
                                selectedPlan = .monthly
                            }
                        }
                    }
                    .padding(.horizontal, 18)

                    Label("Cancel anytime  •  No 2,500-step cap", systemImage: "checkmark.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NanoTheme.secondaryText)

#if DEBUG
                    if isUsingRevenueCatTestStore {
                        Label("REVENUECAT TEST PURCHASE • NO CHARGE", systemImage: "checkmark.seal.fill")
                            .font(NanoFont.aldrich(9))
                            .tracking(0.7)
                            .foregroundStyle(NanoTheme.teal)
                    }
#endif

                    Button {
                        Task { await purchaseSelectedPlan() }
                    } label: {
                        HStack(spacing: 9) {
                            if isPurchasing {
                                ProgressView()
                                    .tint(.black)
                            }
                            Text(isPurchasing ? "Connecting securely…" : "Start My Evolution")
                                .font(.headline)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            LinearGradient(
                                colors: [NanoTheme.teal, NanoTheme.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing || selectedPackage == nil)
                    .opacity(selectedPackage == nil && offering != nil ? 0.5 : 1)
                    .padding(.horizontal, 18)

                    if offering == nil && errorMessage == nil {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading subscription plans…")
                        }
                        .font(.caption)
                        .foregroundStyle(NanoTheme.secondaryText)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(NanoTheme.pink)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    HStack(spacing: 12) {
                        Link("Privacy Policy", destination: URL(string: "https://nanobeasts.app/privacy")!)
                        Text("•")
                        Link("Terms of Service", destination: URL(string: "https://nanobeasts.app/terms")!)
                        Text("•")
                        Button(isRestoring ? "Restoring…" : "Restore") {
                            Task { await restore() }
                        }
                        .disabled(isRestoring)
                    }
                    .font(.caption2)
                    .foregroundStyle(NanoTheme.secondaryText)

                    Text(selectedPlan == .yearly ? yearlyFooter : "Monthly access renews automatically until cancelled.")
                        .font(.caption)
                        .foregroundStyle(NanoTheme.secondaryText)
                        .padding(.bottom, 16)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await loadOffering()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(NanoTheme.secondaryText)

            Spacer()

            Image(systemName: "sparkles")
                .foregroundStyle(NanoTheme.teal)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var displayName: String {
        playerName.isEmpty ? "Researcher" : playerName
    }

    private var yearlyPrice: String {
        yearlyPackage.map {
            "\($0.storeProduct.localizedPriceString)/year"
        } ?? "$32.99/year"
    }

    private var monthlyPrice: String {
        monthlyPackage.map {
            "\($0.storeProduct.localizedPriceString)/month"
        } ?? "$5.99/month"
    }

    private var yearlyDetail: String {
        if let annual = yearlyPackage?.storeProduct.price,
           let monthly = monthlyPackage?.storeProduct.price {
            let annualValue = NSDecimalNumber(decimal: annual).doubleValue
            let monthlyValue = NSDecimalNumber(decimal: monthly).doubleValue
            guard monthlyValue > 0 else { return "Billed yearly" }
            let savings = max(0, Int((1 - annualValue / (monthlyValue * 12)) * 100))
            return savings > 0 ? "Best value • save \(savings)%" : "Billed yearly"
        }
        return "$2.74/month billed yearly"
    }

    private var yearlyFooter: String {
        "Just \(yearlyPrice) — auto-renews yearly until cancelled."
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
        errorMessage = nil
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
        } catch {
            errorMessage = "RevenueCat could not load the plans. Please check your connection and try again."
        }
    }

    @MainActor
    private func purchaseSelectedPlan() async {
        guard let selectedPackage else { return }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: selectedPackage)
            guard !result.userCancelled else { return }

            store.applyRevenueCatCustomerInfo(result.customerInfo)
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
        isRestoring = true
        errorMessage = nil
        defer { isRestoring = false }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            store.applyRevenueCatCustomerInfo(customerInfo)
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

private struct BenefitRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(width: 34, height: 34)
                .background(NanoTheme.teal, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(NanoTheme.secondaryText)
                    .lineSpacing(3)
            }
            Spacer()
        }
    }
}

private struct PlanCard: View {
    let eyebrow: String
    let price: String
    let detail: String
    let badge: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? NanoTheme.teal : NanoTheme.secondaryText)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(eyebrow)
                            .font(NanoFont.aldrich(12))
                            .tracking(1.2)
                        if let badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(NanoTheme.teal, in: Capsule())
                        }
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(NanoTheme.secondaryText)
                }
                Spacer()
                Text(price)
                    .font(.subheadline.monospacedDigit().bold())
                    .multilineTextAlignment(.trailing)
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(
                selected ? NanoTheme.teal.opacity(0.10) : NanoTheme.surface,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selected ? NanoTheme.teal : NanoTheme.border, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
