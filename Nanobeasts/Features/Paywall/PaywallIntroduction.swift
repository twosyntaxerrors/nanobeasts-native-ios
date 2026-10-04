import SwiftUI

/// Shared by the shipping paywall and the lightweight macOS layout renderer.
struct PaywallIntroduction: View {
    let copy: OnboardingCopy
    let tint: Color
    var firstName: String = ""
    var milestone: String? = nil
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 30

    private var headline: AttributedString {
        var value = AttributedString(copy.personalizedPaywallHeadline(name: firstName))
        value.foregroundColor = .white
        if let range = value.range(of: copy.paywallAccent, options: .backwards) {
            value[range].foregroundColor = tint
        }
        return value
    }

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 20) {
                Text(milestone ?? "YOUR PLAN IS READY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(tint.opacity(0.07), in: Capsule())
                    .overlay(Capsule().stroke(tint.opacity(0.24), lineWidth: 1))
                Text(headline)
                    .font(.system(size: headlineSize, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(copy.paywallDetail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            OnboardingBenefitList(benefits: copy.paywallBenefits, tint: tint)
        }
        .frame(maxWidth: .infinity)
    }
}

struct OnboardingBenefitList: View {
    let benefits: [OnboardingCopy.Benefit]
    let tint: Color
    var spacing: CGFloat = 24
    @ScaledMetric(relativeTo: .subheadline) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .footnote) private var detailSize: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(benefits) { item in
                HStack(alignment: .top, spacing: 14) {
                    SolarImage(.checkCircle, size: 25)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 22, height: 23)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.system(size: titleSize, weight: .bold))
                            .foregroundStyle(.white)
                        Text(item.detail)
                            .font(.system(size: detailSize))
                            .foregroundStyle(.white.opacity(0.63))
                            .lineSpacing(2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct PaywallPage<Header: View, Offers: View, Checkout: View>: View {
    let copy: OnboardingCopy
    let firstName: String
    let tint: Color
    var milestone: String? = nil
    @ViewBuilder let header: Header
    @ViewBuilder let offers: Offers
    @ViewBuilder let checkout: Checkout

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                PaywallPageContent(copy: copy, firstName: firstName, tint: tint, milestone: milestone,
                    minimumHeight: geometry.size.height, header: { header },
                    offers: { offers }, checkout: { checkout })
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// Layout-only content also renders without a platform scroll-view wrapper.
struct PaywallPageContent<Header: View, Offers: View, Checkout: View>: View {
    let copy: OnboardingCopy
    let firstName: String
    let tint: Color
    var milestone: String? = nil
    var minimumHeight: CGFloat = 0
    @ViewBuilder let header: Header
    @ViewBuilder let offers: Offers
    @ViewBuilder let checkout: Checkout

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.bottom, 12)
            PaywallIntroduction(copy: copy, tint: tint, firstName: firstName, milestone: milestone)
            Spacer(minLength: 24)
            offers
            checkout.padding(.top, 18)
        }
        .padding(.horizontal, 24).padding(.bottom, 18)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .top)
    }
}

struct PaywallPlanCard: View {
    let title: String
    let price: String
    let period: String
    let detail: String
    var badge: String? = nil
    var accessibilityBillingDetail: String? = nil
    var highlightsDetail = false
    let selected: Bool
    let tint: Color
    let action: () -> Void
    @ScaledMetric(relativeTo: .title2) private var priceSize: CGFloat = 25

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .bold)).tracking(1.5)
                    .foregroundStyle(selected ? .white : .white.opacity(0.65))
                Text("\(Text(price).font(.system(size: priceSize, weight: .bold)))\(Text(period).font(.caption))")
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption2.weight(highlightsDetail ? .semibold : .regular))
                    .foregroundStyle(highlightsDetail ? tint : .white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8).padding(.top, 26).padding(.bottom, 15)
            .frame(maxWidth: .infinity, minHeight: 115)
            .background(selected ? tint.opacity(0.07) : Color.white.opacity(0.025),
                        in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20)
                .stroke(selected ? tint : Color.white.opacity(0.15), lineWidth: selected ? 2 : 1))
            .overlay(alignment: .top) {
                if let badge {
                    Text(badge).font(.system(size: 10, weight: .bold)).tracking(0.5)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(tint, in: Capsule()).offset(y: -10)
                }
            }
            .overlay(alignment: .topTrailing) {
                Group {
                    if selected { SolarImage(.checkCircle, size: 22) }
                    else { Circle().stroke(lineWidth: 1.5).frame(width: 18, height: 18) }
                }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? tint : .white.opacity(0.28))
                    .padding(10).accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(price)\(period). \(detail). \(accessibilityBillingDetail ?? ""). \(badge ?? "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A quiet, static field of stars echoes the reference without a busy grid.
struct PaywallBackdrop: View {
    let tint: Color
    var body: some View {
        Color(red: 0.025, green: 0.03, blue: 0.035)
            .overlay {
                Canvas { context, size in
                    for index in 0..<180 {
                        let x = CGFloat((index * 137 + 41) % 997) / 997 * size.width
                        let y = CGFloat((index * 283 + 73) % 991) / 991 * size.height
                        let diameter: CGFloat = index % 9 == 0 ? 1.5 : 0.8
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                                     with: .color(tint.opacity(index % 9 == 0 ? 0.18 : 0.08)))
                    }
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

struct PaywallCheckout: View {
    let title: String
    let summary: String
    let renewalNotice: String
    let tint: Color
    var billingPrice: String? = nil
    var billingLeadIn: String = ""
    var isPurchasing = false
    var isRestoring = false
    var isDisabled = false
    var isRestoreDisabled = false
    let onPurchase: () -> Void
    let onRestore: () -> Void
    @ScaledMetric(relativeTo: .title2) private var billingPriceSize: CGFloat = 28

    var body: some View {
        VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Label { Text("Cancel anytime") } icon: { SolarImage(.checkCircle, size: 18) }
                    Text("·")
                    Text("Made in USA 🇺🇸")
                }.fixedSize()
                VStack(spacing: 6) {
                    Label { Text("Cancel anytime") } icon: { SolarImage(.checkCircle, size: 18) }
                    Text("Made in USA 🇺🇸")
                }
            }
            .font(.caption).foregroundStyle(.white.opacity(0.7))
            Button(action: onPurchase) {
                HStack(spacing: 9) {
                    if isPurchasing { ProgressView().tint(.black) }
                    Text(isPurchasing ? "Connecting securely…" : title).font(.headline)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.vertical, 2)
                .background(tint, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain).disabled(isDisabled)
            .opacity(isDisabled && !isPurchasing && !isRestoring ? 0.5 : 1)
            if let billingPrice {
                VStack(spacing: 4) {
                    Text(billingLeadIn).font(.caption)
                    Text(billingPrice).font(.system(size: billingPriceSize, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore).accessibilityLabel(summary)
            } else if !summary.isEmpty {
                Text(summary).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { legalActions }.fixedSize()
                VStack(spacing: 0) { legalActions }
            }
            .buttonStyle(.plain)
            .font(.caption2).foregroundStyle(.white.opacity(0.6))
            Text(renewalNotice).font(.caption2).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var legalActions: some View {
        Link("Privacy", destination: URL(string: "https://nanobeasts.app/privacy")!)
            .frame(minWidth: 44, minHeight: 44)
        Link("Terms", destination: URL(string: "https://nanobeasts.app/terms")!)
            .frame(minWidth: 44, minHeight: 44)
        Button(isRestoring ? "Restoring…" : "Restore", action: onRestore)
            .disabled(isRestoreDisabled).frame(minWidth: 44, minHeight: 44)
    }
}
