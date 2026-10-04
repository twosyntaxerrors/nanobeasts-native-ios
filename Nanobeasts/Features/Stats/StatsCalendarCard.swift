import SwiftUI

struct ActivityCalendarCard: View {
    let scope: StatsCalendarScope
    @Binding var monthOffset: Int
    let records: [DailyStepRecord]
    let dailyGoal: Int
    let discoveryEvents: [CreatureDiscoveryEvent]
    let workouts: [WorkoutHistoryRecord]
    let importedHistoryRange: DateInterval?
    let distanceUnit: DistanceUnitPreference

    @State private var weekOffset = 0
    @State private var selectedDay: StatsCalendarDay?

    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 7)

    private var calendar: Calendar {
        var value = Calendar.autoupdatingCurrent
        value.firstWeekday = 1
        return value
    }

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    private var displayMonth: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    private var recordsByDay: [Date: Int] {
        records.reduce(into: [Date: Int]()) { result, record in
            result[calendar.startOfDay(for: record.day)] = record.steps
        }
    }

    private var importedHistoryStartDay: Date? {
        importedHistoryRange.map { calendar.startOfDay(for: $0.start) }
    }

    private var journeyStartDay: Date? {
        importedHistoryRange.map { calendar.startOfDay(for: $0.end) }
    }

    private var monthDays: [StatsCalendarDay] {
        guard
            let interval = calendar.dateInterval(of: .month, for: displayMonth),
            let dayRange = calendar.range(of: .day, in: .month, for: displayMonth)
        else {
            return []
        }

        let leading = max(calendar.component(.weekday, from: interval.start) - 1, 0)
        // Build this lookup once per presentation. Accessing the computed
        // property inside the loop rebuilt the entire Health history for every
        // calendar cell during the Home → Stats transition.
        let stepsByDay = recordsByDay
        var result = (0..<leading).map {
            StatsCalendarDay(slot: $0, date: nil, steps: 0)
        }

        for day in dayRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: interval.start) else {
                continue
            }
            result.append(
                makeCalendarDay(
                    slot: result.count,
                    date: date,
                    stepsByDay: stepsByDay
                )
            )
        }
        return result
    }

    private var weekDays: [StatsCalendarDay] {
        let weekday = calendar.component(.weekday, from: today)
        let currentWeekStart = calendar.date(
            byAdding: .day,
            value: -(weekday - 1),
            to: today
        ) ?? today
        let start = calendar.date(
            byAdding: .weekOfYear,
            value: weekOffset,
            to: currentWeekStart
        ) ?? currentWeekStart
        let stepsByDay = recordsByDay

        return (0..<7).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: start) else {
                return nil
            }
            return makeCalendarDay(
                slot: index,
                date: date,
                stepsByDay: stepsByDay
            )
        }
    }

    var body: some View {
        Group {
            if scope == .month {
                monthCard
            } else {
                weekCard
            }
        }
        .sheet(item: $selectedDay) { day in
            DailyFieldReportView(
                day: day,
                dailyGoal: dailyGoal,
                discoveryEvents: discoveryEvents,
                workouts: workouts,
                distanceUnit: distanceUnit
            )
                .presentationDetents([.fraction(0.86), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
    }

    private var monthCard: some View {
        VStack(spacing: 14) {
            monthNavigation

            CalendarProvenanceLegend(
                showsImportedHistory: monthDays.contains(where: \.isImportedFromAppleHealth),
                journeyStartDate: monthDays.first(where: \.isJourneyStart)?.date
            )

            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, weekday in
                    Text(weekday)
                        .font(NanoFont.aldrich(10))
                        .foregroundStyle(NanoTheme.teal)
                        .frame(maxWidth: .infinity)
                }

                ForEach(monthDays) { day in
                    StatsCalendarCell(
                        day: day,
                        dailyGoal: dailyGoal,
                        calendar: calendar
                    ) {
                        select(day)
                    }
                }
            }
        }
        .nanoHUDCard(padding: 16)
    }

    private var monthNavigation: some View {
        HStack {
            CalendarArrow(systemName: "chevron.left", enabled: true) {
                monthOffset -= 1
            }

            Spacer()

            Text(displayMonth.formatted(.dateTime.month(.wide).year()))
                .font(NanoFont.aldrich(17))

            Spacer()

            CalendarArrow(systemName: "chevron.right", enabled: monthOffset < 0) {
                monthOffset += 1
            }
        }
    }

    private var weekCard: some View {
        VStack(spacing: 16) {
            weekNavigation
            CalendarProvenanceLegend(
                showsImportedHistory: weekDays.contains(where: \.isImportedFromAppleHealth),
                journeyStartDate: weekDays.first(where: \.isJourneyStart)?.date
            )
            WeeklyBarChart(
                days: weekDays,
                dailyGoal: dailyGoal,
                calendar: calendar,
                onSelect: select
            )
        }
        .nanoHUDCard(padding: 16)
    }

    private var weekNavigation: some View {
        HStack {
            CalendarArrow(systemName: "chevron.left", enabled: true) {
                weekOffset -= 1
            }

            Spacer()

            VStack(spacing: 5) {
                Text(weekOffset == 0 ? "CURRENT WEEK" : "WEEKLY VIEW")
                    .font(NanoFont.aldrich(10))
                    .tracking(1)
                    .foregroundStyle(NanoTheme.teal)
                Text(weekDateRange)
                    .font(NanoFont.aldrich(16))
            }

            Spacer()

            CalendarArrow(systemName: "chevron.right", enabled: weekOffset < 0) {
                weekOffset += 1
            }
        }
    }

    private var weekDateRange: String {
        guard let first = weekDays.first?.date, let last = weekDays.last?.date else {
            return "THIS WEEK"
        }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func select(_ day: StatsCalendarDay) {
        guard let date = day.date, date <= today else { return }
        selectedDay = day
    }

    private func makeCalendarDay(
        slot: Int,
        date: Date,
        stepsByDay: [Date: Int]
    ) -> StatsCalendarDay {
        let day = calendar.startOfDay(for: date)
        let isImported = importedHistoryStartDay.map { day >= $0 } == true
            && journeyStartDay.map { day < $0 } == true
        let isJourneyStart = journeyStartDay.map {
            calendar.isDate(day, inSameDayAs: $0)
        } == true

        return StatsCalendarDay(
            slot: slot,
            date: day,
            steps: stepsByDay[day] ?? 0,
            isImportedFromAppleHealth: isImported,
            isJourneyStart: isJourneyStart
        )
    }
}

private struct CalendarProvenanceLegend: View {
    let showsImportedHistory: Bool
    let journeyStartDate: Date?

    var body: some View {
        if showsImportedHistory || journeyStartDate != nil {
            HStack(spacing: 10) {
                if showsImportedHistory {
                    legendItem(
                        title: "APPLE HEALTH · IMPORTED",
                        marker: .imported
                    )
                }

                if showsImportedHistory, journeyStartDate != nil {
                    Spacer(minLength: 4)
                }

                if let journeyStartDate {
                    legendItem(
                        title: "JOURNEY BEGAN \(journeyStartDate.formatted(.dateTime.month(.abbreviated).day()).uppercased())",
                        marker: .journeyStart
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private func legendItem(
        title: String,
        marker: CalendarProvenanceMarker.Kind
    ) -> some View {
        HStack(spacing: 5) {
            CalendarProvenanceMarker(kind: marker)
            Text(title)
                .font(NanoFont.aldrich(8))
                .tracking(0.65)
                .foregroundStyle(NanoTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }
}

private struct CalendarProvenanceMarker: View {
    enum Kind: Equatable {
        case imported
        case journeyStart
    }

    let kind: Kind

    var body: some View {
        Group {
            switch kind {
            case .imported:
                Circle()
                    .fill(NanoTheme.secondaryText.opacity(0.78))
            case .journeyStart:
                Circle()
                    .fill(NanoTheme.background)
                    .stroke(NanoTheme.teal, lineWidth: 1.5)
            }
        }
        .frame(
            width: kind == .imported ? 4 : 7,
            height: kind == .imported ? 4 : 7
        )
        .accessibilityHidden(true)
    }
}

private struct CalendarArrow: View {
    let systemName: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? .white : NanoTheme.mutedText)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(NanoTheme.elevated.opacity(0.68))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
    }
}

private struct StatsCalendarCell: View {
    let day: StatsCalendarDay
    let dailyGoal: Int
    let calendar: Calendar
    let action: () -> Void

    private var ratio: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(Double(day.steps) / Double(dailyGoal), 1)
    }

    private var isFuture: Bool {
        guard let date = day.date else { return false }
        return calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())
    }

    var body: some View {
        Group {
            if let date = day.date {
                Button(action: action) {
                    VStack(spacing: 1) {
                        Text(date.formatted(.dateTime.day()))
                            .font(NanoFont.aldrich(12))
                            .foregroundStyle(ratio >= 1 ? NanoTheme.background : .white)
                        Text(day.steps > 0 ? day.steps.formatted(.number.notation(.compactName)) : "")
                            .font(NanoFont.aldrich(8))
                            .foregroundStyle(ratio >= 1 ? NanoTheme.background : NanoTheme.teal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(cellBackground(date))
                    .overlay(alignment: .topTrailing) {
                        if day.isJourneyStart {
                            CalendarProvenanceMarker(kind: .journeyStart)
                                .padding(5)
                        } else if day.isImportedFromAppleHealth {
                            CalendarProvenanceMarker(kind: .imported)
                                .padding(6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isFuture)
                .opacity(isFuture ? 0.35 : 1)
                .accessibilityLabel(accessibilityLabel(for: date))
            } else {
                Color.clear
            }
        }
        .aspectRatio(0.82, contentMode: .fit)
    }

    private func cellBackground(_ date: Date) -> some View {
        let hasSteps = day.steps > 0
        let isToday = calendar.isDateInToday(date)
        return RoundedRectangle(cornerRadius: 10)
            .fill(
                ratio >= 1
                    ? NanoTheme.teal
                    : NanoTheme.teal.opacity(hasSteps ? 0.10 + ratio * 0.25 : 0.015)
            )
            .stroke(
                isToday ? NanoTheme.teal : NanoTheme.teal.opacity(hasSteps ? 0.30 : 0.08),
                lineWidth: isToday ? 2 : 1
            )
    }

    private func accessibilityLabel(for date: Date) -> String {
        var parts = [
            date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()),
            "\(day.steps.formatted()) steps",
        ]
        if day.isImportedFromAppleHealth {
            parts.append("imported from Apple Health")
        } else if day.isJourneyStart {
            parts.append("Nanobeasts journey began")
        }
        return parts.joined(separator: ", ")
    }
}

private struct WeeklyBarChart: View {
    let days: [StatsCalendarDay]
    let dailyGoal: Int
    let calendar: Calendar
    let onSelect: (StatsCalendarDay) -> Void

    private var scaleMaximum: Int {
        max(dailyGoal, max(days.map(\.steps).max() ?? 1, 1))
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days) { day in
                WeeklyBar(
                    day: day,
                    dailyGoal: dailyGoal,
                    scaleMaximum: scaleMaximum,
                    calendar: calendar
                ) {
                    onSelect(day)
                }
            }
        }
        .frame(minHeight: 154)
    }
}

private struct WeeklyBar: View {
    let day: StatsCalendarDay
    let dailyGoal: Int
    let scaleMaximum: Int
    let calendar: Calendar
    let action: () -> Void

    private var isFuture: Bool {
        guard let date = day.date else { return false }
        return calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())
    }

    private var barFraction: Double {
        guard scaleMaximum > 0 else { return 0 }
        return min(max(Double(day.steps) / Double(scaleMaximum), day.steps > 0 ? 0.08 : 0), 1)
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(day.date?.formatted(.dateTime.weekday(.narrow)) ?? "")
                .font(NanoFont.aldrich(10))
                .foregroundStyle(isFuture ? NanoTheme.mutedText : NanoTheme.teal)

            Button(action: action) {
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(NanoTheme.elevated)
                        if day.steps > 0 && !isFuture {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            NanoTheme.teal.opacity(day.steps >= dailyGoal ? 1 : 0.68),
                                            NanoTheme.teal.opacity(0.28)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: proxy.size.height * barFraction)
                        }
                    }
                }
                .frame(height: 104)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.clear, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if day.isJourneyStart {
                        CalendarProvenanceMarker(kind: .journeyStart)
                            .padding(9)
                    } else if day.isImportedFromAppleHealth {
                        CalendarProvenanceMarker(kind: .imported)
                            .padding(10)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isFuture)
            .opacity(isFuture ? 0.35 : 1)
            .accessibilityLabel(accessibilityLabel)

            Text(day.date?.formatted(.dateTime.day()) ?? "")
                .font(NanoFont.aldrich(10))
                .foregroundStyle(NanoTheme.secondaryText)
            Text(day.steps > 0 ? day.steps.formatted(.number.notation(.compactName)) : "–")
                .font(NanoFont.aldrich(8))
                .foregroundStyle(day.steps > 0 ? .white : NanoTheme.mutedText)
        }
        .frame(maxWidth: .infinity)
    }

    private var accessibilityLabel: String {
        guard let date = day.date else { return "Calendar day" }
        var parts = [
            date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()),
            "\(day.steps.formatted()) steps",
        ]
        if day.isImportedFromAppleHealth {
            parts.append("imported from Apple Health")
        } else if day.isJourneyStart {
            parts.append("Nanobeasts journey began")
        }
        return parts.joined(separator: ", ")
    }
}

struct StatsCalendarDay: Identifiable {
    let slot: Int
    let date: Date?
    let steps: Int
    let isImportedFromAppleHealth: Bool
    let isJourneyStart: Bool

    init(
        slot: Int,
        date: Date?,
        steps: Int,
        isImportedFromAppleHealth: Bool = false,
        isJourneyStart: Bool = false
    ) {
        self.slot = slot
        self.date = date
        self.steps = steps
        self.isImportedFromAppleHealth = isImportedFromAppleHealth
        self.isJourneyStart = isJourneyStart
    }

    var id: String {
        if let date {
            return String(Int(date.timeIntervalSince1970))
        }
        return "empty-\(slot)"
    }
}

private struct DailyFieldReportView: View {
    let day: StatsCalendarDay
    let dailyGoal: Int
    let discoveryEvents: [CreatureDiscoveryEvent]
    let workouts: [WorkoutHistoryRecord]
    let distanceUnit: DistanceUnitPreference

    @Environment(\.dismiss) private var dismiss
    @State private var selectedWorkout: WorkoutHistoryRecord?
    @State private var workoutsExpanded = false

    private var progress: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(Double(day.steps) / Double(dailyGoal), 1)
    }

    private var goalPercent: Int {
        guard dailyGoal > 0 else { return 0 }
        return min(Int((Double(day.steps) / Double(dailyGoal) * 100).rounded()), 999)
    }

    private var distance: Double {
        distanceUnit.value(forSteps: day.steps)
    }

    private var discoveriesForDay: [CreatureDiscoveryEvent] {
        guard let date = day.date else { return [] }
        let calendar = Calendar.autoupdatingCurrent
        return discoveryEvents
            .filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var workoutsForDay: [WorkoutHistoryRecord] {
        guard let date = day.date else { return [] }
        let calendar = Calendar.autoupdatingCurrent
        return workouts
            .filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("DAILY FIELD REPORT")
                                .font(NanoFont.aldrich(12))
                                .tracking(1.7)
                                .foregroundStyle(NanoTheme.teal)
                            Text(
                                day.date?.formatted(
                                    .dateTime
                                        .weekday(.wide)
                                        .month(.wide)
                                        .day()
                                        .year()
                                ).uppercased() ?? ""
                            )
                            .font(NanoFont.aldrich(18))
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                        }

                        Spacer(minLength: 8)

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .accessibilityLabel("Close daily field report")
                    }
                    .padding(.bottom, 5)

                    if day.isImportedFromAppleHealth {
                        ImportedHistoryProvenanceView()
                    }

                    VStack(spacing: 10) {
                        Text(day.steps.formatted())
                            .font(NanoFont.aldrich(48))
                            .foregroundStyle(.white)
                        Text("STEPS RECORDED")
                            .font(NanoFont.aldrich(10))
                            .tracking(1.7)
                            .foregroundStyle(NanoTheme.teal)

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(NanoTheme.teal.opacity(0.12))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [NanoTheme.teal, NanoTheme.teal.opacity(0.64)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: proxy.size.width * progress)
                            }
                        }
                        .frame(height: 8)
                    }
                    .padding(.vertical, 8)
                    .nanoHUDCard(illuminated: true)

                    HStack(spacing: 12) {
                        ReportMetric(
                            icon: "flag.fill",
                            value: "\(goalPercent)%",
                            label: "DAILY GOAL"
                        )
                        ReportMetric(
                            icon: "location.fill",
                            value:
                                distance.formatted(
                                    .number.precision(.fractionLength(1))
                                ) + " \(distanceUnit.abbreviation)",
                            label: "DISTANCE"
                        )
                    }

                    if !workoutsForDay.isEmpty {
                        dailyWorkoutsSection
                    }

                    VStack(spacing: 16) {
                        HStack {
                            Text("DISCOVERY LOG")
                                .font(NanoFont.aldrich(13))
                                .tracking(1.2)
                            Spacer()
                            Text(discoveriesForDay.count.formatted())
                                .font(NanoFont.aldrich(11))
                                .foregroundStyle(NanoTheme.teal)
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 11)
                                        .fill(NanoTheme.teal.opacity(0.08))
                                        .stroke(NanoTheme.teal.opacity(0.35), lineWidth: 1)
                                )
                        }

                        if discoveriesForDay.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "cube.transparent")
                                    .font(.system(size: 30, weight: .medium))
                                    .foregroundStyle(NanoTheme.mutedText)
                                Text("NO NEW SPECIMENS")
                                    .font(NanoFont.aldrich(13))
                                Text("No egg, hatch, or evolution signals were recorded for this date.")
                                    .font(NanoFont.aldrich(10))
                                    .foregroundStyle(NanoTheme.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(4)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                            .nanoHUDCard()
                        } else {
                            ForEach(discoveriesForDay) { event in
                                DiscoveryLogRow(event: event)
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .onChange(of: day.date) { workoutsExpanded = false }
        .sheet(item: $selectedWorkout) { workout in
            WorkoutHistoryDetailView(
                workout: workout,
                distanceUnit: distanceUnit
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    }

    private var dailyWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $workoutsExpanded) {
                ForEach(workoutsForDay) { workout in
                    Button {
                        selectedWorkout = workout
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: workout.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(NanoTheme.background)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(NanoTheme.orange))

                        VStack(alignment: .leading, spacing: 5) {
                            Text(workout.name)
                                .font(NanoFont.aldrich(12))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text(workoutSummary(workout))
                                .font(NanoFont.spaceMono(9))
                                .foregroundStyle(NanoTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }

                        Spacer(minLength: 6)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NanoTheme.orange)
                    }
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(workout.name), \(workoutSummary(workout))"
                )
                .accessibilityHint("Shows full workout details")
            }
            } label: {
                HStack {
                    Text("WORKOUTS")
                        .font(NanoFont.aldrich(13))
                        .tracking(1.2)
                    Spacer()
                    Text(workoutsForDay.count.formatted())
                        .font(NanoFont.spaceMono(11, bold: true))
                        .foregroundStyle(NanoTheme.orange)
                }
                .frame(minHeight: 32)
            }
            .tint(NanoTheme.orange)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NanoTheme.surface)
                .stroke(NanoTheme.orange.opacity(0.34), lineWidth: 1)
        )
    }

    private func workoutSummary(_ workout: WorkoutHistoryRecord) -> String {
        var parts = [formattedWorkoutDuration(workout.duration)]
        if workout.steps > 0 {
            parts.append("\(workout.steps.formatted()) steps")
        } else if workout.distanceMiles > 0 {
            parts.append(formattedWorkoutDistance(workout.distanceMiles))
        }
        if workout.calories > 0 {
            parts.append("\(Int(workout.calories.rounded())) kcal")
        }
        return parts.joined(separator: " · ")
    }

    private func formattedWorkoutDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int(duration.rounded()) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    private func formattedWorkoutDistance(_ miles: Double) -> String {
        let value = distanceUnit == .miles ? miles : miles * 1.609_344
        return value.formatted(
            .number.precision(.fractionLength(value < 10 ? 2 : 1))
        ) + " \(distanceUnit.abbreviation.lowercased())"
    }
}

private struct ImportedHistoryProvenanceView: View {
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "heart.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NanoTheme.secondaryText)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(NanoTheme.elevated.opacity(0.78))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("APPLE HEALTH HISTORY")
                    .font(NanoFont.aldrich(10))
                    .tracking(1.1)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("Imported before your Nanobeasts journey")
                    .font(NanoFont.aldrich(9))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(NanoTheme.surface.opacity(0.72))
                .stroke(NanoTheme.secondaryText.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct DiscoveryLogRow: View {
    let event: CreatureDiscoveryEvent

    var body: some View {
        HStack(spacing: 13) {
            CreatureArtworkView(stage: event.creatureStage)
                .frame(width: 62, height: 62)
                .padding(5)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(NanoTheme.background)
                        .stroke(NanoTheme.teal.opacity(0.30), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(event.kind.title)
                    .font(NanoFont.aldrich(8))
                    .tracking(1.1)
                    .foregroundStyle(NanoTheme.teal)
                Text(event.name.uppercased())
                    .font(NanoFont.aldrich(13))
                    .lineLimit(2)
                Text(event.timestamp.formatted(.dateTime.hour().minute()))
                    .font(NanoFont.aldrich(9))
                    .foregroundStyle(NanoTheme.secondaryText)
            }

            Spacer(minLength: 6)

            Image(systemName: event.kind.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NanoTheme.teal)
        }
        .nanoHUDCard(radius: 17, padding: 12)
    }
}

private struct ReportMetric: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(NanoTheme.teal)
            Text(value)
                .lineLimit(1).minimumScaleFactor(0.75)
                .font(NanoFont.aldrich(18))
            Text(label)
                .lineLimit(1).minimumScaleFactor(0.75)
                .font(NanoFont.aldrich(9))
                .tracking(1)
                .foregroundStyle(NanoTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .nanoHUDCard()
    }
}
