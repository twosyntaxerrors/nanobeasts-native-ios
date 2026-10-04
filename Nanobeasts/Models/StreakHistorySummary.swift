import Foundation

/// Calendar-day streaks use the goal that applied on each day, including gaps.
struct StreakHistorySummary {
    struct Day: Identifiable {
        let date: Date
        let steps: Int
        let goal: Int
        let isToday: Bool
        let isFuture: Bool
        var id: Date { date }
        var metGoal: Bool { !isFuture && steps >= goal }
        var progress: Double { min(1, Double(steps) / Double(goal)) }
    }

    let current: Int
    let best: Int
    let week: [Day]
    let today: Day
    let nextMilestone: Int?
    static let milestones = [3, 5, 7, 10, 14, 21, 30, 45, 60, 90, 120, 180]

    init(records: [DailyStepRecord], dailyGoal: Int, goalHistory: [DailyGoalRecord],
         now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        let todayDate = calendar.startOfDay(for: now)
        let byDate = Dictionary(records.map { (calendar.startOfDay(for: $0.day), max(0, $0.steps)) },
                                uniquingKeysWith: { _, latest in latest })
        let goals = goalHistory.sorted { $0.day < $1.day }
        func goal(_ day: Date) -> Int {
            max(1, goals.last { calendar.startOfDay(for: $0.day) <= day }?.goal ?? dailyGoal)
        }
        func day(_ date: Date) -> Day {
            Day(date: date, steps: byDate[date] ?? 0, goal: goal(date),
                isToday: date == todayDate, isFuture: date > todayDate)
        }
        today = day(todayDate)
        var cursor = today.metGoal ? todayDate : calendar.date(byAdding: .day, value: -1, to: todayDate)!
        var count = 0
        while let steps = byDate[cursor], steps >= goal(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        current = count
        var longest = 0
        var run = 0
        var previous: Date?
        for date in byDate.keys.sorted() where date <= todayDate {
            if let previous, calendar.dateComponents([.day], from: previous, to: date).day != 1 { run = 0 }
            run = (byDate[date] ?? 0) >= goal(date) ? run + 1 : 0
            longest = max(longest, run)
            previous = date
        }
        best = longest
        nextMilestone = Self.milestones.first { $0 > count }
        let weekday = calendar.component(.weekday, from: todayDate)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: todayDate)!
        week = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start).map(day) }
    }
}
