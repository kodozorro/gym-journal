import SwiftUI
import GymJournalCore

// Экран «Прогресс»: текущая неделя, лучший вес по упражнению и ходьба по неделям.
// Показатели те же, что на листе «Прогресс» таблицы.

struct ProgressScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let state = model.sync
        ScreenScroll {
            if let snapshot = state.snapshot, state.configured, !state.journal.isEmpty {
                ProgressBody(data: ProgressData(
                    journal: state.journal, start: model.start, today: model.today,
                    goal: snapshot.walkGoalKm, wanted: model.settings.chartExercise
                ))
            } else {
                EmptyState(
                    title: "Пока нечего показывать",
                    text: state.configured
                        ? "Графики появятся после первых записей."
                        : "Графики появятся, когда вы подключите таблицу и запишете первую тренировку."
                ) {
                    if !state.configured {
                        Button("Открыть настройки") {
                            model.go(.settings)
                        }
                        .buttonStyle(.app(.soft))
                    }
                }
            }
        }
    }
}

/// Всё, что показывает экран, посчитанное из журнала.
private struct ProgressData {
    var xMin: Int
    var xMax: Int
    /// Цель по ходьбе, километров в неделю, или nil.
    var goal: Double?
    var kmNow: Double
    var daysNow: Int
    var doneNow: Int
    var exercises: [String]
    /// Упражнение, выбранное для графика веса.
    var chosen: String
    var best: [WeeklyBest]
    var history: [JournalRow]
    var walkWeeks: [WeeklyWalk]
    private var ranges: [Int: String]

    init(journal: [JournalRow], start: String?, today: String, goal: Double?, wanted: String) {
        let weeks = Stats.weeks(journal, start: start).filter { $0.week != nil }
        let numbers = weeks.compactMap { $0.week }
        xMin = min(1, numbers.min() ?? 1)
        xMax = max(12, numbers.max() ?? 12)
        var ranges: [Int: String] = [:]
        var days: [Int: [JournalDay]] = [:]
        for week in weeks {
            guard let number = week.week, let first = week.days.first, let last = week.days.last else { continue }
            ranges[number] = Days.formatRange(first.date, last.date)
            days[number] = week.days
        }
        self.ranges = ranges

        let nowWeek = Stats.weekOfDate(weeks, date: today) ?? numbers.first ?? 1
        let walk = Stats.weeklyWalk(journal, start: start)
        self.goal = (goal ?? 0) > 0 ? goal : nil
        kmNow = walk.first { $0.week == nowWeek }?.km ?? 0
        let current = days[nowWeek] ?? []
        daysNow = current.count
        doneNow = current.filter { Journal.dayStatus($0.rows, date: $0.date, today: today) == .done }.count

        let exercises = Stats.exerciseList(journal)
        self.exercises = exercises
        var chosen = wanted
        if !exercises.contains(wanted) {
            let withData = exercises.first { !Stats.weeklyBest(journal, exercise: $0, start: start).isEmpty }
            chosen = withData ?? exercises.first ?? ""
        }
        self.chosen = chosen
        best = chosen.isEmpty ? [] : Stats.weeklyBest(journal, exercise: chosen, start: start)
        history = chosen.isEmpty ? [] : Stats.exerciseHistory(journal, exercise: chosen)
        walkWeeks = walk.filter { $0.km > 0 || $0.min > 0 }
    }

    /// «неделя 3 · 9 ноя – 15 ноя».
    func weekTitle(_ week: Int) -> String {
        guard let range = ranges[week] else { return "неделя \(week)" }
        return "неделя \(week) · \(range)"
    }
}

private struct ProgressBody: View {
    @EnvironmentObject private var model: AppModel
    let data: ProgressData

    private func valueText(_ value: String, _ tail: String) -> AttributedString {
        var head = AttributedString(value)
        head.font = Font.app(28, .bold)
        head.foregroundColor = Palette.ink
        var rest = AttributedString(tail)
        rest.font = Font.app(15, .medium)
        rest.foregroundColor = Palette.ink2
        return head + rest
    }

    private func tile<Extra: View>(_ label: String, _ value: AttributedString, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.app(14))
                .foregroundStyle(Palette.ink2)
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            extra()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private func heading(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.app(19, .bold))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(sub)
                .font(.app(14))
                .foregroundStyle(Palette.ink2)
        }
    }

    var body: some View {
        let goal = data.goal
        HStack(alignment: .top, spacing: Metrics.gap) {
            tile("Ходьба", valueText(Numbers.format(data.kmNow), goal.map { " из \(Numbers.format($0)) км" } ?? " км")) {
                if let goal {
                    MeterView(share: data.kmNow / goal, label: "Километры за неделю")
                }
            }
            tile("Тренировки", valueText(String(data.doneNow), " из \(data.daysNow)")) {
                MeterView(
                    share: data.daysNow > 0 ? Double(data.doneNow) / Double(data.daysNow) : 0,
                    label: "Тренировки за неделю"
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)

        if !data.exercises.isEmpty {
            weights
        }
        walking
    }

    // MARK: Вес

    private var weights: some View {
        let best = data.best
        let chosen = data.chosen
        let summary = best.map { "неделя \($0.week): \(Numbers.format($0.best)) кг" }.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 12) {
            heading("Лучший вес за неделю", "Килограммы по неделям программы")
            ExercisePicker(exercises: data.exercises, chosen: chosen)
            ChartView(
                kind: .line,
                id: "weight:\(chosen)",
                points: best.map {
                    ChartPoint(
                        x: $0.week, y: $0.best, value: "\(Numbers.format($0.best)) кг", title: data.weekTitle($0.week)
                    )
                },
                xMin: data.xMin,
                xMax: data.xMax,
                label: best.isEmpty
                    ? "Лучший вес по неделям, \(chosen): записей нет"
                    : "Лучший вес по неделям, \(chosen): \(summary)",
                empty: "По этому упражнению ещё нет записей с весом."
            )
            if !best.isEmpty {
                TableToggle {
                    DataTable(
                        columns: ["Неделя", "Лучший вес, кг"],
                        rows: best.map { [data.weekTitle($0.week), Numbers.format($0.best)] }
                    )
                }
            }
            if !data.history.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    CapsTitle("Записи")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(data.history) { row in
                            HStack(alignment: .top, spacing: 10) {
                                Text(Days.formatSheetDay(row.date))
                                    .foregroundStyle(Palette.ink2)
                                    .lineLimit(1)
                                    .frame(width: 78, alignment: .leading)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(row.summary)
                                        .foregroundStyle(Palette.ink)
                                    if !row.note.isEmpty {
                                        Text(row.note)
                                            .font(.app(13))
                                            .foregroundStyle(Palette.ink2)
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.app(15))
                            .padding(.vertical, 9)
                            .overlay(alignment: .top) {
                                Rectangle().fill(Palette.line).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
        .card()
    }

    // MARK: Ходьба

    private var walking: some View {
        let weeks = data.walkWeeks
        let goal = data.goal
        let summary = weeks.map { "неделя \($0.week): \(Numbers.format($0.km)) км" }.joined(separator: ", ")
        let goalText = goal.map { ". Цель \(Numbers.format($0)) км в неделю" } ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            heading("Ходьба по неделям", "Километры за неделю")
            ChartView(
                kind: .bars,
                id: "walk",
                points: weeks.map { week in
                    let title = data.weekTitle(week.week)
                    return ChartPoint(
                        x: week.week, y: week.km, value: "\(Numbers.format(week.km)) км",
                        title: week.min > 0 ? "\(title) · \(Numbers.format(week.min, digits: 0)) мин" : title
                    )
                },
                xMin: data.xMin,
                xMax: data.xMax,
                goal: goal.map { ChartGoal(value: $0, label: "цель \(Numbers.format($0)) км") },
                label: weeks.isEmpty
                    ? "Километры ходьбы по неделям: записей нет"
                    : "Километры ходьбы по неделям: \(summary)\(goalText)",
                empty: "Записей о ходьбе пока нет."
            )
            if !weeks.isEmpty {
                TableToggle {
                    DataTable(
                        columns: ["Неделя", "Км", "Мин"],
                        rows: weeks.map {
                            [data.weekTitle($0.week), Numbers.format($0.km), Numbers.format($0.min, digits: 0)]
                        }
                    )
                }
            }
        }
        .card()
    }
}

/// Выбор упражнения для графика веса: выглядит как поле со стрелкой, открывает список.
private struct ExercisePicker: View {
    @EnvironmentObject private var model: AppModel
    let exercises: [String]
    let chosen: String

    var body: some View {
        let selection = Binding<String>(
            get: { chosen },
            set: { name in model.update { $0.chartExercise = name } }
        )
        Menu {
            Picker("Упражнение", selection: selection) {
                ForEach(exercises, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(chosen)
                    .font(.app(17, .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Icon("chevronDown", size: 22)
                    .foregroundStyle(Palette.ink2)
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(minHeight: 52)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusSmall)
                    .strokeBorder(Palette.lineStrong, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Упражнение: \(chosen)")
    }
}

/// «Показать таблицей»: те же данные, что на графике, числами.
private struct TableToggle<Content: View>: View {
    @State private var open = false
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                open.toggle()
            } label: {
                Text("Показать таблицей")
                    .font(.app(15, .semibold))
                    .foregroundStyle(Palette.accentText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.press)
            .accessibilityValue(open ? "раскрыто" : "свёрнуто")
            if open {
                content
            }
        }
    }
}

/// Таблица под графиком: первый столбец слева, числа справа.
private struct DataTable: View {
    let columns: [String]
    let rows: [[String]]

    private func cell(_ text: String, column: Int, header: Bool) -> some View {
        Text(text)
            .font(.app(header ? 13 : 15, header ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(header ? Palette.ink2 : Palette.ink)
            .multilineTextAlignment(column == 0 ? .leading : .trailing)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: column == 0 ? .infinity : nil, alignment: column == 0 ? .leading : .trailing)
            .gridColumnAlignment(column == 0 ? .leading : .trailing)
    }

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, title in
                    cell(title, column: index, header: true)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Rectangle()
                    .fill(Palette.line)
                    .frame(height: 1)
                    .gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { index, text in
                        cell(text, column: index, header: false)
                    }
                }
            }
        }
    }
}
