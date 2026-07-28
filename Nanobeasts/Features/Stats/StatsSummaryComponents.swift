import SwiftUI

struct StatsScreenHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("ACTIVITY STATS")
                .font(NanoFont.aldrich(28))
                .tracking(1.8)
                .foregroundStyle(.white)
            Text("Your movement powers evolution.")
                .font(NanoFont.aldrich(13))
                .foregroundStyle(NanoTheme.secondaryText)
        }
    }
}

struct LifetimeMovementCard: View {
    let steps: Int
    let activeDays: Int
    let unlockedBadges: Int
    let totalBadges: Int
    let rangeLabel: String

    private var distanceMiles: Double {
        Double(steps) * 0.000473
    }

    private var completion: Double {
        guard totalBadges > 0 else { return 0 }
        return min(Double(unlockedBadges) / Double(totalBadges), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            header
            Divider().overlay(NanoTheme.teal.opacity(0.26))
            metrics
            Divider().overlay(NanoTheme.teal.opacity(0.26))
            badgeProgress
        }
        .nanoHUDCard(illuminated: true)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("MOVEMENT HISTORY")
                    .font(NanoFont.aldrich(11))
                    .tracking(1.7)
                    .foregroundStyle(NanoTheme.teal)

                Text(steps.formatted())
                    .font(NanoFont.aldrich(43))
                    .minimumScaleFactor(0.62)
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Text(rangeLabel)
                    .font(NanoFont.aldrich(10))
                    .tracking(1.6)
                    .foregroundStyle(NanoTheme.secondaryText)
            }

            Spacer(minLength: 10)

            Image(systemName: "chart.bar.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(NanoTheme.teal)
                .frame(width: 62, height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(NanoTheme.teal.opacity(0.09))
                        .stroke(NanoTheme.teal.opacity(0.48), lineWidth: 1)
                )
        }
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            LifetimeMetric(
                icon: "location.fill",
                value: distanceMiles.formatted(.number.precision(.fractionLength(1))),
                unit: "MI",
                label: "TOTAL DISTANCE"
            )
            .padding(.trailing, 16)

            Rectangle()
                .fill(NanoTheme.teal.opacity(0.28))
                .frame(width: 1)
                .frame(height: 38)
                .padding(.horizontal, 8)

            LifetimeMetric(
                icon: "calendar",
                value: activeDays.formatted(),
                unit: "",
                label: "ACTIVE DAYS"
            )
            .padding(.leading, 16)
        }
        .padding(.vertical, 4)
    }

    private var badgeProgress: some View {
        VStack(spacing: 7) {
            HStack {
                Text("BADGE COLLECTION")
                    .font(NanoFont.aldrich(10))
                    .tracking(1.3)
                    .foregroundStyle(NanoTheme.secondaryText)
                Spacer()
                Text("\(unlockedBadges)/\(totalBadges)")
                    .font(NanoFont.aldrich(12))
                    .foregroundStyle(NanoTheme.teal)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NanoTheme.teal.opacity(0.09))
                        .stroke(NanoTheme.teal.opacity(0.28), lineWidth: 1)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [NanoTheme.teal, NanoTheme.teal.opacity(0.68)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * completion)
                }
            }
            .frame(height: 8)
        }
    }
}

private struct LifetimeMetric: View {
    let icon: String
    let value: String
    let unit: String
    let label: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(NanoTheme.teal)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(NanoFont.aldrich(20))
                        .foregroundStyle(.white)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(NanoFont.aldrich(9))
                            .foregroundStyle(NanoTheme.secondaryText)
                    }
                }
                Text(label)
                    .font(NanoFont.aldrich(8))
                    .tracking(1.1)
                    .foregroundStyle(NanoTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ActivityConsistencyHeader: View {
    @Binding var scope: StatsCalendarScope

    var body: some View {
        HStack(spacing: 10) {
            Text("ACTIVITY CONSISTENCY")
                .font(NanoFont.aldrich(14))
                .tracking(1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 2)

            HStack(spacing: 3) {
                ForEach(StatsCalendarScope.allCases) { option in
                    scopeButton(option)
                }
            }
            .padding(3)
            .background(
                Capsule()
                    .fill(NanoTheme.surface)
                    .stroke(NanoTheme.elevated, lineWidth: 1)
            )
        }
    }

    private func scopeButton(_ option: StatsCalendarScope) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                scope = option
            }
        } label: {
            Text(option.rawValue)
                .font(NanoFont.aldrich(10))
                .foregroundStyle(scope == option ? NanoTheme.background : NanoTheme.secondaryText)
                .frame(width: 62, height: 32)
                .background(
                    Capsule()
                        .fill(scope == option ? NanoTheme.teal : .clear)
                )
        }
        .buttonStyle(.plain)
    }
}
