import Foundation

/// Даты в приложении — строки вида «YYYY-MM-DD», как в ответе таблицы.
///
/// Арифметика идёт по номеру дня от 1 января 1970 года по григорианскому календарю,
/// без часовых поясов: переход на летнее время и пояс телефона не сдвигают календарь.
/// Названия дней и месяцев записаны здесь же, чтобы подписи не зависели от языка телефона.
public enum Days {
    // MARK: Номер дня

    /// Номер дня от 1 января 1970 года.
    public static func ordinal(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let monthFromMarch = (month + 9) % 12
        let dayOfYear = (153 * monthFromMarch + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// Год, месяц и число по номеру дня.
    public static func civil(_ ordinal: Int) -> (year: Int, month: Int, day: Int) {
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthFromMarch = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthFromMarch + 2) / 5 + 1
        let month = monthFromMarch < 10 ? monthFromMarch + 3 : monthFromMarch - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }

    /// Номер дня для строки «YYYY-MM-DD» или nil, если это не дата.
    public static func parse(_ iso: String) -> Int? {
        let bytes = Array(iso.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45 else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let byte = bytes[index]
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10) else { return nil }
        guard month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }
        let value = ordinal(year: year, month: month, day: day)
        // 30 февраля даёт другой день при обратном переводе: такой даты нет
        let back = civil(value)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return value
    }

    /// Строка «YYYY-MM-DD» по номеру дня.
    public static func iso(_ ordinal: Int) -> String {
        let date = civil(ordinal)
        return "\(pad(date.year, 4))-\(pad(date.month, 2))-\(pad(date.day, 2))"
    }

    public static func isISODate(_ value: String) -> Bool {
        parse(value) != nil
    }

    public static func addDays(_ iso: String, _ count: Int) -> String {
        guard let value = parse(iso) else { return iso }
        return self.iso(value + count)
    }

    /// На сколько дней дата `a` позже даты `b`.
    public static func diffDays(_ a: String, _ b: String) -> Int {
        guard let first = parse(a), let second = parse(b) else { return 0 }
        return first - second
    }

    /// Сегодняшняя дата по часам устройства.
    public static func today(_ now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return "\(pad(parts.year ?? 1970, 4))-\(pad(parts.month ?? 1, 2))-\(pad(parts.day ?? 1, 2))"
    }

    /// День недели: 1 — понедельник, 7 — воскресенье.
    public static func isoWeekday(_ iso: String) -> Int {
        guard let value = parse(iso) else { return 1 }
        // 1 января 1970 года — четверг
        return (((value % 7) + 7) % 7 + 3) % 7 + 1
    }

    public static func mondayOf(_ iso: String) -> String {
        addDays(iso, 1 - isoWeekday(iso))
    }

    // MARK: Подписи

    static let weekdayShort = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
    static let weekdayLong = ["понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"]
    static let monthGenitive = [
        "января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря",
    ]
    static let monthShort = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]

    static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return text.count >= width ? text : String(repeating: "0", count: width - text.count) + text
    }

    private static func parts(_ iso: String) -> (year: Int, month: Int, day: Int)? {
        guard let value = parse(iso) else { return nil }
        return civil(value)
    }

    /// «ср 11.11» — как в таблице.
    public static func formatSheetDay(_ iso: String) -> String {
        guard let date = parts(iso) else { return iso }
        return "\(weekdayShort[isoWeekday(iso) - 1]) \(pad(date.day, 2)).\(pad(date.month, 2))"
    }

    /// «среда» — день недели полностью.
    public static func weekdayName(_ iso: String) -> String {
        weekdayLong[isoWeekday(iso) - 1]
    }

    /// «11 ноября»
    public static func formatDayMonth(_ iso: String) -> String {
        guard let date = parts(iso) else { return iso }
        return "\(date.day) \(monthGenitive[date.month - 1])"
    }

    /// «среда, 11 ноября»
    public static func formatLongDay(_ iso: String) -> String {
        guard parts(iso) != nil else { return iso }
        return "\(weekdayName(iso)), \(formatDayMonth(iso))"
    }

    /// «11 ноя»
    public static func formatShortDay(_ iso: String) -> String {
        guard let date = parts(iso) else { return iso }
        return "\(date.day) \(monthShort[date.month - 1])"
    }

    /// «11.11»
    public static func formatNumericDay(_ iso: String) -> String {
        guard let date = parts(iso) else { return iso }
        return "\(pad(date.day, 2)).\(pad(date.month, 2))"
    }

    /// «10–13 ноя» или «30 ноя – 4 дек»
    public static func formatRange(_ from: String, _ to: String) -> String {
        if from == to { return formatShortDay(from) }
        guard let a = parts(from), let b = parts(to) else { return "\(from) – \(to)" }
        if a.month == b.month, a.year == b.year {
            return "\(a.day)–\(formatShortDay(to))"
        }
        return "\(formatShortDay(from)) – \(formatShortDay(to))"
    }

    /// «12:31» для сегодняшнего времени, «9 ноября, 12:31» для более раннего.
    public static func formatMoment(_ moment: Date?, now: Date, timeZone: TimeZone = .current) -> String {
        guard let moment else { return "ещё ни разу" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: moment)
        let time = "\(pad(parts.hour ?? 0, 2)):\(pad(parts.minute ?? 0, 2))"
        if today(moment, timeZone: timeZone) == today(now, timeZone: timeZone) { return time }
        let month = monthGenitive[max(1, min(12, parts.month ?? 1)) - 1]
        return "\(parts.day ?? 1) \(month), \(time)"
    }
}
