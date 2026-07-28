import SwiftUI
import WidgetKit

@main
struct NanobeastsWidgetBundle: WidgetBundle {
    var body: some Widget {
        NanobeastsProgressWidget()
    }
}

struct NanobeastsProgressWidget: Widget {
    let kind = WidgetSnapshotStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NanobeastsTimelineProvider()) { entry in
            NanobeastsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetPalette.background
                }
        }
        .configurationDisplayName("Nanobeasts Progress")
        .description("See today’s steps, evolution progress, and current Nanobeast.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct NanobeastsWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let artworkData: Data?
}

struct NanobeastsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NanobeastsWidgetEntry {
        NanobeastsWidgetEntry(
            date: Date(),
            snapshot: .placeholder,
            artworkData: nil
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (NanobeastsWidgetEntry) -> Void
    ) {
        let snapshot = context.isPreview ? WidgetSnapshot.placeholder : WidgetSnapshotStore.load()
        completion(
            NanobeastsWidgetEntry(
                date: Date(),
                snapshot: snapshot,
                artworkData: context.isPreview ? nil : artworkData(for: snapshot)
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<NanobeastsWidgetEntry>) -> Void
    ) {
        let snapshot = WidgetSnapshotStore.load()
        let entry = NanobeastsWidgetEntry(
            date: Date(),
            snapshot: snapshot,
            artworkData: artworkData(for: snapshot)
        )
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            ?? Date().addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func artworkData(for snapshot: WidgetSnapshot) -> Data? {
        guard let filename = snapshot.artworkFilename else { return nil }
        return WidgetSnapshotStore.loadArtworkData(filename: filename)
    }
}

private struct NanobeastsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NanobeastsWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                small
            case .systemMedium:
                medium
            case .accessoryCircular:
                accessoryCircular
            case .accessoryRectangular:
                accessoryRectangular
            case .accessoryInline:
                accessoryInline
            default:
                small
            }
        }
        .widgetURL(URL(string: "nanobeasts://home"))
    }

    private var small: some View {
        VStack(spacing: 7) {
            HStack {
                Text("NANOBEASTS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(WidgetPalette.teal)
                Spacer()
                Text("\(entry.snapshot.streak)D")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(WidgetPalette.orange)
            }

            ZStack {
                EvolutionRing(progress: entry.snapshot.evolutionProgress, width: 8)
                WidgetCreatureArtwork(data: entry.artworkData)
                    .padding(14)
            }

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(entry.snapshot.todaySteps.formatted())
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("/ \(entry.snapshot.dailyGoal.formatted())")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WidgetPalette.secondary)
            }
        }
        .padding(2)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            ZStack {
                EvolutionRing(progress: entry.snapshot.evolutionProgress, width: 9)
                WidgetCreatureArtwork(data: entry.artworkData)
                    .padding(17)
            }
            .frame(width: 116, height: 116)

            VStack(alignment: .leading, spacing: 8) {
                Text(entry.snapshot.creatureName.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(WidgetPalette.teal)
                    .lineLimit(1)

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(entry.snapshot.todaySteps.formatted())
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("STEPS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(WidgetPalette.secondary)
                }

                ProgressView(value: entry.snapshot.goalProgress)
                    .tint(WidgetPalette.teal)

                HStack {
                    Label(
                        "\(entry.snapshot.stepsRemaining.formatted()) TO EVOLVE",
                        systemImage: "sparkles"
                    )
                    Spacer()
                    Label(
                        "\(entry.snapshot.streak)",
                        systemImage: "flame.fill"
                    )
                    .foregroundStyle(WidgetPalette.orange)
                }
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(WidgetPalette.secondary)
            }
        }
    }

    private var accessoryCircular: some View {
        Gauge(value: entry.snapshot.evolutionProgress) {
            Image(systemName: "pawprint.fill")
        } currentValueLabel: {
            Text("\(Int(entry.snapshot.evolutionProgress * 100))")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.snapshot.creatureName)
                .font(.headline)
                .lineLimit(1)
            Text("\(entry.snapshot.stepsRemaining.formatted()) steps to evolve")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: entry.snapshot.evolutionProgress)
        }
        .widgetAccentable()
    }

    private var accessoryInline: some View {
        Label(
            "\(entry.snapshot.stepsRemaining.formatted()) to evolve · \(entry.snapshot.streak)d streak",
            systemImage: "pawprint.fill"
        )
    }
}

private struct EvolutionRing: View {
    let progress: Double
    let width: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(
                    WidgetPalette.track,
                    style: StrokeStyle(lineWidth: width, lineCap: .round)
                )
                .rotationEffect(.degrees(90))

            Circle()
                .trim(from: 0.08, to: 0.08 + 0.84 * min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(
                        colors: [WidgetPalette.teal, WidgetPalette.cyan],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: width, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .shadow(color: WidgetPalette.teal.opacity(0.55), radius: 5)
        }
    }
}

private struct WidgetCreatureArtwork: View {
    let data: Data?

    private var image: UIImage? {
        data.flatMap(UIImage.init(data:))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "pawprint.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(20)
                    .foregroundStyle(WidgetPalette.teal)
            }
        }
    }
}

private enum WidgetPalette {
    static let background = Color(red: 0.015, green: 0.025, blue: 0.027)
    static let teal = Color(red: 0.36, green: 0.90, blue: 0.84)
    static let cyan = Color(red: 0.10, green: 0.76, blue: 0.91)
    static let orange = Color(red: 1.0, green: 0.43, blue: 0.06)
    static let secondary = Color.white.opacity(0.62)
    static let track = Color.white.opacity(0.13)
}
