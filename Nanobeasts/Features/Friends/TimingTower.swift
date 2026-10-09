import SwiftUI

/// The week as a seven-lap race: the week number, its dates, the time left,
/// and one segment per day with today glowing.
struct RaceHeader: View {
    let weekNumber: Int?
    let dates: String?
    let raceDay: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom) {
                Text(weekNumber.map { "WEEK \($0)" } ?? "THIS WEEK")
                    .font(NanoFont.aldrich(30))
                    .foregroundStyle(NanoTheme.text)
                Spacer(minLength: 8)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .trailing, spacing: 2) {
                        if let dates {
                            Text(dates.uppercased())
                        }
                        Text("FINISH IN \(Self.timeToSunday(from: context.date))")
                    }
                    .font(NanoFont.spaceMono(11))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .monospacedDigit()
                }
            }

            HStack(spacing: 4) {
                ForEach(1...7, id: \.self) { day in
                    Capsule()
                        .fill(day < raceDay ? NanoTheme.text : day == raceDay ? NanoTheme.teal : NanoTheme.elevated)
                        .frame(height: 4)
                        .shadow(color: day == raceDay ? NanoTheme.teal : .clear, radius: 6)
                        .opacity(day == raceDay && pulsing ? 0.5 : 1)
                }
            }

            HStack {
                Text("DAY \(raceDay) / 7")
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(NanoTheme.teal).frame(width: 5, height: 5)
                    Text("LIVE")
                }
            }
            .font(NanoFont.aldrich(9))
            .tracking(1.6)
            .foregroundStyle(NanoTheme.secondaryText)
        }
        .padding(.horizontal, 2)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulsing = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Week \(weekNumber ?? 0), day \(raceDay) of 7. Finishes in \(Self.timeToSunday(from: Date()))")
    }

    /// "1D 22H", or "6H 12M" on the final day.
    static func timeToSunday(from now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let end = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, weekday: 1),
            matchingPolicy: .nextTime
        ) ?? now
        let minutes = max(Int(end.timeIntervalSince(now) / 60), 0)
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        return days > 0 ? "\(days)D \(hours)H" : "\(hours)H \(minutes % 60)M"
    }
}

/// Standings styled like a race broadcast's timing tower: position, the
/// creature's type color, the walker, their steps, and the gap to the leader.
struct TimingTower: View {
    let ranking: [LeaderboardEntry]
    let value: KeyPath<LeaderboardEntry, Int>
    /// Places gained or lost since yesterday. Empty for Today.
    let movement: [String: Int]
    /// The player who holds this week's best day, marked in purple.
    let bestDayID: String?
    let stageForKey: (String?) -> CreatureStage?
    let inviteURL: URL?
    let onRemove: (LeaderboardEntry) -> Void

    static let bestDayPurple = Color(red: 0.66, green: 0.33, blue: 0.97)

    var body: some View {
        VStack(spacing: 0) {
            columns
            ForEach(Array(ranking.enumerated()), id: \.element.id) { index, entry in
                row(entry, position: index + 1)
                    .contextMenu {
                        if !entry.isMe {
                            Button("Remove friend", systemImage: "person.badge.minus", role: .destructive) {
                                onRemove(entry)
                            }
                        }
                    }
                if index < ranking.count - 1 || ranking.count < 3 { divider }
            }
            if let inviteURL {
                ForEach(0..<max(3 - ranking.count, 0), id: \.self) { slot in
                    inviteRow(position: ranking.count + slot + 1, url: inviteURL)
                    if ranking.count + slot + 1 < 3 { divider }
                }
            }
        }
        .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var columns: some View {
        HStack(spacing: 0) {
            Text("POS").frame(width: 34, alignment: .leading)
            Text("WALKER").padding(.leading, 50)
            Spacer()
            Text("STEPS").frame(width: 70, alignment: .trailing)
            Text("GAP").frame(width: 62, alignment: .trailing)
        }
        .font(NanoFont.aldrich(8.5))
        .tracking(1.4)
        .foregroundStyle(NanoTheme.mutedText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(NanoTheme.border).frame(height: 1) }
    }

    private var divider: some View {
        Rectangle().fill(NanoTheme.border).frame(height: 1)
    }

    private func row(_ entry: LeaderboardEntry, position: Int) -> some View {
        let stage = stageForKey(entry.avatarKey)
        let steps = entry[keyPath: value]
        let leader = ranking.first?[keyPath: value] ?? 0
        let walked = steps > 0
        let teamColor = entry.isMe ? NanoTheme.teal : stage.map(NanoCreatureType.color(for:)) ?? NanoTheme.mutedText

        return HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if let change = movement[entry.id] {
                    Image(systemName: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(change > 0 ? NanoTheme.green : NanoTheme.danger)
                        .offset(x: -9)
                        .accessibilityLabel(change > 0 ? "Up \(change)" : "Down \(-change)")
                }
                Text(walked ? "\(position)" : "–")
                    .font(NanoFont.spaceMono(15, bold: true))
                    .foregroundStyle(walked ? (LeaderboardMedal.color(for: position) ?? NanoTheme.text) : NanoTheme.mutedText)
            }
            .frame(width: 30, alignment: .leading)

            Capsule()
                .fill(teamColor)
                .frame(width: 3, height: 28)

            Group {
                if let stage {
                    CreatureArtworkView(stage: stage, maxPixel: 100)
                } else {
                    Image(systemName: "person.fill")
                        .foregroundStyle(NanoTheme.secondaryText)
                }
            }
            .frame(width: 34, height: 34)
            .padding(.leading, 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.isMe ? "YOU" : entry.displayName.uppercased())
                        .font(NanoFont.aldrich(13.5))
                        .tracking(1)
                        .lineLimit(1)
                    if entry.id == bestDayID {
                        Image(systemName: "stopwatch.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Self.bestDayPurple)
                            .accessibilityLabel("Best day")
                    }
                }
                Text(stage?.name ?? "No creature yet")
                    .font(.system(size: 11))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .lineLimit(1)
            }
            .padding(.leading, 10)

            Spacer(minLength: 4)

            Text(steps.formatted())
                .font(NanoFont.spaceMono(13.5, bold: true))
                .monospacedDigit()
                .foregroundStyle(NanoTheme.text)
                .frame(width: 70, alignment: .trailing)

            Group {
                if position == 1 && walked {
                    Text("LEADER")
                        .font(NanoFont.aldrich(9))
                        .tracking(1.2)
                        .foregroundStyle(LeaderboardMedal.gold)
                } else {
                    Text("+\((leader - steps).formatted())")
                        .font(NanoFont.spaceMono(11))
                        .monospacedDigit()
                        .foregroundStyle(NanoTheme.secondaryText)
                }
            }
            .frame(width: 62, alignment: .trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background {
            if entry.isMe {
                LinearGradient(
                    colors: [NanoTheme.teal.opacity(0.30), NanoTheme.teal.opacity(0.05)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .overlay(alignment: .leading) {
                    Rectangle().fill(NanoTheme.teal).frame(width: 3)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(entry, position: position, steps: steps, gap: leader - steps))
    }

    private func inviteRow(position: Int, url: URL) -> some View {
        ShareLink(item: url, message: Text("Race me on Nanobeasts this week!")) {
            HStack(spacing: 0) {
                Text("\(position)")
                    .font(NanoFont.spaceMono(15, bold: true))
                    .foregroundStyle(NanoTheme.mutedText)
                    .frame(width: 30, alignment: .leading)
                Capsule()
                    .fill(NanoTheme.mutedText.opacity(0.5))
                    .frame(width: 3, height: 28)
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(NanoTheme.secondaryText.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])))
                    .padding(.leading, 8)
                Text("OPEN SEAT")
                    .font(NanoFont.aldrich(13))
                    .tracking(1)
                    .foregroundStyle(NanoTheme.secondaryText)
                    .padding(.leading, 10)
                Spacer()
                Text("INVITE")
                    .font(NanoFont.aldrich(10))
                    .tracking(1.2)
                    .foregroundStyle(NanoTheme.teal)
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open seat. Invite a friend.")
    }

    private func accessibilityText(_ entry: LeaderboardEntry, position: Int, steps: Int, gap: Int) -> String {
        let name = entry.isMe ? "You" : entry.displayName
        guard steps > 0 else { return "\(name), no steps yet" }
        let gapText = position == 1 ? "leader" : "\(gap.formatted()) behind the leader"
        return "Position \(position), \(name), \(steps.formatted()) steps, \(gapText)"
    }
}

/// The biggest single day anyone on the board walked this week.
struct BestDayCard: View {
    let holder: LeaderboardEntry
    let day: LeaderboardEntry.BestDay

    var body: some View {
        HStack(spacing: 12) {
            Text("BEST DAY")
                .font(NanoFont.aldrich(9))
                .tracking(1.4)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(TimingTower.bestDayPurple, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                (Text(holder.isMe ? "You" : holder.displayName)
                    + Text(" · ")
                    + Text(day.steps.formatted()).font(NanoFont.spaceMono(13, bold: true))
                    + Text(" on \(FriendsStore.weekdayName(day.date))"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NanoTheme.text)
                Text(holder.isMe ? "Your record to defend this week" : "Beat it to take the purple stopwatch")
                    .font(.system(size: 11))
                    .foregroundStyle(NanoTheme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TimingTower.bestDayPurple.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
