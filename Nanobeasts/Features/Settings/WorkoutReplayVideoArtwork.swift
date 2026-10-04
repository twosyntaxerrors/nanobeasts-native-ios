import SwiftUI

@MainActor
enum WorkoutReplayVideoArtwork {
    static func chrome(payload: WorkoutSharePayload, companion: CreatureStage, unit: DistanceUnitPreference) -> UIImage? {
        render(WorkoutReplayVideoChrome(payload: payload, companion: companion, unit: unit),
               size: CGSize(width: 1080, height: 1920))
    }

    static func ending(payload: WorkoutSharePayload, companion: CreatureStage, artwork: UIImage,
                       unit: DistanceUnitPreference) -> UIImage? {
        render(WorkoutReplayEndCard(payload: payload, companion: companion, artwork: artwork, unit: unit),
               size: CGSize(width: 1080, height: 1350))
    }

    private static func render(_ view: some View, size: CGSize) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, .large))
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.uiImage
    }
}

private struct WorkoutReplayVideoChrome: View {
    let payload: WorkoutSharePayload
    let companion: CreatureStage
    let unit: DistanceUnitPreference

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 14) {
                Text("NANOBEASTS").font(NanoFont.aldrich(30)).tracking(4).foregroundStyle(NanoTheme.teal)
                Text(payload.workoutName).font(NanoFont.aldrich(54)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.65)
            }
            .frame(width: 960, alignment: .leading).offset(x: 60, y: 75)

            ReplayShareMetrics(payload: payload, unit: unit, labelSize: 24, valueSize: 43)
                .padding(30).frame(width: 960, height: 270)
                .background(RoundedRectangle(cornerRadius: 32).fill(NanoTheme.surface))
                .offset(x: 60, y: 218)

            Text("Exploring with \(companion.name)")
                .font(NanoFont.aldrich(30)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 936, alignment: .center).offset(x: 72, y: 1777)
        }
        .frame(width: 1080, height: 1920, alignment: .topLeading)
    }
}

/// Rendered once as a transparent PNG-style overlay for both replay and video.
private struct WorkoutReplayEndCard: View {
    let payload: WorkoutSharePayload
    let companion: CreatureStage
    let artwork: UIImage
    let unit: DistanceUnitPreference

    var body: some View {
        VStack(spacing: 24) {
            Text("ADVENTURE COMPLETE").font(NanoFont.aldrich(33)).tracking(3).foregroundStyle(NanoTheme.teal)
            HStack(spacing: 18) {
                Image(uiImage: artwork).resizable().scaledToFit().frame(width: 110, height: 110)
                Text(companion.name).font(NanoFont.aldrich(38)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
            Text(ReplayShareMetrics.distance(payload.distanceMiles, unit: unit))
                .font(.system(size: 110, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
            WorkoutRouteShape(coordinates: payload.route, breakIndices: payload.routeBreakIndices)
                .stroke(NanoTheme.teal, style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                .padding(38).frame(height: 460)
            ReplayShareMetrics(payload: payload, unit: unit, labelSize: 26, valueSize: 46)
                .frame(height: 230)
            Text("EVERY STEP. MORE LIFE.").font(NanoFont.aldrich(25)).tracking(3).foregroundStyle(NanoTheme.teal)
            Text("NANOBEASTS").font(NanoFont.aldrich(30)).tracking(3).foregroundStyle(.white)
        }
        .padding(54)
        .frame(width: 1080, height: 1350)
    }
}

private struct ReplayShareMetrics: View {
    let payload: WorkoutSharePayload
    let unit: DistanceUnitPreference
    let labelSize: CGFloat
    let valueSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(alignment: .top, spacing: 24) {
                metric("STEPS", payload.steps.formatted())
                metric("DISTANCE", Self.distance(payload.distanceMiles, unit: unit))
                metric("ACTIVE TIME", WorkoutMetricsFormat.time(TimeInterval(payload.elapsedSeconds)))
            }
            HStack(alignment: .top, spacing: 24) {
                metric("AVG PACE", Self.pace(payload, unit: unit))
                metric("ENERGY", "\(Int(payload.calories)) kcal")
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(NanoFont.aldrich(labelSize)).foregroundStyle(NanoTheme.secondaryText)
            Text(value).font(NanoFont.spaceMono(valueSize, bold: true)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.55)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    static func distance(_ miles: Double, unit: DistanceUnitPreference) -> String {
        String(format: "%.2f %@", miles * (unit == .kilometers ? 1.609344 : 1), unit.abbreviation.lowercased())
    }

    static func pace(_ payload: WorkoutSharePayload, unit: DistanceUnitPreference) -> String {
        guard payload.distanceMiles > 0.005 else { return "—" }
        let seconds = Int((payload.paceMinutesPerMile * 60 / (unit == .kilometers ? 1.609344 : 1)).rounded())
        return String(format: "%d:%02d/%@", seconds / 60, seconds % 60, unit.abbreviation.lowercased())
    }
}

struct WorkoutReplayVideoShare: Identifiable {
    let id = UUID()
    let url: URL
}

struct WorkoutReplayVideoShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
