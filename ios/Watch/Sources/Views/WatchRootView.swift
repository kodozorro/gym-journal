import SwiftUI
import GymJournalCore

// Главный экран часов: список дня. Из него открываются упражнение, ходьба и идущая тренировка.
// Отсчёт отдыха закрывает экран целиком: во время отдыха на часах нужен только он.

struct WatchRootView: View {
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        ZStack {
            NavigationStack(path: $model.path) {
                DayScreen()
                    .navigationDestination(for: WatchRoute.self) { route in
                        // после записи подхода экран сменяется экраном соседа по паре: у каждого
                        // упражнения свой экран со своими повторами
                        switch route {
                        case .exercise(let key):
                            ExerciseScreen(key: key)
                                .id(key)
                        case .walk(let key):
                            WalkScreen(key: key)
                                .id(key)
                        case .workout:
                            WorkoutScreen()
                        }
                    }
            }
            if let rest = model.activeRest {
                RestOverlay(rest: rest)
                    .transition(.opacity)
                    .zIndex(1)
            }
            if let notice = model.notice {
                NoticeView(notice: notice)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.activeRest)
        .animation(.easeInOut(duration: 0.2), value: model.notice)
        .sheet(item: $model.walkPrompt) { prompt in
            WalkSegmentSheet(prompt: prompt)
                .environmentObject(model)
        }
        .sheet(item: $model.weightPrompt) { prompt in
            WeightSheet(key: prompt.key)
                .environmentObject(model)
        }
    }
}

/// Список дня или объяснение, почему его нет.
private struct DayScreen: View {
    @EnvironmentObject private var model: WatchModel

    private var title: String {
        let state = model.state
        guard state.configured, !model.stale, let date = state.date else { return "Тренировки" }
        return date == state.today ? "Сегодня" : Days.formatSheetDay(date)
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
        }
        .navigationTitle(title)
    }

    @ViewBuilder private var content: some View {
        let state = model.state
        if state.stamp == 0 {
            MessageView(
                icon: "iphone",
                title: "Откройте «Тренировки» на iPhone",
                text: "Часы покажут тренировку, когда получат её с телефона."
            )
        } else if !state.configured {
            MessageView(
                icon: "tablecells",
                title: "Таблица не подключена",
                text: "Подключите её в приложении на iPhone."
            )
        } else if model.stale {
            MessageView(
                icon: "arrow.triangle.2.circlepath",
                title: "Нет сегодняшнего дня",
                text: "Откройте приложение на iPhone: часы получат свежий журнал."
            )
        } else if state.date == nil {
            MessageView(
                icon: "moon.zzz",
                title: "Сегодня тренировки нет",
                text: state.next.isEmpty ? "По плану день отдыха." : "Следующая: \(state.next)."
            )
        } else {
            DayList()
        }
    }
}

private struct DayList: View {
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        let state = model.state
        let rows = model.rows
        let split = Journal.splitDay(rows)
        let progress = Journal.dayProgress(rows)
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.watch(16, .semibold))
                    .foregroundStyle(WatchPalette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    MeterBar(done: progress.done, total: progress.total)
                    Text("\(progress.done) из \(progress.total)")
                        .font(.watch(13))
                        .monospacedDigit()
                        .foregroundStyle(WatchPalette.ink2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Записано упражнений: \(progress.done) из \(progress.total)")
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)

            WorkoutArea()

            ForEach(Array(split.pairs.enumerated()), id: \.offset) { index, pair in
                GroupTitle(text: split.pairs.count > 1 ? "Пара \(index + 1)" : "Упражнения")
                ForEach(pair) { row in
                    ExerciseRow(row: row, last: state.last[row.key])
                }
            }
            if !split.walks.isEmpty {
                GroupTitle(text: "Ходьба")
                ForEach(split.walks) { row in
                    WalkRow(row: row)
                }
            }
            if !model.ops.isEmpty, !model.reachable, model.demo == nil {
                Text("Записи уйдут на iPhone, когда он будет рядом.")
                    .font(.watch(12))
                    .foregroundStyle(WatchPalette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }
}

/// Полоса «записано из всего».
private struct MeterBar: View {
    let done: Int
    let total: Int

    var body: some View {
        GeometryReader { geometry in
            let share = total > 0 ? CGFloat(done) / CGFloat(total) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(WatchPalette.markTrack)
                Capsule()
                    .fill(done == total && total > 0 ? WatchPalette.ok : WatchPalette.mark)
                    .frame(width: max(0, geometry.size.width * min(1, share)))
            }
        }
        .frame(height: 5)
    }
}

private struct GroupTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.watch(11, .semibold))
            .foregroundStyle(WatchPalette.ink3)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct DoneMark: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 18))
            .foregroundStyle(WatchPalette.ok)
            .accessibilityLabel("записано")
    }
}

/// Строка силового упражнения: название и коротко, что записано или что по плану.
private struct ExerciseRow: View {
    @EnvironmentObject private var model: WatchModel
    let row: JournalRow
    let last: JournalRow?

    /// Сделанное, а если записей нет — план и прошлый вес: «3 × 10–12 · 40 кг».
    private var brief: String {
        if row.hasData { return row.summary }
        let before = last?.weight.map { "\(Numbers.format($0)) кг" } ?? ""
        return [Present.planChip(row), before].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        Button {
            model.open(row.key)
        } label: {
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.exercise)
                        .font(.watch(15, .semibold))
                        .foregroundStyle(WatchPalette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(brief)
                        .font(.watch(13))
                        .monospacedDigit()
                        .foregroundStyle(row.hasData ? WatchPalette.ink2 : WatchPalette.ink3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if row.isDone { DoneMark() }
            }
        }
        .buttonStyle(WatchRowStyle())
    }
}

/// Строка ходьбы: название и записанные километры или план.
private struct WalkRow: View {
    @EnvironmentObject private var model: WatchModel
    let row: JournalRow

    var body: some View {
        Button {
            model.path = [.walk(row.key)]
        } label: {
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.exercise)
                        .font(.watch(15, .semibold))
                        .foregroundStyle(WatchPalette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(row.hasData ? row.summary : row.plan)
                        .font(.watch(13))
                        .monospacedDigit()
                        .foregroundStyle(row.hasData ? WatchPalette.ink2 : WatchPalette.ink3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if row.isDone { DoneMark() }
            }
        }
        .buttonStyle(WatchRowStyle())
    }
}

/// Тренировка в «Здоровье»: идущая или кнопки, чтобы её начать.
private struct WorkoutArea: View {
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        if let workout = model.workout {
            Button {
                model.path = [.workout]
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: WorkoutLook.icon(workout.kind))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(WatchPalette.ok)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(workout.kind.title)
                            .font(.watch(14, .semibold))
                            .foregroundStyle(WatchPalette.accentSoftInk)
                        Text(workout.startedAt, style: .timer)
                            .font(.watch(15, .semibold, rounded: true))
                            .monospacedDigit()
                            .foregroundStyle(WatchPalette.ink)
                    }
                    Spacer(minLength: 0)
                    if let heart = model.metrics.heartRate {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(WatchPalette.danger)
                            Text(Numbers.format(heart, digits: 0))
                                .font(.watch(15, .semibold, rounded: true))
                                .monospacedDigit()
                                .foregroundStyle(WatchPalette.ink)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Пульс \(Numbers.format(heart, digits: 0))")
                    }
                }
            }
            .buttonStyle(WatchRowStyle(fill: WatchPalette.accentSoft))
        } else if let theirs = model.state.workout, !theirs.onWatch {
            Text("\(theirs.kind.title): тренировку записывает iPhone.")
                .font(.watch(13))
                .foregroundStyle(WatchPalette.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        } else {
            ForEach(model.workoutOffer, id: \.self) { kind in
                Button {
                    model.startWorkout(kind)
                } label: {
                    Label(
                        model.workoutStarting == kind ? "Запускаю…" : WorkoutLook.startTitle(kind),
                        systemImage: WorkoutLook.icon(kind)
                    )
                }
                .buttonStyle(.watch(.soft))
                .disabled(model.workoutStarting != nil)
            }
        }
    }
}

/// Значки и подписи видов тренировки.
enum WorkoutLook {
    static func icon(_ kind: WorkoutKind) -> String {
        switch kind {
        case .strength: return "dumbbell.fill"
        case .walk: return "figure.walk"
        }
    }

    static func startTitle(_ kind: WorkoutKind) -> String {
        switch kind {
        case .strength: return "Начать силовую"
        case .walk: return "Начать ходьбу"
        }
    }
}

/// Объяснение вместо списка: значок, заголовок и что делать.
struct MessageView: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(WatchPalette.accentText)
                .padding(.top, 6)
                .accessibilityHidden(true)
            Text(title)
                .font(.watch(16, .semibold))
                .foregroundStyle(WatchPalette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !text.isEmpty {
                Text(text)
                    .font(.watch(14))
                    .foregroundStyle(WatchPalette.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
    }
}

/// Короткое сообщение поверх экрана. Касание убирает его.
private struct NoticeView: View {
    @EnvironmentObject private var model: WatchModel
    let notice: WatchNotice

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Button {
                model.dismissNotice()
            } label: {
                Text(notice.text)
                    .font(.watch(14, .semibold))
                    .foregroundStyle(WatchPalette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(WatchPalette.surface2, in: RoundedRectangle(cornerRadius: WatchMetrics.radius))
                    .overlay(
                        RoundedRectangle(cornerRadius: WatchMetrics.radius)
                            .strokeBorder(WatchPalette.lineStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }
}
