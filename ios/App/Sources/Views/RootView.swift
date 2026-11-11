import SwiftUI
import UIKit
import GymJournalCore

// Каркас приложения: шапка, экран, нижняя панель с таймером отдыха и вкладками, сообщение и лист.

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    /// Открыта клавиатура телефона: нижняя панель убирается, чтобы не ехать вверх вместе с ней.
    @State private var typing = false

    var body: some View {
        ZStack {
            Palette.page.ignoresSafeArea()
            VStack(spacing: 0) {
                HeaderView()
                ScreenHost()
                if !typing {
                    DockView()
                }
            }
            .frame(maxWidth: Metrics.maxWidth)
            ToastHost()
            SheetHost()
        }
        .onAppear {
            model.start()
            model.applyTheme()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            typing = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            typing = false
        }
    }
}

// MARK: Шапка

private struct Heading {
    var title = "Сегодня"
    var sub = ""
    var back = false
}

struct HeaderView: View {
    @EnvironmentObject private var model: AppModel

    private func weekText(_ date: String) -> String {
        guard let week = model.day(date)?.week else { return "" }
        return " · неделя \(week)"
    }

    private var heading: Heading {
        var out = Heading()
        switch model.route {
        case .today:
            out.sub = Present.capitalized(Days.formatLongDay(model.today)) + weekText(model.today)
        case .day(let date):
            out.title = Present.capitalized(Days.formatDayMonth(date))
            out.sub = Present.capitalized(Days.weekdayName(date)) + weekText(date)
            out.back = true
        case .plan:
            out.title = "План"
            if let first = model.days.first, let last = model.days.last {
                out.sub = "\(Days.formatShortDay(first.date)) – \(Days.formatShortDay(last.date))"
            }
        case .progress:
            out.title = "Прогресс"
            let weeks = Stats.weeks(model.sync.journal, start: model.start).filter { $0.week != nil }
            if let current = Stats.weekOfDate(weeks, date: model.today), let last = weeks.last?.week {
                out.sub = "Неделя \(current) из \(last)"
            }
        case .settings:
            out.title = "Настройки"
        }
        return out
    }

    var body: some View {
        let head = heading
        HStack(spacing: 10) {
            if head.back {
                Button {
                    model.go(.plan)
                } label: {
                    Icon("chevronLeft")
                        .foregroundStyle(Palette.ink2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.press)
                .accessibilityLabel("К плану")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(head.title)
                    .font(.app(26, .bold))
                    .tracking(-0.26)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if !head.sub.isEmpty {
                    Text(head.sub)
                        .font(.app(15))
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PillView()
        }
        .padding(EdgeInsets(top: 10, leading: Metrics.pad, bottom: 8, trailing: Metrics.pad))
    }
}

/// Метка синхронизации: одним словом, что с записями. Открывает лист с подробностями.
struct PillView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let info = Present.pill(model.sync)
        let tinted = info.tone == .wait || info.tone == .bad
        Button {
            model.openSync()
        } label: {
            HStack(spacing: 6) {
                if info.tone == .busy {
                    TimelineView(.animation) { context in
                        let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
                        Icon(info.icon, size: 16).rotationEffect(.degrees(turn * 360))
                    }
                } else {
                    Icon(info.icon, size: 16)
                }
                Text(info.text)
                    .font(.app(13, .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(ink(info.tone))
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(fill(info.tone), in: Capsule())
            .overlay(Capsule().strokeBorder(tinted ? Color.clear : Palette.line, lineWidth: 1))
        }
        .buttonStyle(.press)
        .fixedSize()
        .accessibilityLabel("Синхронизация: \(info.text). Подробнее")
    }

    private func fill(_ tone: PillTone) -> Color {
        switch tone {
        case .plain, .busy: return Palette.surface
        case .wait: return Palette.warnSoft
        case .bad: return Palette.dangerSoft
        }
    }

    private func ink(_ tone: PillTone) -> Color {
        switch tone {
        case .plain, .busy: return Palette.ink2
        case .wait: return Palette.warnSoftInk
        case .bad: return Palette.dangerSoftInk
        }
    }
}

// MARK: Экран

struct ScreenHost: View {
    @EnvironmentObject private var model: AppModel

    private var dayDate: String? {
        if case .day(let date) = model.route { return date }
        return nil
    }

    var body: some View {
        ZStack {
            switch model.route.tab {
            case .today:
                TodayScreen()
            case .plan:
                // план остаётся под открытым днём: после возврата он стоит на том же месте
                PlanScreen()
                    .opacity(dayDate == nil ? 1 : 0)
                    .allowsHitTesting(dayDate == nil)
                    .accessibilityHidden(dayDate != nil)
                if let date = dayDate {
                    DayScreen(date: date)
                        .id(date)
                        .overlay(alignment: .leading) { backSwipe }
                }
            case .progress:
                ProgressScreen()
            case .settings:
                SettingsScreen()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Привычный жест iPhone: провести от левого края, чтобы вернуться к плану.
    private var backSwipe: some View {
        Color.clear
            .frame(width: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12).onEnded { value in
                    if value.translation.width > 50 { model.go(.plan) }
                }
            )
    }
}

// MARK: Нижняя панель

struct DockView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.line).frame(height: 1)
            if let workout = model.workout {
                WorkoutBar(workout: workout)
            }
            if let timer = model.timer {
                TimerBar(timer: timer)
            }
            TabBar()
        }
        .background(Palette.surface.ignoresSafeArea(edges: .bottom))
    }
}

struct TabBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let active = model.route.tab == tab
                Button {
                    model.go(tab.route)
                } label: {
                    VStack(spacing: 3) {
                        Icon(tab.icon)
                        Text(tab.title)
                            .font(.app(11, active ? .bold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(active ? Palette.accentText : Palette.ink3)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.press)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }
}

/// Панель отдыха: сколько осталось, «+30 с» и «Стоп». После конца отдыха зеленеет и считает, сколько прошло.
struct TimerBar: View {
    @EnvironmentObject private var model: AppModel
    let timer: RestTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let now = context.date
            let over = timer.isOver(now: now)
            HStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(over ? "Отдых окончен" : "Отдых")
                        .font(.app(over ? 17 : 15, over ? .bold : .regular))
                        .foregroundStyle(over ? Palette.okSoftInk : Palette.ink2)
                        .lineLimit(1)
                    Text(over ? "+\(RestTimer.clock(timer.overtime(now: now)))" : RestTimer.clock(timer.left(now: now)))
                        .font(.app(over ? 17 : 30, over ? .semibold : .bold))
                        .monospacedDigit()
                        .foregroundStyle(over ? Palette.okSoftInk : Palette.ink)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !over {
                    Button("+30 с") {
                        model.extendRest(30)
                    }
                    .buttonStyle(.app(.plain, small: true))
                }
                Button(over ? "Закрыть" : "Стоп") {
                    model.stopRest()
                }
                .buttonStyle(.app(over ? .surface : .plain, small: true))
            }
            .padding(EdgeInsets(top: 6, leading: Metrics.pad, bottom: 6, trailing: 12))
            .frame(minHeight: 60)
            .background {
                ZStack {
                    if over { Palette.okSoft }
                    if model.timerFlash { FlashView() }
                }
            }
            .overlay(alignment: .top) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Palette.markTrack
                        (over ? Palette.ok : Palette.mark)
                            .frame(width: geometry.size.width * timer.progress(now: now))
                    }
                }
                .frame(height: 4)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.line).frame(height: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Отдых")
    }
}

/// Вспышка в конце отдыха: панель четыре раза за две секунды окрашивается цветом акцента.
private struct FlashView: View {
    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 2 * Double.pi
            Palette.accent.opacity(abs(sin(phase)))
        }
    }
}

/// Панель тренировки, которая записывается в «Здоровье»: вид, время и кнопка «Завершить».
struct WorkoutBar: View {
    @EnvironmentObject private var model: AppModel
    let workout: LiveWorkout

    static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        let tail = rest < 10 ? "0\(rest)" : "\(rest)"
        if hours == 0 { return "\(minutes):\(tail)" }
        return "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(tail)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: workout.onWatch ? "applewatch" : "iphone")
                .font(.system(size: 17, weight: .semibold))
                .accessibilityLabel(workout.onWatch ? "Тренировку ведут часы" : "Тренировку ведёт телефон")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(workout.kind.title)
                        .font(.app(15, .semibold))
                    Text(WorkoutBar.clock(Numbers.int(context.date.timeIntervalSince(workout.startedAt))))
                        .font(.app(17, .bold))
                        .monospacedDigit()
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(model.workoutEnding ? "Завершаю…" : "Завершить") {
                model.askStopWorkout()
            }
            .buttonStyle(.app(.primary, small: true))
            .disabled(model.workoutEnding)
        }
        .foregroundStyle(Palette.accentSoftInk)
        .padding(EdgeInsets(top: 8, leading: Metrics.pad, bottom: 8, trailing: 12))
        .background(Palette.accentSoft)
    }
}

// MARK: Сообщение

struct ToastHost: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if let toast = model.toast {
                Text(toast.text)
                    .font(.app(15, .semibold))
                    .foregroundStyle(Palette.surface)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Palette.shadow, radius: 14, y: 8)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 84)
                    .id(toast.id)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .frame(maxWidth: 520)
        .allowsHitTesting(false)
    }
}
