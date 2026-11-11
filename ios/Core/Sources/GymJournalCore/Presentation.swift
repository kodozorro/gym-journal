import Foundation

// Тексты и небольшие решения экранов, общие для телефона и часов: что написать в метке
// синхронизации, под названием дня, в плашке об ошибке. Здесь нет ни цветов, ни разметки.

/// Тон метки синхронизации в шапке.
public enum PillTone: String, Sendable {
    case plain, busy, wait, bad
}

public struct PillInfo: Equatable, Sendable {
    public var tone: PillTone
    /// Имя значка: info, alert, sync, cloudUp, cloudOff, check.
    public var icon: String
    public var text: String
}

/// Ошибка, после которой нужен человек: заголовок и пояснение без повтора заголовка.
public struct ErrorText: Equatable, Sendable {
    public var title: String
    public var text: String
}

/// Что показать, когда на сегодня тренировки нет.
public struct FreeDay: Equatable, Sendable {
    public var title: String
    public var text: String
    public var next: JournalDay?
}

/// Числа для выбора повторов: границы ленты и число, с которого начать.
public struct RepsChoice: Equatable, Sendable {
    public var low: Int
    public var high: Int
    public var anchor: Int
}

public enum Present {
    public static let setupURL = "https://github.com/kodozorro/gym-journal/blob/main/docs/setup.md"
    public static let noteLimit = 500
    /// За сколько дней назад показывать незаписанные тренировки.
    public static let catchUpDays = 14
    public static let catchUpLimit = 6

    // MARK: Синхронизация

    public static func pill(_ state: SyncState) -> PillInfo {
        if !state.configured { return PillInfo(tone: .plain, icon: "info", text: "Не подключено") }
        if state.phase == .error { return PillInfo(tone: .bad, icon: "alert", text: "Нужна настройка") }
        if !state.failed.isEmpty { return PillInfo(tone: .bad, icon: "alert", text: "Не записано: \(state.failed.count)") }
        if state.phase == .syncing {
            return PillInfo(tone: .busy, icon: "sync", text: state.pending > 0 ? "Отправка…" : "Обновление…")
        }
        if state.pending > 0 {
            if state.online && state.phase == .idle { return PillInfo(tone: .busy, icon: "sync", text: "Отправка…") }
            return PillInfo(tone: .wait, icon: state.online ? "cloudUp" : "cloudOff", text: "В очереди: \(state.pending)")
        }
        if !state.online { return PillInfo(tone: .wait, icon: "cloudOff", text: "Нет сети") }
        if state.phase == .waiting { return PillInfo(tone: .wait, icon: "cloudOff", text: "Нет связи") }
        return PillInfo(tone: .plain, icon: "check", text: "Сохранено")
    }

    private static let errorTitles: [String: String] = [
        "unauthorized": "Ключ не подходит",
        "no_key": "В таблице не создан ключ",
        "layout_changed": "Лист «Журнал» изменился",
        "no_journal": "В таблице нет листа «Журнал»",
        "no_spreadsheet": "Скрипт не привязан к таблице",
        "api_mismatch": "Скрипт в таблице другой версии",
    ]

    // Где сообщение скрипта слишком короткое, приложение говорит, что делать.
    private static let errorHelp: [String: String] = [
        "unauthorized": "В приложении записан другой ключ. Вставьте ключ заново: его показывает функция setup в редакторе скрипта.",
        "no_journal": "Проверьте, что скрипт стоит в той самой таблице и лист не переименован.",
    ]

    private static let leadingMark = Rx(#"^[.:]\s*"#)

    public static func errorText(code: String, message: String) -> ErrorText {
        let title = errorTitles[code] ?? "Таблица не принимает записи"
        let full = errorHelp[code] ?? message
        guard full.hasPrefix(title) else { return ErrorText(title: title, text: full) }
        return ErrorText(title: title, text: leadingMark.replace(String(full.dropFirst(title.count)), with: ""))
    }

    /// Одной фразой: что сейчас с записями.
    public static func syncText(_ state: SyncState, now: Date) -> String {
        if !state.configured { return "Таблица не подключена." }
        if state.phase == .syncing { return "Идёт обмен с таблицей…" }
        if state.phase == .error {
            guard let error = state.error else { return "Таблица не принимает записи." }
            let parts = errorText(code: error.code, message: error.message)
            return "\(parts.title). \(parts.text)".trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if state.pending > 0 {
            if !state.online { return "Нет сети. Записи сохранены в телефоне и уйдут в таблицу, когда сеть появится." }
            if state.phase == .waiting {
                let wait = state.retryAt.map { Swift.max(1, Numbers.int($0.timeIntervalSince(now).rounded(.up))) } ?? 0
                let reason = state.error?.message ?? "Нет связи с таблицей."
                let tail = wait > 0 ? "Следующая попытка через \(wait) с." : ""
                return "\(reason) Записи сохранены в телефоне. \(tail)".trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return "Записи отправляются в таблицу."
        }
        if state.phase == .waiting { return state.error?.message ?? "Нет связи с таблицей." }
        if !state.online { return "Нет сети. Показан журнал, сохранённый в телефоне." }
        if !state.failed.isEmpty { return "Таблица не приняла записей: \(state.failed.count). Остальное сохранено." }
        return "Все записи в таблице."
    }

    /// Что было в записи, которую таблица не приняла.
    public static func describe(_ fields: RowFields) -> String {
        var parts: [String] = []
        if case .set(let value) = fields.weight {
            parts.append(value.map { "\(Numbers.format($0)) кг" } ?? "вес стёрт")
        }
        if let sets = fields.sets {
            let done = sets.compactMap { $0 }
            parts.append(done.isEmpty ? "подходы стёрты" : "подходы \(done.map { Numbers.plain($0) }.joined(separator: ", "))")
        }
        if case .set(let value) = fields.km {
            parts.append(value.map { "\(Numbers.format($0)) км" } ?? "км стёрты")
        }
        if case .set(let value) = fields.min {
            parts.append(value.map { "\(Numbers.format($0)) мин" } ?? "минуты стёрты")
        }
        if let note = fields.note {
            parts.append(note.isEmpty ? "заметка стёрта" : "заметка «\(note)»")
        }
        return parts.joined(separator: " · ")
    }

    /// Почему таблица не приняла запись.
    public static func failedReason(_ item: FailedItem) -> String {
        if !item.reason.isEmpty { return item.reason }
        return item.status == "not_found" ? "В журнале нет такой строки." : "Таблица отклонила запись."
    }

    private static let connectErrors: [String: String] = [
        "unauthorized": "Ключ не подошёл. Скопируйте его заново из журнала выполнения функции setup.",
        "network": "Нет связи со скриптом. Проверьте интернет и адрес.",
        "timeout": "Скрипт не ответил вовремя. Попробуйте ещё раз.",
    ]

    /// Текст ошибки под формой подключения.
    public static func connectError(code: String, message: String) -> String {
        connectErrors[code] ?? message
    }

    private static let execTail = Rx(#"/s/([^/]+)/exec$"#)
    private static let scheme = Rx(#"^https?://"#)

    /// Короткая запись адреса скрипта: «…TESTD…6789/exec».
    public static func shortURL(_ url: String) -> String {
        guard let id = execTail.match(url)?[1] else { return scheme.replace(url, with: "") }
        return id.count > 12 ? "…\(id.prefix(5))…\(id.suffix(4))/exec" : "…\(id)/exec"
    }

    // MARK: День

    public static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// Отметка в заметке о том, что тренировку другого дня сделали сегодня: «сделано 25.11».
    public static func doneMark(today: String) -> String {
        "сделано \(Days.formatNumericDay(today))"
    }

    /// Что написать под названием дня: сделанное, а если записей нет — план.
    public static func daySummary(_ rows: [JournalRow]) -> String {
        let progress = Journal.dayProgress(rows)
        let strength = rows.filter { !$0.isWalk }
        let walks = rows.filter { $0.isWalk }
        let walked = walks.map { $0.summary }.filter { !$0.isEmpty }.joined(separator: "; ")
        if strength.isEmpty {
            if progress.touched > 0 { return walked }
            return walks.map { $0.plan }.filter { !$0.isEmpty }.joined(separator: "; ")
        }
        let written = "записано \(progress.done) из \(progress.total)"
        if progress.touched > 0 && progress.done < progress.total { return written }
        if progress.touched > 0 { return walked.isEmpty ? written : walked }
        var parts = ["\(strength.count) \(Numbers.plural(strength.count, "упражнение", "упражнения", "упражнений"))"]
        let km = walks.reduce(0.0) { $0 + ($1.plannedKm ?? 0) }
        if km != 0 { parts.append("\(Numbers.format(km)) км") }
        return parts.joined(separator: " · ")
    }

    /// Строка под названием тренажёра в открытой карточке: тренажёр и уточнение плана.
    public static func meta(_ row: JournalRow) -> String {
        let plan = row.strengthPlan
        return [row.machine, plan.unknown ? row.plan : plan.tail].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// «3 × 10–12» или текст плана, если он не разобран.
    public static func planChip(_ row: JournalRow) -> String {
        let plan = row.strengthPlan
        return plan.unknown ? row.plan : "\(plan.sets) × \(plan.rangeText)"
    }

    /// Что написано в свёрнутой карточке: сделанное, а если записей нет — план и прошлый вес.
    public static func closedText(_ row: JournalRow, last: JournalRow?) -> String {
        if row.hasData { return row.summary }
        let before = last?.weight.map { "прошлый раз \(Numbers.format($0)) кг" } ?? ""
        return [planChip(row), before].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Пара, с которой работают: та, где записывали последней, а если она готова — первая незаконченная.
    public static func activePair(focus: Int?, pairs: [[JournalRow]]) -> Int? {
        if let focus, pairs.indices.contains(focus), pairs[focus].contains(where: { !$0.isDone }) { return focus }
        return pairs.firstIndex { pair in pair.contains { !$0.isDone } }
    }

    /// Лента повторов: от плана минус пять до плана плюс пять; посередине — записанное число,
    /// иначе прошлое, если оно в диапазоне плана, иначе верх диапазона.
    public static func reps(plan: StrengthPlan, current: Double?, last: Double?) -> RepsChoice {
        guard !plan.unknown, let low = plan.low, let high = plan.high else {
            let anchor = current ?? last ?? 10
            return RepsChoice(low: 1, high: 30, anchor: Numbers.int(anchor))
        }
        var anchor = Double(high)
        if let current {
            anchor = current
        } else if let last, last >= Double(low), last <= Double(high) {
            anchor = last
        }
        return RepsChoice(low: Swift.max(1, low - 5), high: high + 5, anchor: Numbers.int(anchor))
    }

    /// Пора ли отдыхать после записи подхода: круг пары закончен, а день ещё нет.
    public static func restAfterSet(pairs: [[JournalRow]], pair: [JournalRow], key: String, index: Int) -> Bool {
        let allDone = pairs.allSatisfy { $0.allSatisfy { $0.isDone } }
        return !allDone && Journal.roundComplete(pair, key: key, setIndex: index)
    }

    // MARK: Списки дней

    public static func freeDay(days: [JournalDay], today: String) -> FreeDay? {
        guard let first = days.first, let last = days.last else { return nil }
        let next = days.first { $0.date > today }
        if today < first.date {
            return FreeDay(
                title: "Программа ещё не началась",
                text: "Первая тренировка: \(Days.formatLongDay(first.date)).", next: next
            )
        }
        if today > last.date {
            return FreeDay(
                title: "Программа закончилась",
                text: "Последняя тренировка была \(Days.formatLongDay(last.date)). Чтобы продолжить, добавьте недели в таблицу.",
                next: next
            )
        }
        return FreeDay(title: "Сегодня тренировки нет", text: "По плану день отдыха.", next: next)
    }

    /// Прошлые дни без записи за две недели: их можно дозаписать. Новые сверху.
    public static func catchUp(days: [JournalDay], today: String) -> [JournalDay] {
        let from = Days.addDays(today, -catchUpDays)
        let list = days.filter { day in
            guard day.date < today, day.date >= from else { return false }
            let status = Journal.dayStatus(day.rows, date: day.date, today: today)
            return status == .missed || status == .partial
        }
        return Array(list.reversed().prefix(catchUpLimit))
    }

    /// Когда следующая тренировка: «пт 27.11 · Силовая C и ходьба». Пустая строка, если её нет.
    public static func nextWorkout(days: [JournalDay], today: String) -> String {
        guard let next = days.first(where: { $0.date > today }) else { return "" }
        return "\(Days.formatSheetDay(next.date)) · \(Journal.workoutTitle(next.rows))"
    }

    /// Километры недели рядом с её заголовком: «8,5 из 17 км».
    public static func weekKm(walked: Double?, goal: Double?, started: Bool) -> String {
        let hasGoal = (goal ?? 0) != 0
        guard walked != nil || (started && hasGoal) else { return "" }
        let km = Numbers.format(walked ?? 0)
        if let goal, hasGoal { return "\(km) из \(Numbers.format(goal)) км" }
        return "\(km) км"
    }
}
