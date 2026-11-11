import SwiftUI
import GymJournalCore

// Экран «Настройки»: подключение таблицы, поведение тренировки, «Здоровье» и часы, оформление, сброс.

struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScreenScroll {
            ConnectionSection()
            if !model.sync.failed.isEmpty {
                SettingsCard("Не записано") {
                    SectionText("Таблица не приняла эти записи. Исправьте причину и повторите или уберите запись.")
                    FailedList()
                }
            }
            WorkoutSection()
            HealthSection()
            SettingsCard("Оформление") {
                SegmentedView(
                    label: "Тема",
                    options: [
                        SegmentOption(ThemeMode.auto, "Авто"),
                        SegmentOption(ThemeMode.light, "Светлая"),
                        SegmentOption(ThemeMode.dark, "Тёмная"),
                    ],
                    selection: model.settings.theme
                ) { theme in
                    model.update { $0.theme = theme }
                }
            }
            SettingsCard("Приложение") {
                KeyValues(rows: [(name: "Версия", value: SettingsScreen.version)])
                SectionText("Вес записывается так, как он выставлен на тренажёре: число на плитке стека или сумма дисков.")
            }
            if model.sync.configured {
                SettingsCard("Сброс") {
                    SectionText("Приложение забудет адрес, ключ и сохранённый журнал на этом телефоне. Таблица не изменится.")
                    Button("Отключить таблицу") {
                        model.askReset()
                    }
                    .buttonStyle(.app(.plain, block: true))
                }
            }
            Text("Журнал тренировок. Данные хранятся в вашей Google Таблице.")
                .font(.app(13))
                .foregroundStyle(Palette.ink3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
    }

    /// «1.0 (3)»: версия и номер сборки.
    private static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        if short.isEmpty { return build }
        return build.isEmpty ? short : "\(short) (\(build))"
    }
}

// MARK: Кусочки

/// Раздел настроек: карточка с заголовком.
private struct SettingsCard<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.app(19, .bold))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .card()
    }
}

private struct SectionText: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.app(15))
            .foregroundStyle(Palette.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Строка настройки: название, пояснение и то, чем она меняется. Строки разделены тонкой линией.
private struct SettingRow<Control: View>: View {
    private let label: String
    private let hint: String
    private let first: Bool
    /// Переключатель стоит справа, выбор из нескольких — под названием.
    private let stacked: Bool
    private let control: Control

    init(
        _ label: String, hint: String = "", first: Bool = false, stacked: Bool = false,
        @ViewBuilder control: () -> Control
    ) {
        self.label = label
        self.hint = hint
        self.first = first
        self.stacked = stacked
        self.control = control()
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.app(16, .semibold))
                .foregroundStyle(Palette.ink)
            if !hint.isEmpty {
                Text(hint)
                    .font(.app(13))
                    .foregroundStyle(Palette.ink2)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 8) {
                    texts
                    control
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    texts
                    control
                }
            }
        }
        .padding(.top, first ? 0 : 8)
        .frame(minHeight: 52)
        .overlay(alignment: .top) {
            if !first {
                Rectangle().fill(Palette.line).frame(height: 1)
            }
        }
    }
}

/// Записи, которые таблица не приняла: что в них было, почему не приняты и что с ними сделать.
struct FailedList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.sync.failed.enumerated()), id: \.element.id) { index, failed in
                VStack(alignment: .leading, spacing: 8) {
                    Text(leadText(
                        "\(Days.formatSheetDay(failed.item.date)) · \(failed.item.exercise)",
                        ": \(Present.describe(failed.item.fields))"
                    ))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(Present.failedReason(failed))
                        .font(.app(14))
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Повторить") {
                            model.retryFailed(index)
                        }
                        .buttonStyle(.app(.plain, small: true))
                        Button("Убрать") {
                            model.dropFailed(index)
                        }
                        .buttonStyle(.app(.ghost, small: true))
                    }
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) {
                    Rectangle().fill(Palette.line).frame(height: 1)
                }
            }
        }
    }
}

// MARK: Таблица

private struct ConnectionSection: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focus: FormField?

    var body: some View {
        let state = model.sync
        if state.configured && !model.form.editing {
            connected(state)
        } else {
            form(configured: state.configured)
        }
    }

    private func connected(_ state: SyncState) -> some View {
        SettingsCard("Таблица") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                SectionText(Present.syncText(state, now: context.date))
            }
            KeyValues(rows: [
                (name: "Скрипт", value: Present.shortURL(state.connection?.url ?? "")),
                (name: "Журнал прочитан", value: Days.formatMoment(state.snapshot?.fetchedAt, now: model.now())),
                (name: "В очереди", value: String(state.pending)),
            ])
            HStack(spacing: 8) {
                Button {
                    model.syncNow()
                } label: {
                    HStack(spacing: 8) {
                        Icon("sync", size: 20)
                        Text("Обновить")
                    }
                }
                .buttonStyle(.app(.soft, block: true))
                .disabled(state.phase == .syncing)
                Button("Изменить") {
                    model.editConnection()
                }
                .buttonStyle(.app(.plain, block: true))
            }
        }
    }

    private func input<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.app(14, .semibold))
                .foregroundStyle(Palette.ink2)
            field()
                .font(.system(size: 16, design: .monospaced))
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radiusSmall)
                        .strokeBorder(Palette.lineStrong, lineWidth: 1)
                )
        }
    }

    private func form(configured: Bool) -> some View {
        let form = model.form
        let url = Binding<String>(get: { model.form.url }, set: { model.formInput(.url, $0) })
        let key = Binding<String>(get: { model.form.key }, set: { model.formInput(.key, $0) })
        return SettingsCard(configured ? "Новое подключение" : "Подключение таблицы") {
            SectionText("Вставьте адрес веб-приложения и ключ из редактора скрипта. Можно вставить оба сразу в первое поле.")
            input("Адрес веб-приложения") {
                TextField(
                    "Адрес веб-приложения", text: url,
                    prompt: Text(verbatim: "https://script.google.com/\nmacros/s/…/exec"), axis: .vertical
                )
                .lineLimit(3, reservesSpace: true)
                .keyboardType(.URL)
                .focused($focus, equals: .url)
            }
            input("Ключ") {
                TextField("Ключ", text: key, prompt: Text("40 знаков из журнала setup"))
                    .submitLabel(.done)
                    .focused($focus, equals: .key)
                    .onSubmit {
                        focus = nil
                        model.connect()
                    }
            }
            if !form.error.isEmpty {
                Text(form.error)
                    .font(.app(14, .semibold))
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(form.busy ? "Проверяю…" : "Подключить") {
                focus = nil
                model.connect()
            }
            .buttonStyle(.app(.primary, block: true))
            .disabled(form.busy)
            if configured {
                Button("Отмена") {
                    focus = nil
                    model.cancelEdit()
                }
                .buttonStyle(.app(.ghost, block: true))
            }
            LinkButton(title: "Как поставить скрипт", address: Present.setupURL, block: true)
        }
    }
}

// MARK: Тренировка

private struct WorkoutSection: View {
    @EnvironmentObject private var model: AppModel

    private func stepperButton(_ icon: Icon, label: String, enabled: Bool, change: Int) -> some View {
        Button {
            model.update { $0.restSec += change }
        } label: {
            icon
                .foregroundStyle(Palette.ink)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.press)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    var body: some View {
        let settings = model.settings
        SettingsCard("Тренировка") {
            VStack(spacing: 0) {
                SettingRow("Время отдыха", hint: "Между кругами пары", first: true) {
                    HStack(spacing: 0) {
                        stepperButton(
                            Icon("minus", size: 22), label: "Меньше отдыха",
                            enabled: settings.restSec > AppSettings.restMin, change: -AppSettings.restStep
                        )
                        Text(RestTimer.clock(settings.restSec))
                            .font(.app(17, .bold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                            .frame(minWidth: 72)
                        stepperButton(
                            Icon("plus", size: 22), label: "Больше отдыха",
                            enabled: settings.restSec < AppSettings.restMax, change: AppSettings.restStep
                        )
                    }
                    .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Metrics.radiusSmall))
                }
                SettingRow("Автозапуск отдыха", hint: "Когда записан подход у обоих упражнений пары") {
                    SwitchView(label: "Автозапуск отдыха", isOn: settings.autoTimer) { isOn in
                        model.update { $0.autoTimer = isOn }
                    }
                }
                SettingRow("Звук в конце отдыха", hint: "В беззвучном режиме телефона не слышен") {
                    SwitchView(label: "Звук в конце отдыха", isOn: settings.sound) { isOn in
                        model.update { $0.sound = isOn }
                    }
                }
                SettingRow("Вибрация в конце отдыха") {
                    SwitchView(label: "Вибрация в конце отдыха", isOn: settings.vibrate) { isOn in
                        model.update { $0.vibrate = isOn }
                    }
                }
                SettingRow("Подсказка о прибавке веса", hint: "Когда в прошлый раз все подходы дошли до верхней границы") {
                    SwitchView(label: "Подсказка о прибавке веса", isOn: settings.hints) { isOn in
                        model.update { $0.hints = isOn }
                    }
                }
                SettingRow(
                    "Не гасить экран", hint: "Пока идёт отдых или всё время, пока открыта тренировка.", stacked: true
                ) {
                    SegmentedView(
                        label: "Не гасить экран",
                        options: [
                            SegmentOption(WakeLockMode.rest, "В отдых"),
                            SegmentOption(WakeLockMode.workout, "Всегда"),
                            SegmentOption(WakeLockMode.off, "Нет"),
                        ],
                        selection: settings.wakeLock
                    ) { mode in
                        model.update { $0.wakeLock = mode }
                    }
                }
                SettingRow(
                    "Шаг веса, кг",
                    hint: "Для кнопок «+» и «−». У каждого упражнения шаг можно поменять в окне ввода веса.",
                    stacked: true
                ) {
                    FlowLayout(spacing: 8) {
                        ForEach(AppSettings.stepChoices, id: \.self) { step in
                            ChipButton(title: Numbers.format(step), chosen: step == settings.defaultStep) {
                                model.update { $0.defaultStep = step }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: «Здоровье» и часы

private struct HealthSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let isOn = model.settings.health
        SettingsCard("Здоровье и часы") {
            SettingRow(
                "Записывать тренировки в «Здоровье»",
                hint: "Силовая и ходьба попадают в «Фитнес» и идут в кольца активности.", first: true
            ) {
                SwitchView(label: "Записывать тренировки в «Здоровье»", isOn: isOn) { next in
                    model.setHealth(next)
                }
            }
            if isOn {
                if model.healthAccess == .unavailable {
                    SectionText("На этом устройстве нет «Здоровья».")
                } else {
                    if model.healthAccess == .denied {
                        BannerView(
                            tone: .warn, lead: "Нет доступа к «Здоровью». ",
                            text: "Разрешите приложению записывать тренировки в настройках конфиденциальности «Здоровья»."
                        )
                    }
                    KeyValues(rows: [(
                        name: "Приложение на часах",
                        value: model.watchInstalled ? "установлено" : "не найдено"
                    )])
                    SectionText(model.watchInstalled
                        ? "Тренировку начинают кнопкой на экране дня. Часы включают её сами и считают пульс и калории."
                        : "Тренировку начинают кнопкой на экране дня. Без часов телефон записывает только её вид и время.")
                }
            }
        }
    }
}
