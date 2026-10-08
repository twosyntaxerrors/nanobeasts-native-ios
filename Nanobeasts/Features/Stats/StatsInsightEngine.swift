import Foundation

/// A sentence split into plain and highlighted runs, so views can color the key facts.
struct InsightLine: Hashable, Sendable {
    struct Run: Hashable, Sendable {
        let text: String
        let isHighlighted: Bool
    }

    let runs: [Run]

    init(_ runs: [Run]) { self.runs = runs }

    var plainText: String { runs.map(\.text).joined() }
}

/// Builds `InsightLine`s with `**highlighted**` markers, e.g. "You walked **4,210 steps**."
private func line(_ markup: String) -> InsightLine {
    let parts = markup.components(separatedBy: "**")
    return InsightLine(parts.enumerated().compactMap { index, text in
        text.isEmpty ? nil : InsightLine.Run(text: text, isHighlighted: !index.isMultiple(of: 2))
    })
}

enum TrendRange: String, CaseIterable, Identifiable, Sendable {
    case week = "W"
    case month = "M"
    case year = "Y"

    var id: Self { self }

    var dayCount: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .year: 365
        }
    }

    var accessibilityName: String {
        switch self {
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .year: "Last 12 months"
        }
    }

    var comparisonName: String {
        switch self {
        case .week: "last week"
        case .month: "the 30 days before"
        case .year: "the year before"
        }
    }
}

struct TrendPoint: Identifiable, Hashable, Sendable {
    let date: Date
    let steps: Int
    var id: Date { date }
}

struct TrendSnapshot: Sendable {
    let range: TrendRange
    let points: [TrendPoint]
    let averageSteps: Int
    let totalSteps: Int
    let goalDays: Int
    let dayCount: Int
    /// Percent change in daily average against the previous period, when there is one.
    let deltaPercent: Int?
    let best: TrendPoint?
    let headline: InsightLine
    let chartMaximum: Int
}

struct RhythmSnapshot: Sendable {
    /// Average steps for each hour of the day (0...23) across the sampled days.
    let hourlyAverages: [Int]
    let peakHours: ClosedRange<Int>
    let weekdayAverages: [Int] // Sunday first
    let bestWeekday: Int // 0 = Sunday
    let weekendLiftPercent: Int
    let sampledDays: Int
    let headline: InsightLine
    /// Today against the user's usual total by this hour, when there's enough history.
    let todayPace: InsightLine?
    let todayIsAhead: Bool
}

struct PersonalRecord: Identifiable, Sendable {
    let id: String
    let title: String
    let value: String
    let unit: String
    let caption: String
    var isNew = false
}

struct RecapDiscovery: Identifiable, Sendable {
    let id: UUID
    let stage: CreatureStage
    let kind: CreatureDiscoveryKind
    let date: Date
}

struct MonthRecap: Sendable {
    let month: Date
    let days: [TrendPoint]
    /// Whether each entry in `days` met that day's goal.
    let goalHits: [Bool]
    let totalSteps: Int
    let distance: Double
    let averageSteps: Int
    let goalDays: Int
    let dayCount: Int
    let best: TrendPoint?
    let previousMonthDelta: Int?
    let marathons: Double
    let discoveries: [RecapDiscovery]

    /// New forms only (hatches, evolutions, maturities), oldest first.
    var newForms: [RecapDiscovery] { discoveries.filter { $0.kind != .eggAcquired } }
    var evolutionCount: Int { discoveries.filter { $0.kind == .evolution || $0.kind == .maturity }.count }

    var monthName: String { month.formatted(.dateTime.month(.wide)) }
}

struct StatsInsightInput: Sendable {
    let records: [DailyStepRecord]
    let journeyRecords: [DailyStepRecord]
    let hourly: [HourlyStepRecord]
    let todaySteps: Int
    let dailyGoal: Int
    let goalHistory: [DailyGoalRecord]
    let journeyDayCount: Int
    let journeyRangeLabel: String
    let discoveries: [CreatureDiscoveryEvent]
    let distanceUnit: DistanceUnitPreference
    let now: Date
}

struct StatsInsights: Sendable {
    let trends: [TrendRange: TrendSnapshot]
    let rhythm: RhythmSnapshot?
    let records: [PersonalRecord]
    let recap: MonthRecap?
    let streak: (current: Int, best: Int)

    static let empty = StatsInsights(trends: [:], rhythm: nil, records: [], recap: nil, streak: (0, 0))

    private init(trends: [TrendRange: TrendSnapshot],
                 rhythm: RhythmSnapshot?, records: [PersonalRecord], recap: MonthRecap?,
                 streak: (current: Int, best: Int)) {
        self.trends = trends
        self.rhythm = rhythm
        self.records = records
        self.recap = recap
        self.streak = streak
    }

    init(input: StatsInsightInput) {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: input.now)
        var byDay: [Date: Int] = [:]
        for record in input.records {
            byDay[calendar.startOfDay(for: record.day), default: 0] += max(record.steps, 0)
        }
        byDay[today] = max(byDay[today] ?? 0, input.todaySteps)

        let goals = input.goalHistory.sorted { $0.day < $1.day }
        func goal(on day: Date) -> Int {
            max(goals.last(where: { calendar.startOfDay(for: $0.day) <= day })?.goal ?? input.dailyGoal, 1)
        }
        func days(from start: Date, through end: Date) -> [TrendPoint] {
            var result: [TrendPoint] = []
            var day = start
            while day <= end {
                result.append(TrendPoint(date: day, steps: byDay[day] ?? 0))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return result
        }

        let summary = StreakHistorySummary(
            records: byDay.map { DailyStepRecord(day: $0.key, steps: $0.value) },
            dailyGoal: input.dailyGoal, goalHistory: input.goalHistory, now: input.now, calendar: calendar)
        streak = (summary.current, summary.best)

        var trends: [TrendRange: TrendSnapshot] = [:]
        for range in TrendRange.allCases {
            trends[range] = Self.trend(range: range, today: today, calendar: calendar,
                                       days: days, goal: goal)
        }
        self.trends = trends

        rhythm = Self.rhythm(input: input, today: today, calendar: calendar)
        records = Self.records(byDay: byDay, hourly: input.hourly, input: input, today: today,
                               bestStreak: summary.best, calendar: calendar)
        recap = Self.recap(today: today, calendar: calendar, days: days, goal: goal, input: input)
    }

    // MARK: Trends

    private static func trend(
        range: TrendRange, today: Date, calendar: Calendar,
        days: (Date, Date) -> [TrendPoint], goal: (Date) -> Int
    ) -> TrendSnapshot {
        let currentStart: Date
        let previousStart: Date
        if range == .year {
            let thisMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
            currentStart = calendar.date(byAdding: .month, value: -11, to: thisMonth) ?? thisMonth
            previousStart = calendar.date(byAdding: .month, value: -12, to: currentStart) ?? currentStart
        } else {
            currentStart = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: today) ?? today
            previousStart = calendar.date(byAdding: .day, value: -range.dayCount, to: currentStart) ?? currentStart
        }
        let previousEnd = calendar.date(byAdding: .day, value: -1, to: currentStart) ?? currentStart
        let current = days(currentStart, today)
        let previous = days(previousStart, previousEnd)

        let total = current.reduce(0) { $0 + $1.steps }
        let average = current.isEmpty ? 0 : total / current.count
        let previousTotal = previous.reduce(0) { $0 + $1.steps }
        let previousAverage = previous.isEmpty ? 0 : previousTotal / previous.count
        let goalDays = current.filter { $0.steps >= goal($0.date) }.count
        let delta = previousTotal > 0 && previousAverage > 0
            ? Int((Double(average - previousAverage) / Double(previousAverage) * 100).rounded())
            : nil

        let points: [TrendPoint]
        if range == .year {
            let grouped = Dictionary(grouping: current) {
                calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date
            }
            points = grouped.map { month, values in
                TrendPoint(date: month, steps: values.reduce(0) { $0 + $1.steps } / max(values.count, 1))
            }.sorted { $0.date < $1.date }
        } else {
            points = current
        }

        let best = points.filter { $0.steps > 0 }.max { $0.steps < $1.steps }
        let headline: InsightLine
        if let best {
            switch range {
            case .week:
                headline = line("Your best day was **\(best.date.formatted(.dateTime.weekday(.wide)))** with **\(best.steps.formatted()) steps**.")
            case .month:
                headline = line("Your strongest day this month was **\(best.date.formatted(.dateTime.month(.abbreviated).day()))** at **\(best.steps.formatted()) steps**.")
            case .year:
                headline = line("**\(best.date.formatted(.dateTime.month(.wide)))** was your most active month, averaging **\(best.steps.formatted())** a day.")
            }
        } else {
            headline = line("Take a few steps and your **trend** starts here.")
        }

        let highest = max(points.map(\.steps).max() ?? 0, goal(today))
        return TrendSnapshot(
            range: range, points: points, averageSteps: average, totalSteps: total,
            goalDays: goalDays, dayCount: current.count, deltaPercent: delta, best: best,
            headline: headline, chartMaximum: max(Int(Double(highest) * 1.18), 1))
    }

    // MARK: Rhythm

    private static func rhythm(input: StatsInsightInput, today: Date, calendar: Calendar) -> RhythmSnapshot? {
        // Only finished days, so a half-walked today doesn't skew the profile.
        let past = input.hourly.filter { $0.start < today }
        let dayKeys = Set(past.map { calendar.startOfDay(for: $0.start) })
        guard dayKeys.count >= 5 else { return nil }

        var hourTotals = Array(repeating: 0, count: 24)
        var weekdayTotals = Array(repeating: 0, count: 7)
        var weekdayDays = Array(repeating: Set<Date>(), count: 7)
        for record in past {
            let steps = max(record.steps, 0)
            let hour = calendar.component(.hour, from: record.start)
            let weekday = calendar.component(.weekday, from: record.start) - 1
            hourTotals[hour] += steps
            weekdayTotals[weekday] += steps
            weekdayDays[weekday].insert(calendar.startOfDay(for: record.start))
        }
        let hourlyAverages = hourTotals.map { $0 / dayKeys.count }
        guard hourlyAverages.reduce(0, +) > 0 else { return nil }

        // Strongest two-hour window.
        let windowTotals: [Int] = (0..<23).map { hourlyAverages[$0] + hourlyAverages[$0 + 1] }
        let peakStart = windowTotals.indices.max { windowTotals[$0] < windowTotals[$1] } ?? 0
        let weekdayAverages: [Int] = (0..<7).map { day in
            weekdayDays[day].isEmpty ? 0 : weekdayTotals[day] / weekdayDays[day].count
        }
        let bestWeekday = (0..<7).max { weekdayAverages[$0] < weekdayAverages[$1] } ?? 0

        let weekendDays = weekdayDays[0].count + weekdayDays[6].count
        let workDays = (1...5).reduce(0) { $0 + weekdayDays[$1].count }
        let weekendAverage = weekendDays > 0 ? (weekdayTotals[0] + weekdayTotals[6]) / weekendDays : 0
        let workTotal: Int = (1...5).reduce(0) { $0 + weekdayTotals[$1] }
        let workAverage = workDays > 0 ? workTotal / workDays : 0
        let liftRatio = workAverage > 0 ? Double(weekendAverage - workAverage) / Double(workAverage) : 0
        let lift = Int((liftRatio * 100).rounded())

        let hour = calendar.component(.hour, from: input.now)
        let usual = hourlyAverages.prefix(hour).reduce(0, +)
        var todayPace: InsightLine?
        var todayIsAhead = true
        if (9...21).contains(hour), usual >= 500 {
            let difference = input.todaySteps - usual
            let time = input.now.formatted(.dateTime.hour()).nonBreaking
            todayIsAhead = difference >= 0
            todayPace = difference >= 0
                ? line("Today you're **\(difference.formatted()) steps ahead** of your usual \(time).")
                : line("You usually have **\(usual.formatted())** by \(time). A **\(max(5, -difference / 100))-min walk** catches you up.")
        }

        return RhythmSnapshot(
            hourlyAverages: hourlyAverages, peakHours: peakStart...(peakStart + 1),
            weekdayAverages: weekdayAverages, bestWeekday: bestWeekday, weekendLiftPercent: lift,
            sampledDays: dayKeys.count,
            headline: line("You move most around **\(hourRange(peakStart, peakStart + 2, calendar: calendar).nonBreaking)**."),
            todayPace: todayPace, todayIsAhead: todayIsAhead)
    }

    static func hourRange(_ start: Int, _ end: Int, calendar: Calendar) -> String {
        func label(_ hour: Int) -> (String, String) {
            let normalized = (hour % 24 + 24) % 24
            let suffix = normalized < 12 ? "AM" : "PM"
            let twelve = normalized % 12 == 0 ? 12 : normalized % 12
            return ("\(twelve)", suffix)
        }
        let (a, aSuffix) = label(start)
        let (b, bSuffix) = label(end)
        return aSuffix == bSuffix ? "\(a)–\(b) \(bSuffix)" : "\(a) \(aSuffix)–\(b) \(bSuffix)"
    }

    // MARK: Records

    private static func records(
        byDay: [Date: Int], hourly: [HourlyStepRecord], input: StatsInsightInput, today: Date,
        bestStreak: Int, calendar: Calendar
    ) -> [PersonalRecord] {
        var result: [PersonalRecord] = []
        let freshSince = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        func date(_ day: Date) -> String {
            calendar.isDate(day, equalTo: today, toGranularity: .year)
                ? day.formatted(.dateTime.month(.abbreviated).day())
                : day.formatted(.dateTime.month(.abbreviated).day().year())
        }

        if let best = byDay.filter({ $0.value > 0 }).max(by: { $0.value < $1.value }) {
            result.append(PersonalRecord(id: "day", title: "BEST DAY", value: best.value.formatted(),
                                         unit: "steps", caption: date(best.key), isNew: best.key >= freshSince))
        }

        var weeks: [Date: Int] = [:]
        for (day, steps) in byDay {
            weeks[calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day, default: 0] += steps
        }
        if let week = weeks.filter({ $0.value > 0 }).max(by: { $0.value < $1.value }) {
            result.append(PersonalRecord(id: "week", title: "BEST WEEK", value: week.value.formatted(),
                                         unit: "steps", caption: "Week of \(date(week.key))",
                                         isNew: calendar.isDate(week.key, equalTo: today, toGranularity: .weekOfYear)))
        }

        result.append(PersonalRecord(id: "streak", title: "LONGEST STREAK", value: bestStreak.formatted(),
                                     unit: bestStreak == 1 ? "day" : "days", caption: "Goal days in a row"))

        if let hour = hourly.filter({ $0.steps > 0 }).max(by: { $0.steps < $1.steps }) {
            let label = hourRange(calendar.component(.hour, from: hour.start),
                                  calendar.component(.hour, from: hour.start) + 1, calendar: calendar)
            result.append(PersonalRecord(id: "hour", title: "PEAK HOUR", value: hour.steps.formatted(),
                                         unit: "steps", caption: "\(date(hour.start)) · \(label)",
                                         isNew: hour.start >= freshSince))
        }

        let lifetime = input.journeyRecords.reduce(0) { $0 + max($1.steps, 0) }
        result.append(PersonalRecord(id: "lifetime", title: "LIFETIME STEPS", value: lifetime.formatted(),
                                     unit: "", caption: input.journeyRangeLabel.capitalized))
        let distance = input.distanceUnit.value(forSteps: lifetime)
        result.append(PersonalRecord(id: "distance", title: "DISTANCE", value: distance.formatted(.number.precision(.fractionLength(1))),
                                     unit: input.distanceUnit.abbreviation.lowercased(),
                                     caption: "\(input.journeyDayCount.formatted()) days tracked"))
        return result
    }

    // MARK: Recap

    /// The month's recap opens on its last day and stays playable through the 7th of the next month.
    static func recapMonth(for today: Date, calendar: Calendar) -> (interval: DateInterval, end: Date)? {
        guard let thisMonth = calendar.dateInterval(of: .month, for: today),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: thisMonth.end)
        else { return nil }
        if calendar.isDate(today, inSameDayAs: lastDay) { return (thisMonth, today) }
        guard calendar.component(.day, from: today) <= 7,
              let previous = calendar.dateInterval(of: .month, for: thisMonth.start.addingTimeInterval(-1)),
              let previousEnd = calendar.date(byAdding: .day, value: -1, to: previous.end)
        else { return nil }
        return (previous, previousEnd)
    }

    private static func recap(
        today: Date, calendar: Calendar, days: (Date, Date) -> [TrendPoint],
        goal: (Date) -> Int, input: StatsInsightInput
    ) -> MonthRecap? {
        guard let (month, end) = recapMonth(for: today, calendar: calendar) else { return nil }

        let monthDays = days(month.start, end)
        let total = monthDays.reduce(0) { $0 + $1.steps }
        guard total > 0 else { return nil }
        let previousStart = calendar.date(byAdding: .month, value: -1, to: month.start) ?? month.start
        let previousEnd = calendar.date(byAdding: .day, value: -1, to: month.start) ?? month.start
        let previous = days(previousStart, previousEnd)
        let previousTotal = previous.reduce(0) { $0 + $1.steps }
        let average = total / max(monthDays.count, 1)
        let previousAverage = previous.isEmpty ? 0 : previousTotal / previous.count
        let discoveries = input.discoveries
            .filter { month.contains($0.timestamp) }
            .sorted { $0.timestamp < $1.timestamp }
            .map { event in
                RecapDiscovery(
                    id: event.id,
                    stage: CreatureStage(familyID: event.familyID, name: event.name, imageKey: event.imageKey,
                                         stage: event.stage, types: event.types, description: event.description),
                    kind: event.kind, date: event.timestamp)
            }
        let hits = monthDays.map { $0.steps >= goal($0.date) }
        return MonthRecap(
            month: month.start, days: monthDays, goalHits: hits, totalSteps: total,
            distance: input.distanceUnit.value(forSteps: total), averageSteps: average,
            goalDays: hits.filter { $0 }.count, dayCount: monthDays.count,
            best: monthDays.max { $0.steps < $1.steps },
            previousMonthDelta: previousAverage > 0
                ? Int((Double(average - previousAverage) / Double(previousAverage) * 100).rounded()) : nil,
            marathons: Double(total) * 0.000762 / 42.195, discoveries: discoveries)
    }
}

private extension String {
    /// Keeps short ranges like "8–10 PM" from wrapping mid-phrase.
    var nonBreaking: String {
        replacingOccurrences(of: " ", with: "\u{00A0}").replacingOccurrences(of: "–", with: "\u{2060}–\u{2060}")
    }
}
