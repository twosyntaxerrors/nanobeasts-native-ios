// Render the shipping presentation components with macOS SwiftUI, without Simulator.
// These are content/layout review images, not iPhone screenshots. Platform text
// styles differ; physical iPhone testing remains the final visual acceptance.
import AppKit
import SwiftUI

@main
struct RenderOnboardingDesign {
    @MainActor static func main() throws {
        let _ = NSApplication.shared
        let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Design/Onboarding-Single-Plan-2026-09-09")
        let tint = Color(red: 0.33, green: 0.88, blue: 0.81)
        for (name, baseline, target, width, goals) in [
            ("plan-390", 3500, 5000, 390.0, Set(["Lose Weight"])),
            ("plan-active-390", 9000, 10000, 390.0, Set(["Get Fit"])),
            ("plan-320", 1500, 4000, 320.0, Set(["Walk More"]))
        ] {
            let copy = OnboardingCopy.forGoals(goals)
            let content = OnboardingPlanContent(
                comparison: WalkingPlanComparison(baselineSteps: baseline, targetSteps: target),
                headline: copy.planOpening(blockers: ["No way to track progress"]).headline, detail: copy.planOpening(blockers: ["No way to track progress"]).detail, tint: tint, comparisonHeadline: copy.comparisonTitle)
            try save(content, width: width, file: folder.appending(path: "\(name).png"))
        }
        let allGoals = Set(WalkingMotivation.allCases.map(\.rawValue))
        for mainGoal in WalkingMotivation.allCases {
            let copy = OnboardingCopy.forGoals(allGoals, primaryGoal: mainGoal.rawValue)
            let opening = copy.planOpening(blockers: ["No way to track progress"])
            try save(OnboardingPlanContent(comparison: .init(baselineSteps: 3500, targetSteps: 5500),
                headline: opening.headline, detail: opening.detail, tint: tint, comparisonHeadline: copy.comparisonTitle),
                width: 390, file: folder.appending(path: "all-goals-plan-\(mainGoal.rawValue).png"))
            try save(PaywallIntroduction(copy: copy, tint: tint, firstName: "Ervenst"), width: 390,
                file: folder.appending(path: "all-goals-paywall-\(mainGoal.rawValue).png"))
        }
        for (label, baseline, target, width, goal) in [
            ("weight", 3500, 5500, 390.0, "Lose Weight"),
            ("active", 9000, 10000, 390.0, "Get Fit"),
            ("compact", 1500, 4000, 320.0, "Walk More")
        ] {
            let copy = OnboardingCopy.forGoals([goal])
            let opening = copy.planOpening(blockers: ["No way to track progress"])
            for page in WalkingPlanPage.allCases {
                try save(WalkingPlanPageContent(page: page, comparison: .init(baselineSteps: baseline, targetSteps: target),
                    headline: opening.headline, detail: opening.detail, comparisonHeadline: copy.comparisonTitle, tint: tint),
                    width: width, file: folder.appending(path: "page-\(label)-\(page.rawValue).png"))
            }
        }
        for elapsed in [0.0, 0.7, 2.0, 3.6] {
            let copy = OnboardingCopy.forGoals(["Walk More"])
            try save(OnboardingPlanContent(
                comparison: WalkingPlanComparison(baselineSteps: 3500, targetSteps: 5000),
                headline: copy.planOpening(blockers: ["No way to track progress"]).headline, detail: copy.planOpening(blockers: ["No way to track progress"]).detail, tint: tint, elapsed: elapsed),
                width: 390, file: folder.appending(path: "reveal-\(elapsed).png"))
        }
        for (name, goals) in [("weight", Set(["Lose Weight"])), ("fitness", Set(["Get Fit"])), ("habit", Set(["Walk More"]))] {
            try save(PaywallIntroduction(copy: .forGoals(goals), tint: tint, firstName: "Ervenst"), width: 390,
                     file: folder.appending(path: "paywall-\(name).png"))
        }
    }

    @MainActor private static func save<V: View>(_ content: V, width: CGFloat, file: URL) throws {
        let renderer = ImageRenderer(content: content
            .padding(.horizontal, 26).padding(.vertical, 28)
            .frame(width: width)
            .background(Color(red: 0.025, green: 0.032, blue: 0.034))
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { fatalError("Unable to render \(file.lastPathComponent)") }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
        print("Rendered \(file.lastPathComponent): \(cgImage.width)x\(cgImage.height)")
    }
}
