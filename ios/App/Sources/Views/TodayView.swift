import SwiftUI
import GymJournalCore

// Экран тренировки: «Сегодня» и любой другой день журнала. То, что вокруг самого дня:
// приглашение подключить таблицу, первая загрузка, плашки о неполадках, день отдыха.

struct TodayScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScreenScroll {
            if !model.sync.configured {
                WelcomeView()
            } else if model.sync.snapshot == nil {
                FirstLoadView()
            } else {
                AlertsView()
                if model.days.isEmpty {
                    EmptyState(title: "Журнал пуст", text: "В листе «Журнал» нет строк с датой и упражнением.")
                } else if let day = model.day(model.today) {
                    DayBody(day: day)
                } else if let free = Present.freeDay(days: model.days, today: model.today) {
                    FreeDayView(free: free)
                }
                CatchUpView()
            }
        }
    }
}

/// День журнала, открытый из плана.
struct DayScreen: View {
    @EnvironmentObject private var model: AppModel
    let date: String

    var body: some View {
        ScreenScroll {
            if !model.sync.configured {
                WelcomeView()
            } else if model.sync.snapshot == nil {
                FirstLoadView()
            } else if let day = model.day(date) {
                AlertsView()
                if date != model.today {
                    OtherDayBanner(day: day)
                }
                DayBody(day: day)
            } else {
                EmptyState(
                    title: "В этот день тренировки нет",
                    text: "В журнале нет строк за \(Days.formatLongDay(date))."
                ) {
                    Button("Открыть план") {
                        model.go(.plan)
                    }
                    .buttonStyle(.app(.soft))
                }
            }
        }
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        EmptyState(
            title: "Подключите таблицу",
            text: "Приложение записывает тренировки в вашу Google Таблицу и берёт из неё план. Данные хранятся только там."
        ) {
            StepsList(steps: [
                "Поставьте в таблицу скрипт по инструкции. Это делается один раз, с компьютера.",
                "Скопируйте адрес веб-приложения и ключ.",
                "Вставьте их в настройках этого приложения.",
            ])
            Button("Открыть настройки") {
                model.go(.settings)
            }
            .buttonStyle(.app(.primary, block: true))
            LinkButton(title: "Инструкция", address: Present.setupURL)
        }
    }
}

private struct FirstLoadView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.sync.phase == .syncing {
            EmptyState(text: "Читаю журнал из таблицы…")
        } else {
            EmptyState(
                title: "Журнал ещё не загружен",
                text: model.sync.error?.message ?? "Нужна связь с таблицей, чтобы прочитать план."
            ) {
                Button("Повторить") {
                    model.syncNow()
                }
                .buttonStyle(.app(.primary))
            }
        }
    }
}

/// Плашки о том, что требует внимания: запись не сохраняется, таблица не принимает данные.
struct AlertsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let state = model.sync
        if !state.outboxSaved || !model.persistent {
            BannerView(
                tone: .bad, lead: "Телефон не даёт сохранять данные. ",
                text: "Записи держатся только пока приложение открыто. Не закрывайте его, пока они не уйдут в таблицу."
            )
        }
        if state.phase == .error, let error = state.error {
            let parts = Present.errorText(code: error.code, message: error.message)
            BannerView(tone: .bad, lead: "\(parts.title). ", text: parts.text) {
                Button("Открыть настройки") {
                    model.go(.settings)
                }
                .buttonStyle(.app(.surface, small: true))
            }
        } else if state.phase == .waiting, let error = state.error, error.code == "not_json" {
            BannerView(tone: .warn, text: error.message)
        }
        if !state.failed.isEmpty {
            BannerView(tone: .bad, lead: "Не записано: \(state.failed.count). ", text: "Таблица не приняла эти записи.") {
                Button("Посмотреть") {
                    model.openSync()
                }
                .buttonStyle(.app(.surface, small: true))
            }
        }
        if let script = state.snapshot?.script, script < Bridge.expectedScript {
            BannerView(
                tone: .warn, lead: "Скрипт в таблице устарел. ",
                text: "Обновите его код по инструкции и выпустите новую версию развёртывания."
            ) {
                LinkButton(title: "Инструкция", address: Present.setupURL, kind: .surface, small: true, marked: false)
            }
        }
    }
}

/// День не сегодняшний: запись задним числом, план на будущее или тренировка, которую делают сегодня.
private struct OtherDayBanner: View {
    @EnvironmentObject private var model: AppModel
    let day: JournalDay

    var body: some View {
        let today = model.today
        let name = Days.formatSheetDay(day.date)
        if model.isLive(day.date) {
            let mark = Present.doneMark(today: today)
            let noted = day.rows.contains { $0.note.contains(mark) }
            BannerView(
                lead: "Тренировка за \(name) идёт сегодня. ",
                text: noted ? "В заметке отмечено: \(mark)." : ""
            )
        } else {
            BannerView(
                lead: day.date < today ? "Запись за \(name). " : "План на \(name). ",
                text: "Сегодня \(Days.formatSheetDay(today)). Если делаете эту тренировку сейчас, отметьте это: включится таймер отдыха, а в заметке появится дата."
            ) {
                Button("Делаю сегодня") {
                    model.markLive(day.date)
                }
                .buttonStyle(.app(.surface, small: true))
            }
        }
    }
}

/// На сегодня тренировки нет: день отдыха, программа не началась или уже закончилась.
private struct FreeDayView: View {
    let free: FreeDay

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EmptyState(title: free.title, text: free.text)
            if let next = free.next {
                DaysSection(title: "Следующая тренировка", days: [next])
            }
        }
    }
}

/// Прошлые дни без записи за две недели: их можно дозаписать.
private struct CatchUpView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let missed = Present.catchUp(days: model.days, today: model.today)
        if !missed.isEmpty {
            DaysSection(title: "Не записано раньше", days: missed)
        }
    }
}
