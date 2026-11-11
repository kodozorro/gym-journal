import Foundation
import SwiftUI
import UIKit
import GymJournalCore

/// Состояние приложения и все действия пользователя.
///
/// Журнал и очередь записей живут в SyncEngine, настройки — в AppSettings, всё сиюминутное
/// (открытые карточки, окно ввода, таймер отдыха) — в свойствах ниже. Поведение повторяет
/// веб-приложение (js/ui/app.js): те же правила, те же слова.
@MainActor
final class AppModel: ObservableObject {
    /// Через сколько секунд после конца отдыха панель таймера убирается сама.
    static let overtimeHide = 600
    /// Сигнал подаётся, только если конец отдыха застали вовремя, а не вернулись в приложение позже.
    static let signalWindow: TimeInterval = 3

    // MARK: Зависимости

    let engine: SyncEngine
    let storage: StateStorage
    let monitor: NetworkMonitor
    let feedback = Feedback()
    let notifier: RestNotifier?
    let health: HealthStore?
    let watch: PhoneWatchLink?
    /// Показ с учебными данными: без таблицы, «Здоровья» и часов.
    let demo: DemoMode?

    // MARK: Состояние

    @Published private(set) var sync: SyncState
    @Published private(set) var days: [JournalDay] = []
    /// Понедельник первой недели программы.
    @Published private(set) var start: String?
    @Published private(set) var settings: AppSettings
    @Published private(set) var today: String
    @Published private(set) var route: Route = .today
    /// Ручное раскрытие карточек: ключ строки → открыта или закрыта.
    @Published private(set) var open: [String: Bool] = [:]
    /// Выбранный подход по ключу строки.
    @Published private(set) var setIndex: [String: Int] = [:]
    /// Сколько ячеек подходов показать, если добавили кнопкой «+».
    @Published private(set) var slots: [String: Int] = [:]
    @Published var focus: Focus?
    @Published private(set) var live: LiveDay?
    @Published var sheet: SheetState?
    @Published private(set) var form = ConnectForm()
    @Published private(set) var toast: ToastState?
    @Published var timer: RestTimer?
    @Published var timerEnded = false
    @Published private(set) var timerFlash = false
    /// Карточка, которую нужно показать на экране после записи подхода.
    @Published var scrollTarget: String?
    /// Растёт, когда экран нужно прокрутить к началу.
    @Published private(set) var scrollTop = 0

    // «Здоровье» и часы
    @Published var workout: LiveWorkout?
    /// Тренировка, которую сейчас начинаем.
    @Published var workoutPending: WorkoutKind?
    @Published var workoutEnding = false
    /// Часы не ответили на просьбу закончить тренировку.
    @Published var workoutStale = false
    @Published var watchInstalled = false
    @Published var healthAccess: HealthAccess = .unknown

    var intent: WorkoutIntent?
    var watchMemory = WatchMemory()
    var lastWatchState: WatchState?
    var watchPushScheduled = false
    /// Тренировку попросили закончить с телефона: отрезок ходьбы спросит телефон.
    var stopRequested = false
    var pendingWalk: WorkoutSummary?

    private var sheetSeq = 0
    private var toastSeq = 0
    private var ticker: Timer?
    private var dayTimer: Timer?
    private var started = false

    // MARK: Запуск

    static func make() -> AppModel {
        AppModel(demo: DemoMode.fromLaunch())
    }

    init(demo: DemoMode?) {
        self.demo = demo
        let monitor = NetworkMonitor()
        self.monitor = monitor

        let storage: StateStorage
        let secrets: StateStorage
        let transport: BridgeTransport
        if let demo {
            storage = MemoryStorage()
            let memory = MemoryStorage()
            if demo.connected { memory.save(DemoData.connection, for: "conn") }
            secrets = memory
            if let bridge = demo.bridge {
                transport = bridge
            } else {
                transport = URLSessionTransport()
            }
            notifier = nil
            health = nil
            watch = nil
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            storage = FileStorage(directory: base.appendingPathComponent("GymJournal", isDirectory: true))
            secrets = KeychainStorage(service: "gym-journal.bridge")
            transport = URLSessionTransport()
            notifier = RestNotifier()
            health = HealthStore.isAvailable ? HealthStore() : nil
            watch = PhoneWatchLink()
        }
        self.storage = storage

        let engine = SyncEngine(storage: storage, secrets: secrets, transport: transport, isOnline: { monitor.online })
        self.engine = engine
        sync = engine.state
        settings = (storage.load(AppSettings.self, for: "settings") ?? AppSettings()).normalized()
        let day = demo?.today ?? Days.today()
        today = day

        if let saved = storage.load(LiveDay.self, for: "live"), Days.isISODate(saved.date), saved.on == day {
            live = saved
        }
        let moment = Date()
        if let saved = storage.load(RestTimer.self, for: "timer"), saved.isValid,
           moment.timeIntervalSince(saved.endsAt) < Double(AppModel.overtimeHide) {
            timer = saved
            // отдых кончился, пока приложение было закрыто: показываем это, но уже не сигналим
            timerEnded = saved.isOver(now: moment)
        }
        watchMemory = storage.load(WatchMemory.self, for: "watch") ?? WatchMemory()
        if let saved = storage.load(LiveWorkout.self, for: "workout") {
            // тренировку, которую телефон вёл сам и не закончил за шесть часов, уже не сохранить честно
            if saved.onWatch || moment.timeIntervalSince(saved.startedAt) < 6 * 3600 {
                workout = saved
            } else {
                storage.remove("workout")
            }
        }
        derive()
        engine.onChange = { [weak self] in self?.engineChanged() }
    }

    /// Запускает всё, что живёт вместе с приложением. Вызывается один раз, когда появился экран.
    func launch() {
        guard !started else { return }
        started = true
        monitor.onChange = { [weak self] in self?.networkChanged() }
        if demo == nil {
            monitor.start()
            Feedback.installSounds()
        }
        watch?.onPacket = { [weak self] packet in self?.receive(packet) }
        watch?.onStatus = { [weak self] in self?.watchStatusChanged() }
        watch?.activate()
        healthAccess = currentHealthAccess()
        if demo != nil { watchInstalled = true }
        runTicker()
        dayTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshToday() }
        }
        applyTheme()
        updateWakeLock()
        engine.wake(staleAfter: 0)
        if let demo { runScene(demo) }
    }

    func now() -> Date {
        Date()
    }

    /// Телефон даёт сохранять данные.
    var persistent: Bool {
        (storage as? FileStorage)?.persistent ?? true
    }

    // MARK: Производные данные

    private func derive() {
        days = Journal.groupDays(sync.journal)
        start = sync.snapshot?.start ?? days.first.map { Days.mondayOf($0.date) }
    }

    private func engineChanged() {
        sync = engine.state
        derive()
        updateWakeLock()
        scheduleWatchPush()
    }

    private func networkChanged() {
        engineChanged()
        if monitor.online { engine.wake() }
    }

    /// Тренировку этого дня делают сегодня: для неё работает автозапуск отдыха.
    func isLive(_ date: String) -> Bool {
        if date == today { return true }
        guard let live else { return false }
        return live.date == date && live.on == today
    }

    func day(_ date: String) -> JournalDay? {
        days.first { $0.date == date }
    }

    func row(_ key: String) -> JournalRow? {
        sync.journal.first { $0.key == key }
    }

    /// Сколько ячеек подходов показано: по плану и записям, плюс добавленная кнопкой «+».
    func slotsOf(_ row: JournalRow) -> Int {
        min(Plans.maxSets, max(row.slotCount, slots[row.key] ?? 0))
    }

    /// Подход, в который попадёт следующее число: выбранный касанием или первый пустой. -1 — все записаны.
    func selectedSet(_ row: JournalRow) -> Int {
        if let chosen = setIndex[row.key], chosen >= 0, chosen < slotsOf(row) { return chosen }
        return row.nextSetIndex
    }

    /// Пара, с которой работают в этом дне.
    func activePair(date: String, pairs: [[JournalRow]]) -> Int? {
        Present.activePair(focus: focus?.date == date ? focus?.pair : nil, pairs: pairs)
    }

    // MARK: Переходы

    func go(_ next: Route) {
        var target = next
        if case .day(let date) = next, date == today { target = .today }
        if target == route {
            scrollTop += 1
            return
        }
        route = target
        open = [:]
        setIndex = [:]
        slots = [:]
        if target != .settings { form = ConnectForm() }
        if sheet != nil { closeSheet() }
        updateWakeLock()
    }

    func refreshToday() {
        let next = demo?.today ?? Days.today(now())
        guard next != today else { return }
        today = next
        if let current = live, current.on != next {
            live = nil
            storage.remove("live")
        }
        if case .day(let date) = route, date == next { route = .today }
        scheduleWatchPush()
    }

    /// Возврат в приложение: новый день, очередь записей, экран и таймер.
    func wake() {
        guard started else { return }
        refreshToday()
        engine.wake()
        tick()
        applyTheme()
        updateWakeLock()
        healthAccess = currentHealthAccess()
        watchStatusChanged()
        presentPendingWalk()
    }

    /// Разрешение на запись тренировок. В показе с учебными данными «Здоровья» нет, но выглядит всё как с ним.
    private func currentHealthAccess() -> HealthAccess {
        if let health { return health.access }
        return demo != nil ? .granted : .unavailable
    }

    // MARK: Тема и экран

    func applyTheme() {
        switch settings.theme {
        case .auto: ThemeApplier.apply(.unspecified)
        case .light: ThemeApplier.apply(.light)
        case .dark: ThemeApplier.apply(.dark)
        }
    }

    func updateWakeLock() {
        let resting = timer != nil && !timerEnded
        let onWorkout = sync.configured && route.isWorkout
        switch settings.wakeLock {
        case .workout: feedback.keepAwake(onWorkout || resting)
        case .rest: feedback.keepAwake(resting)
        case .off: feedback.keepAwake(false)
        }
    }

    // MARK: Сообщения и листы

    func showToast(_ text: String) {
        toastSeq += 1
        let id = toastSeq
        toast = ToastState(id: id, text: text)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard let self, self.toast?.id == id else { return }
            self.toast = nil
        }
    }

    func openSheet(title: String, sub: String = "", top: Bool = false, _ content: SheetContent) {
        sheetSeq += 1
        sheet = SheetState(id: sheetSeq, title: title, sub: sub, top: top, content: content)
    }

    func closeSheet() {
        sheet = nil
        presentPendingWalk()
    }

    // MARK: Упражнения

    func toggleCard(_ row: JournalRow, pair: Int, open isOpen: Bool) {
        open[row.key] = isOpen
        if isOpen { focus = Focus(date: row.date, pair: pair) }
    }

    func selectSet(_ row: JournalRow, _ index: Int) {
        if selectedSet(row) == index {
            openReps(row.key, index)
            return
        }
        setIndex[row.key] = index
    }

    func addSet(_ row: JournalRow) {
        let count = slotsOf(row)
        guard count < Plans.maxSets else { return }
        slots[row.key] = count + 1
        setIndex[row.key] = count
    }

    /// Записывает число повторов в подход; nil стирает его.
    func recordSet(_ key: String, _ index: Int, _ reps: Double?) {
        feedback.prime()
        guard let row = engine.row(for: key), !row.isWalk, row.sets.indices.contains(index) else { return }
        var sets = row.sets
        let was = sets[index]
        setIndex[key] = nil
        guard was != reps else { return }
        sets[index] = reps
        var fields = RowFields(sets: sets)
        if row.weight == nil, reps != nil, let weight = Journal.lastTime(sync.journal, for: row)?.weight {
            // первый подход закрепляет вес, подставленный с прошлого раза
            fields.weight = .set(weight)
        }
        engine.queue(row, fields)
        if was == nil, reps != nil { afterNewSet(key, index) }
    }

    private func afterNewSet(_ key: String, _ index: Int) {
        let journal = sync.journal
        guard let row = journal.first(where: { $0.key == key }) else { return }
        let pairs = Journal.splitDay(journal.filter { $0.date == row.date }).pairs
        guard let pairIndex = pairs.firstIndex(where: { pair in pair.contains { $0.key == key } }) else { return }
        let pair = pairs[pairIndex]
        focus = Focus(date: row.date, pair: pairIndex)
        if row.isDone { open[key] = nil }
        if settings.autoTimer, isLive(row.date), Present.restAfterSet(pairs: pairs, pair: pair, key: key, index: index) {
            beginRest(Double(settings.restSec))
        }
        if let target = WatchLink.nextTarget(pairs: pairs, pair: pair, key: key, index: index), target != key {
            scrollTarget = target
        }
    }

    func stepWeight(_ key: String, _ direction: Int) {
        guard let row = engine.row(for: key) else { return }
        let base = row.weight ?? Journal.lastTime(sync.journal, for: row)?.weight ?? 0
        let next = max(0, Numbers.roundTo(base + Double(direction) * settings.step(for: row.exercise), 2))
        if row.weight != next { engine.queue(row, RowFields(weight: .set(next))) }
    }

    func setWeight(_ key: String, _ weight: Double?) {
        guard let row = engine.row(for: key), row.weight != weight else { return }
        engine.queue(row, RowFields(weight: .set(weight)))
    }

    func openWeight(_ key: String) {
        guard let row = engine.row(for: key) else { return }
        let value = row.weight ?? Journal.lastTime(sync.journal, for: row)?.weight
        let field = KeypadField(name: "weight", label: "Вес", unit: "кг", value: value, max: 1000, digits: 2, whole: 4)
        openSheet(
            title: row.exercise, sub: "Вес, как он выставлен на тренажёре",
            .keypad(KeypadState(
                target: .weight(key: key), fields: [field], canClear: row.weight != nil, stepsFor: row.exercise
            ))
        )
    }

    func openReps(_ key: String, _ index: Int) {
        guard let row = engine.row(for: key), row.sets.indices.contains(index) else { return }
        let value = row.sets[index]
        let field = KeypadField(
            name: "reps", label: "Подход \(index + 1)", unit: "повт.", value: value, integer: true, max: 500, whole: 3
        )
        openSheet(
            title: row.exercise, sub: "Повторы в подходе \(index + 1)",
            .keypad(KeypadState(target: .reps(key: key, index: index), fields: [field], canClear: value != nil))
        )
    }

    /// Окно ввода ходьбы. Отрезок после тренировки приходит уже с минутами и километрами.
    func openWalk(_ key: String, _ focus: WalkFocus, km: Double? = nil, minutes: Double? = nil, sub: String? = nil) {
        guard let row = engine.row(for: key) else { return }
        let add = focus == .add
        let done = row.summary
        var text = "Итог за тренировку"
        if add { text = done.isEmpty ? "Километры и минуты этого отрезка" : "Прибавится к записанному: \(done)" }
        let fields = [
            KeypadField(name: "km", label: "Километры", unit: "км", value: add ? km : row.km, max: 200, digits: 2, whole: 3),
            KeypadField(name: "min", label: "Минуты", unit: "мин", value: add ? minutes : row.min, max: 1440, digits: 1, whole: 4),
        ]
        openSheet(
            title: add ? "Отрезок ходьбы" : row.exercise, sub: sub ?? text,
            .keypad(KeypadState(
                target: .walk(key: key, add: add), fields: fields, active: focus == .min ? 1 : 0,
                canClear: !add && (row.km != nil || row.min != nil)
            ))
        )
    }

    private func writeWalk(_ key: String, km: Double?, min: Double?, add: Bool) {
        guard let row = engine.row(for: key) else { return }
        var fields = RowFields()
        if add {
            if let km, km > 0 { fields.km = .set(Numbers.roundTo((row.km ?? 0) + km, 2)) }
            if let min, min > 0 { fields.min = .set(Numbers.roundTo((row.min ?? 0) + min, 1)) }
        } else {
            if km != row.km { fields.km = .set(km) }
            if min != row.min { fields.min = .set(min) }
        }
        if !fields.isEmpty { engine.queue(row, fields) }
    }

    // MARK: Заметка

    /// Заметка не длиннее, чем принимает таблица. Длина считается так же, как в скрипте.
    static func clipped(_ text: String) -> String {
        var out = text
        while out.utf16.count > Present.noteLimit { out.removeLast() }
        return out
    }

    func openNote(_ key: String) {
        guard let row = engine.row(for: key) else { return }
        let mark = Present.doneMark(today: today)
        let chips = row.date != today && !row.note.contains(mark) ? [mark] : []
        openSheet(
            title: "Заметка", sub: row.exercise, top: true,
            .note(NoteState(key: key, text: row.note, hadNote: !row.note.isEmpty, chips: chips))
        )
    }

    private func updateNote(_ change: (inout NoteState) -> Void) {
        guard var current = sheet, case .note(var note) = current.content else { return }
        change(&note)
        current.content = .note(note)
        sheet = current
    }

    func noteInput(_ text: String) {
        updateNote { $0.text = AppModel.clipped(text) }
    }

    func noteAppend(_ chip: String) {
        updateNote { note in
            let current = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
            note.text = AppModel.clipped(current.isEmpty ? chip : "\(current); \(chip)")
            note.chips.removeAll { $0 == chip }
        }
    }

    func noteSave(_ text: String) {
        guard let current = sheet, case .note(let note) = current.content else { return }
        let value = AppModel.clipped(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if let row = engine.row(for: note.key), row.note != value {
            engine.queue(row, RowFields(note: value))
        }
        closeSheet()
    }

    /// «Делаю эту тренировку сегодня»: включает таймер для этого дня и ставит дату в заметку.
    func markLive(_ date: String) {
        feedback.prime()
        let next = LiveDay(date: date, on: today)
        live = next
        storage.save(next, for: "live")
        let mark = Present.doneMark(today: today)
        let rows = sync.journal.filter { $0.date == date }
        if let first = rows.first, !rows.contains(where: { $0.note.contains(mark) }) {
            let note = first.note.isEmpty ? mark : "\(first.note); \(mark)"
            if note.utf16.count <= Present.noteLimit { engine.queue(first, RowFields(note: note)) }
        }
        scheduleWatchPush()
    }

    func dismissWeightNote() {
        update { $0.weightNoteSeen = true }
    }

    // MARK: Цифровая клавиатура

    private func updateKeypad(_ change: (inout KeypadState) -> Void) {
        guard var current = sheet, case .keypad(var keypad) = current.content else { return }
        change(&keypad)
        current.content = .keypad(keypad)
        sheet = current
    }

    func keypadKey(_ key: KeypadKey) {
        updateKeypad { keypad in
            guard keypad.fields.indices.contains(keypad.active) else { return }
            keypad.fields[keypad.active] = keypad.fields[keypad.active].pressing(key)
            keypad.error = ""
        }
    }

    func keypadField(_ index: Int) {
        updateKeypad { keypad in
            guard keypad.fields.indices.contains(index) else { return }
            keypad.active = index
            keypad.error = ""
        }
    }

    func keypadNext() {
        updateKeypad { keypad in
            guard keypad.fields.indices.contains(keypad.active) else { return }
            let error = keypad.fields[keypad.active].error
            if !error.isEmpty {
                keypad.error = error
                return
            }
            keypad.active = min(keypad.fields.count - 1, keypad.active + 1)
            keypad.error = ""
        }
    }

    func keypadDone() {
        guard let current = sheet, case .keypad(let keypad) = current.content else { return }
        for (index, field) in keypad.fields.enumerated() {
            let error = field.error
            if !error.isEmpty {
                updateKeypad {
                    $0.active = index
                    $0.error = error
                }
                return
            }
        }
        let values = keypad.fields.map { $0.value.number }
        switch keypad.target {
        case .weight(let key):
            setWeight(key, values.first ?? nil)
        case .reps(let key, let index):
            recordSet(key, index, values.first ?? nil)
        case .walk(let key, let add):
            writeWalk(key, km: values.first ?? nil, min: values.count > 1 ? values[1] : nil, add: add)
        }
        closeSheet()
    }

    func keypadClear() {
        guard let current = sheet, case .keypad(let keypad) = current.content else { return }
        switch keypad.target {
        case .weight(let key):
            setWeight(key, nil)
        case .reps(let key, let index):
            recordSet(key, index, nil)
        case .walk(let key, _):
            writeWalk(key, km: nil, min: nil, add: false)
        }
        closeSheet()
    }

    func setStep(_ exercise: String, _ step: Double) {
        update { $0.setStep(step, for: exercise) }
    }

    // MARK: Листы

    func openSync() {
        openSheet(title: "Синхронизация с таблицей", .sync)
    }

    /// Кнопка «i» в карточке: фото тренажёра, рисунок и техника упражнения.
    func openInfo(_ row: JournalRow) {
        openSheet(title: row.exercise, sub: row.machine, .info(exercise: row.exercise, machine: row.machine))
    }

    func confirmSheet() {
        guard let current = sheet, case .confirm(let confirm) = current.content else { return }
        closeSheet()
        switch confirm.action {
        case .reset:
            engine.reset()
            storage.remove("live")
            live = nil
            focus = nil
            stopRest()
            showToast("Таблица отключена")
        case .endWorkout:
            stopWorkout()
        case .dropWorkout:
            dropWorkout()
        }
    }

    // MARK: Отдых

    func startRest(_ seconds: Double? = nil) {
        feedback.prime()
        beginRest(seconds ?? Double(settings.restSec))
    }

    private func beginRest(_ seconds: Double) {
        timer = RestTimer.start(now: now(), seconds: seconds)
        timerEnded = false
        timerFlash = false
        restChanged(mine: true)
    }

    func extendRest(_ seconds: Double = 30) {
        guard let current = timer else { return }
        feedback.prime()
        timer = current.extended(now: now(), seconds: seconds)
        timerEnded = false
        timerFlash = false
        restChanged(mine: true)
    }

    func stopRest() {
        timer = nil
        timerEnded = false
        timerFlash = false
        restChanged(mine: true)
    }

    /// Отдых, который запустили, продлили или остановили на часах.
    func adoptRest(_ next: RestTimer?) {
        if let next, next.isValid {
            timer = next
        } else {
            timer = nil
        }
        timerEnded = false
        timerFlash = false
        restChanged(mine: false)
    }

    /// - Parameter mine: отдых изменили на телефоне; иначе уведомление о его конце — дело часов.
    private func restChanged(mine: Bool) {
        if let timer {
            storage.save(timer, for: "timer")
        } else {
            storage.remove("timer")
        }
        runTicker()
        if mine, let timer {
            notifier?.schedule(at: timer.endsAt, sound: settings.sound, vibrate: settings.vibrate)
        } else {
            notifier?.cancel()
        }
        updateWakeLock()
        scheduleWatchPush()
    }

    private func runTicker() {
        if timer != nil, ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
        if timer == nil, let current = ticker {
            current.invalidate()
            ticker = nil
        }
    }

    private func tick() {
        guard let current = timer else {
            runTicker()
            return
        }
        let moment = now()
        guard current.isOver(now: moment) else { return }
        if !timerEnded {
            timerEnded = true
            signalRestEnd(onTime: moment.timeIntervalSince(current.endsAt) < AppModel.signalWindow)
            updateWakeLock()
        } else if current.overtime(now: moment) > AppModel.overtimeHide {
            stopRest()
        }
    }

    private func signalRestEnd(onTime: Bool) {
        if onTime, UIApplication.shared.applicationState == .active {
            if settings.sound { feedback.beep() }
            if settings.vibrate { feedback.vibrate() }
        }
        timerFlash = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            self?.timerFlash = false
        }
    }

    // MARK: Синхронизация и подключение

    func syncNow() {
        engine.sync()
    }

    func retryFailed(_ index: Int) {
        engine.retryFailed(index)
    }

    func dropFailed(_ index: Int) {
        engine.dropFailed(index)
    }

    func formInput(_ field: FormField, _ value: String) {
        var next = form
        switch field {
        case .url: next.url = value
        case .key: next.key = value
        }
        next.error = ""
        // адрес и ключ вставили одним куском: раскладываем по полям
        let found = Bridge.extractConnection(value)
        if let url = found.url, let key = found.key {
            next.url = url
            next.key = key
        }
        if next != form { form = next }
    }

    func editConnection() {
        var next = ConnectForm()
        next.editing = true
        form = next
    }

    func cancelEdit() {
        form = ConnectForm()
    }

    func connect() {
        guard !form.busy else { return }
        let key = form.key.trimmingCharacters(in: .whitespacesAndNewlines)
        var error = ""
        var address = ""
        switch Bridge.normalizeURL(form.url) {
        case .url(let value): address = value
        case .error(let message): error = message
        }
        if error.isEmpty {
            if key.isEmpty {
                error = "Вставьте ключ."
            } else if key.contains(where: { $0.isWhitespace }) || key.count > 200 {
                error = "Ключ — одна строка без пробелов."
            }
        }
        if !error.isEmpty {
            form.error = error
            return
        }
        form.busy = true
        form.error = ""
        Task {
            let result = await engine.connect(Connection(url: address, key: key))
            if result.ok {
                form = ConnectForm()
                showToast("Таблица подключена")
                go(.today)
            } else {
                form.busy = false
                form.error = Present.connectError(code: result.code, message: result.message)
            }
        }
    }

    func askReset() {
        let pending = sync.pending
        let lead = pending > 0 ? "В очереди неотправленных записей: \(pending). Они пропадут. " : ""
        openSheet(
            title: "Отключить таблицу?",
            .confirm(ConfirmState(
                text: "\(lead)Приложение забудет адрес, ключ и журнал на этом телефоне. В таблице ничего не изменится.",
                confirmLabel: "Отключить", danger: true, action: .reset
            ))
        )
    }

    // MARK: Настройки

    func update(_ change: (inout AppSettings) -> Void) {
        var next = settings
        change(&next)
        next = next.normalized()
        guard next != settings else { return }
        let themeChanged = next.theme != settings.theme
        settings = next
        storage.save(next, for: "settings")
        if themeChanged { applyTheme() }
        updateWakeLock()
        scheduleWatchPush()
    }

    // MARK: Показ с учебными данными

    private func runScene(_ demo: DemoMode) {
        Task {
            if sync.configured { _ = await engine.sync().value }
            let rows = sync.journal.filter { $0.date == today }
            let strength = rows.filter { !$0.isWalk }
            switch demo.scene {
            case "round":
                if strength.count >= 2 {
                    recordSet(strength[0].key, 0, 12)
                    recordSet(strength[1].key, 0, 12)
                }
            case "weight":
                if strength.count >= 2 {
                    recordSet(strength[0].key, 0, 12)
                    recordSet(strength[1].key, 0, 12)
                    stepWeight(strength[1].key, 1)
                    openWeight(strength[1].key)
                }
            case "note":
                if let row = strength.first { openNote(row.key) }
            case "info":
                if let row = strength.dropFirst(2).first ?? strength.first { openInfo(row) }
            case "walk":
                if let row = rows.first(where: { $0.isWalk }) { openWalk(row.key, .add) }
            case "offline":
                demo.bridge?.setMode(.down)
                monitor.forcedOffline = true
                if let row = strength.first { recordSet(row.key, 0, 12) }
            case "day":
                if let missed = Present.catchUp(days: days, today: today).first { go(.day(missed.date)) }
            case "workout":
                if strength.count >= 2 {
                    recordSet(strength[0].key, 0, 12)
                    recordSet(strength[1].key, 0, 12)
                }
                workout = LiveWorkout(
                    id: "demo", kind: .strength, startedAt: now().addingTimeInterval(-754), date: today, onWatch: true
                )
            case "sync":
                openSync()
            case "plan":
                go(.plan)
            case "progress":
                go(.progress)
            case "settings", "connect":
                go(.settings)
            default:
                break
            }
        }
    }
}
