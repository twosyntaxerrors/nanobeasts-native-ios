// Uses shipping SwiftUI components on macOS. No iOS Simulator is started.
import AppKit
import SwiftUI

@main struct RenderPaywallGoalDesign {
    static let tint = Color(red: 0.33, green: 0.88, blue: 0.81)
    @MainActor static func main() throws {
        let _ = NSApplication.shared
        let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Design/Onboarding-Challenge-2026-09-09")
        let heavy = WalkingPlanComparison(baselineSteps: 12500, targetSteps: 15000)
        let challenge = WalkingEvolutionChallenge(dailyTarget: 15000, averageStepsPerEvolution: 28234)
        let fitness = OnboardingCopy.forGoals(["Get Fit"])
        for elapsed in [0.0, 1.8, 3.1, 4.2] {
            try save(WalkingPlanPreparationContent(playerName: "Sinatra",
                goal: "Lose body fat, keep muscle", tint: tint,
                elapsed: elapsed).padding(24).frame(width: 390),
                to: folder.appending(path: "preparation-\(elapsed).png"))
        }
        for page in WalkingPlanPage.allCases {
            try save(WalkingPlanPageContent(page: page, comparison: heavy,
                headline: fitness.planHeadline, detail: fitness.planDetail, comparisonHeadline: fitness.comparisonTitle,
                tint: tint, benefits: fitness.paywallBenefits, evolutionChallenge: challenge)
                .padding(24).frame(width: 390), to: folder.appending(path: "plan-heavy-\(page.rawValue).png"))
        }
        try save(WalkingPlanPreparationContent(playerName: "Alexandria-Cassandra",
            goal: "Lose body fat, keep muscle", tint: tint,
            elapsed: 2.0).padding(24).frame(width: 320), to: folder.appending(path: "preparation-compact.png"))
        for (name, width, height, goals, primary, blockers, typeSize) in [
            ("weight-bored", 390.0, 760.0, Set(["Lose Weight"]), "Lose Weight", Set(["Walking feels boring"]), DynamicTypeSize.large),
            ("weight-all-obstacles", 390.0, 760.0, Set(WalkingMotivation.allCases.map(\.rawValue)), "Lose Weight", Set(["Walking feels boring", "Hard to stay consistent", "No way to track progress", "Forget to move", "Don’t see results fast enough"]), .large),
            ("fitness", 390.0, 760.0, Set(["Get Fit"]), "Get Fit", Set(["Hard to stay consistent"]), .large),
            ("habit-compact", 320.0, 650.0, Set(["Walk More"]), "Walk More", Set(["Forget to move"]), .large),
            ("fun-large-text", 390.0, 760.0, Set(["Have Fun"]), "Have Fun", Set(["Walking feels boring"]), .accessibility1)
        ] {
            let copy = OnboardingCopy.forGoals(goals, primaryGoal: primary, blockers: blockers)
            let opening = copy.planOpening(blockers: blockers)
            let content = PaywallPageContent(copy: copy, firstName: "Sinatra", tint: tint, minimumHeight: height) {
                HStack {
                    Image(systemName: "xmark").font(.system(size: 15)).frame(width: 44, height: 44)
                    Spacer()
                    Text("PREVIEW · NO CHARGE").font(.system(size: 9, weight: .medium))
                }.foregroundStyle(.white.opacity(0.55))
            } offers: {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 18)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    PaywallPlanCard(title: "MONTHLY", price: "$4.99", period: "/month", detail: "No free trial", selected: false, tint: tint) {}
                    PaywallPlanCard(title: "YEARLY", price: "$29.99", period: "/year", detail: "Free trial for 7 days", badge: "SAVE 50%", highlightsDetail: true, selected: true, tint: tint) {}
                }.padding(.top, 10)
            } checkout: {
                PaywallCheckout(title: "Try for $0", summary: "7 days free, then $29.99/year.",
                    renewalNotice: "Renews automatically. Cancel at least 24 hours before your trial ends to avoid being charged.",
                    tint: tint, onPurchase: {}, onRestore: {})
            }
            .frame(width: width)
            .background(PaywallBackdrop(tint: tint))
            .environment(\.dynamicTypeSize, typeSize)
            try save(content, to: folder.appending(path: "paywall-\(name).png"))
            // Unclipped component renders expose any long-name/large-text truncation.
            try save(PaywallIntroduction(copy: copy, tint: tint, firstName: name == "fun-large-text" ? "Alexandria-Cassandra" : "Sinatra")
                .padding(24).frame(width: width).environment(\.dynamicTypeSize, typeSize),
                to: folder.appending(path: "benefits-\(name).png"))
            if name == "weight-bored" || name == "fitness" {
                try save(WalkingPlanPageContent(page: .target,
                    comparison: .init(baselineSteps: 6500, targetSteps: 8000),
                    headline: opening.headline, detail: opening.detail, comparisonHeadline: copy.comparisonTitle,
                    tint: tint, benefits: copy.paywallBenefits, evolutionChallenge: .init(dailyTarget: 8000, averageStepsPerEvolution: 28234)).padding(24).frame(width: width),
                    to: folder.appending(path: "plan-\(name).png"))
            }
        }
    }
    @MainActor static func save<V: View>(_ content: V, to url: URL) throws {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, .dark)
            .background(Color(red: 0.025, green: 0.03, blue: 0.035)))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { fatalError("No render") }
        try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: url)
        print("\(url.lastPathComponent): \(cg.width)x\(cg.height)")
    }
}
