// Review the shipping SwiftUI chart without launching Simulator.
import AppKit
import SwiftUI

@main struct RenderOnboardingComparison {
    @MainActor static func main() throws {
        let _ = NSApplication.shared
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let tint = Color(red: 0.33, green: 0.88, blue: 0.81)
        for (name, width, baseline, target, goal, elapsed) in [
            ("weight", 390.0, 3500, 5000, "Lose Weight", 3.6),
            ("experienced", 390.0, 12500, 15000, "Get Fit", 3.6),
            ("compact", 320.0, 1500, 3500, "Walk More", 3.6),
            ("fun", 390.0, 3500, 4500, "Have Fun", 3.6),
            ("reveal-middle", 390.0, 3500, 5000, "Lose Weight", 2.0)
        ] {
            let copy = OnboardingCopy.forGoals([goal])
            let content = WalkingPlanPageContent(page: .comparison,
                comparison: .init(baselineSteps: baseline, targetSteps: target),
                headline: copy.planHeadline, detail: copy.planDetail,
                comparisonHeadline: copy.comparisonTitle, tint: tint, elapsed: elapsed,
                comparisonDetail: copy.comparisonDetail)
            let renderer = ImageRenderer(content: content.padding(24).frame(width: width)
                .background(Color(red: 0.025, green: 0.032, blue: 0.034))
                .environment(\.colorScheme, .dark))
            renderer.scale = 2
            guard let image = renderer.cgImage else { fatalError("Render failed") }
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try data.write(to: folder.appending(path: "\(name).png"))
            print("Rendered \(name): \(image.width) × \(image.height)")
        }
    }
}
