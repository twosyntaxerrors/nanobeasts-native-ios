#!/usr/bin/env python3
"""Run production streak calculations against calendar and historical-goal edge cases."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
models = (root / 'Nanobeasts/Models/CreatureModels.swift').read_text()
records = models[models.index('struct DailyStepRecord:'):models.index('enum CreatureDiscoveryKind:')]
checks = r'''
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
    checks += 1
}
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/New_York")!
calendar.firstWeekday = 2
let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!
let today = calendar.startOfDay(for: now)
func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
func summary(_ records: [DailyStepRecord], goals: [DailyGoalRecord] = []) -> StreakHistorySummary {
    .init(records: records, dailyGoal: 8000, goalHistory: goals, now: now, calendar: calendar)
}
let longRun = (-20...0).map { DailyStepRecord(day: day($0), steps: 8000) }
check(summary(longRun).current == 21, "Streak is not capped at seven")
check(summary(longRun).best == 21, "Personal best uses full history")
check(summary(longRun).nextMilestone == 30, "Next target after an earned milestone")
let incompleteToday = longRun.dropLast() + [DailyStepRecord(day: today, steps: 0)]
check(summary(Array(incompleteToday)).current == 20, "Midnight or zero steps today preserves yesterday's streak")
check(summary(Array(longRun.dropLast())).current == 20, "Missing today preserves yesterday's streak")
check(summary(longRun.filter { $0.day != day(-1) }).current == 1, "A missing calendar day breaks a streak")
check(summary([.init(day: day(-2), steps: 9000)]).current == 0, "Old history is not a current streak")
check(summary([.init(day: today, steps: 4000)]).current == 0, "Partial goal does not earn a day")
check(summary([]).current == 0 && summary([]).best == 0, "Empty state")
let changingGoals = [DailyGoalRecord(day: day(-5), goal: 4000), DailyGoalRecord(day: today, goal: 8000)]
let changed = summary([.init(day: day(-1), steps: 4500), .init(day: today, steps: 8100)], goals: changingGoals)
check(changed.current == 2, "Historical goals are honored")
check(changed.week.first { $0.date == day(-1) }?.goal == 4000, "Week shows the goal applicable that day")
check(changed.today.goal == 8000, "Today's goal is current")
check(changed.week.count == 7 && changed.week.first?.date == day(-6), "Localized Monday week start")
check(changed.today.progress == 1, "Over-goal progress is capped")
check(summary([.init(day: day(1), steps: 9000)]).best == 0, "Future samples cannot earn streaks")
check(summary([.init(day: today, steps: -4)]).today.steps == 0, "Negative samples do not break layout")
let missing = longRun.filter { $0.day != day(-10) }
check(summary(missing).best == 10, "Best streak respects gaps")
let duplicates = summary([.init(day: today, steps: 1000), .init(day: today, steps: 9000)])
check(duplicates.current == 1, "Duplicate daily updates do not earn extra days")
var sundayCalendar = calendar; sundayCalendar.firstWeekday = 1
let sunday = StreakHistorySummary(records: longRun, dailyGoal: 8000, goalHistory: [], now: now, calendar: sundayCalendar)
check(sunday.week.first?.isToday == true && sunday.week.dropFirst().allSatisfy(\.isFuture), "Sunday locale and future days")
let dstNow = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
let dstRecords = (0..<4).map { DailyStepRecord(day: calendar.date(byAdding: .day, value: -$0, to: dstNow)!, steps: 8000) }
check(StreakHistorySummary(records: dstRecords, dailyGoal: 8000, goalHistory: [], now: dstNow, calendar: calendar).current == 4, "DST uses calendar days rather than 86400-second subtraction")
print("Passed \(checks) streak-history checks")
'''
with tempfile.TemporaryDirectory(prefix='nano-streak-checks-') as directory:
    directory = Path(directory)
    source = directory / 'main.swift'
    source.write_text('import Foundation\n' + records + '\n' +
                      (root / 'Nanobeasts/Models/StreakHistorySummary.swift').read_text() + checks)
    executable = directory / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'cache'), str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
