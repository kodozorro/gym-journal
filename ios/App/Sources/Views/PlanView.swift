import SwiftUI
import GymJournalCore

// Экран «План»: все недели программы и дни в них. Отсюда открывается любой день.

struct PlanScreen: View {
    @EnvironmentObject private var model: AppModel

    private static func anchor(_ week: Int?) -> String {
        "week-\(week ?? 0)"
    }

    var body: some View {
        let state = model.sync
        if !state.configured || state.snapshot == nil {
            ScreenScroll {
                EmptyState(
                    title: "Плана пока нет",
                    text: state.configured
                        ? "Журнал ещё не загружен из таблицы."
                        : "План появится, когда вы подключите таблицу."
                ) {
                    Button(state.configured ? "На главный экран" : "Открыть настройки") {
                        model.go(state.configured ? .today : .settings)
                    }
                    .buttonStyle(.app(.soft))
                }
            }
        } else {
            let weeks = Stats.weeks(state.journal, start: model.start)
            if weeks.isEmpty {
                ScreenScroll {
                    EmptyState(title: "Журнал пуст", text: "В листе «Журнал» нет строк с датой и упражнением.")
                }
            } else {
                let walked = Dictionary(
                    Stats.weeklyWalk(state.journal, start: model.start).map { ($0.week, $0.km) },
                    uniquingKeysWith: { first, _ in first }
                )
                // план открывается на текущей неделе
                ScreenScroll(initialTarget: PlanScreen.anchor(Stats.weekOfDate(weeks, date: model.today))) {
                    AlertsView()
                    ForEach(weeks) { week in
                        WeekSection(
                            week: week,
                            walked: week.week.flatMap { walked[$0] },
                            goal: state.snapshot?.walkGoalKm,
                            today: model.today
                        )
                        .id(PlanScreen.anchor(week.week))
                    }
                }
            }
        }
    }
}

/// Неделя: номер, даты, километры ходьбы и дни.
private struct WeekSection: View {
    let week: JournalWeek
    /// Пройдено за неделю или nil, если записей о ходьбе нет.
    let walked: Double?
    let goal: Double?
    let today: String

    var body: some View {
        let first = week.days.first?.date ?? ""
        let last = week.days.last?.date ?? first
        let km = Present.weekKm(walked: walked, goal: goal, started: first <= today)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(week.week.map { "Неделя \($0)" } ?? "Без номера недели")
                        .font(.app(17, .bold))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(Days.formatRange(first, last))
                        .font(.app(15))
                        .foregroundStyle(Palette.ink2)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !km.isEmpty {
                    Text(km)
                        .font(.app(14))
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(EdgeInsets(top: 6, leading: 2, bottom: 0, trailing: 2))
            DaysList(days: week.days)
        }
    }
}
