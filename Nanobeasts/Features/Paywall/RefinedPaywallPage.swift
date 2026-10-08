import SwiftUI

enum PaywallDesign: String, Identifiable, CaseIterable {
    case original, refined

    var id: String { rawValue }
    var title: String { self == .original ? "OG paywall" : "New paywall" }
    var previewTitle: String { self == .original ? "OG PREVIEW" : "NEW PREVIEW" }
}

/// The comparison layout reuses checkout and offers from the existing screen.
struct RefinedPaywallPage<Header: View, Offers: View, Checkout: View>: View {
    let family: CreatureFamily
    let tint: Color
    @ViewBuilder let header: Header
    @ViewBuilder let offers: Offers
    @ViewBuilder let checkout: Checkout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 24)
            ScrollView {
                VStack(spacing: 10) {
                    Text("Your next evolution\nstarts with a walk.")
                        .font(.system(size: headlineSize, weight: .bold))
                        .tracking(-0.6).multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    PaywallEvolutionArtwork(family: family, tint: tint)

                    VStack(alignment: .leading, spacing: 8) {
                        benefit("Keep hatching and evolving")
                        benefit("Turn daily steps into progress")
                        benefit("Build your creature collection")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    offers
                    if dynamicTypeSize.isAccessibilitySize {
                        checkout.padding(.top, 12)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 12)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                checkout
                    .padding(.horizontal, 24).padding(.vertical, 8)
                    .frame(maxWidth: 520).frame(maxWidth: .infinity)
                    .background {
                        PaywallBackdrop(tint: tint).ignoresSafeArea(edges: .bottom)
                    }
                    .overlay(alignment: .top) { Color.white.opacity(0.08).frame(height: 1) }
            }
        }
    }

    private func benefit(_ title: String) -> some View {
        HStack(spacing: 12) {
            SolarImage(.checkCircle, size: 20).foregroundStyle(tint).accessibilityHidden(true)
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PaywallEvolutionArtwork: View {
    let family: CreatureFamily
    let tint: Color
    private var stages: [CreatureStage] { Array(family.stages.filter { !$0.isEgg }.prefix(2)) }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            if let first = stages.first {
                specimen(first, label: "HATCH", size: 72)
            }
            if stages.count > 1 {
                Image(systemName: "arrow.right").font(.title3.weight(.semibold))
                    .foregroundStyle(tint.opacity(0.75)).accessibilityHidden(true)
                specimen(stages[1], label: "EVOLVE", size: 92)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 90)
        .background {
            Ellipse().fill(tint.opacity(0.12)).frame(width: 240, height: 100).blur(radius: 26)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hatch and evolve your Nanobeasts by walking")
    }

    private func specimen(_ stage: CreatureStage, label: String, size: CGFloat) -> some View {
        VStack(spacing: 6) {
            CreatureArtworkView(stage: stage).frame(width: size, height: 70)
            Text(label).font(.system(size: 9, weight: .bold)).tracking(2)
                .foregroundStyle(tint.opacity(0.8))
        }
    }
}
