import Foundation
import SwiftUI
import WatchKit
import GymJournalCore

/// Экран, открытый поверх списка дня.
enum WatchRoute: Hashable {
    /// Упражнение по ключу строки.
    case exercise(String)
    /// Ходьба по ключу строки.
    case walk(String)
    /// Идущая тренировка: время, пульс и кнопка «Завершить».
    case workout
}

/// Окно «Отрезок ходьбы»: километры и минуты, которые прибавятся к записанному.
struct WalkPrompt: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var km: Double
    var minutes: Double
    /// Пояснение под заголовком.
    var note: String
    /// Тренировка, после которой часы сами предложили этот отрезок: она уже в «Здоровье».
    /// nil — отрезок записывают вручную, и ходьбу в «Здоровье» запишет телефон.
    var workout: String?
}

/// Окно выбора веса.
struct WeightPrompt: Identifiable, Equatable {
    var key: String
    var id: String { key }
}

/// Короткое сообщение поверх экрана.
struct WatchNotice: Identifiable, Equatable {
    let id: Int
    let text: String
}

/// Что часы помнят между запусками, кроме состояния дня и неотправленных действий.
struct WatchSaved: Codable {
    /// Идентификатор установки приложения на часах: после переустановки номера действий идут заново.
    var epoch = UUID().uuidString
    /// Номер последнего действия.
    var seq = 0
    /// Номер последней просьбы телефона, которую часы выполнили.
    var intentDone: Int64 = 0
    /// Конец отдыха, который запустили на часах: о нём напоминают сами часы.
    var ownRestEnds: Date?
}

/// Состояние приложения на часах и все действия пользователя.
///
/// В таблицу пишет только телефон. Он присылает часам состояние дня, а часы возвращают действия:
/// записанный подход, новый вес, отрезок ходьбы, отдых, начало и конец тренировки. Пока телефон
/// не подтвердил действие, часы показывают его поверх присланного состояния, поэтому записывать
/// можно и без связи: действия дойдут, когда телефон появится.
@MainActor
final class WatchModel: ObservableObject {
    /// Сигнал подаётся, только если конец отдыха застали вовремя, а не открыли часы позже.
    static let signalWindow: TimeInterval = 3

    // MARK: Зависимости

    let storage: StateStorage
    let link: WatchPhoneLink?
    let workouts: WorkoutManager?
    let feedback: WatchFeedback?
    /// Показ с учебными данными: без телефона и «Здоровья».
    let demo: WatchDemo?
    /// «Сегодня», заданное при запуске: телефон на симуляторе показывает учебный журнал.
    private let fixedToday: String?

    // MARK: Состояние

    /// Последнее состояние дня от телефона.
    @Published private(set) var state: WatchState
    /// Действия, которые телефон ещё не подтвердил.
    @Published private(set) var ops: [WatchOp]
    @Published private(set) var today: String
    @Published var path: [WatchRoute] = []
    /// Отдых, который идёт сейчас: его отсчёт закрывает экран.
    @Published private(set) var activeRest: RestTimer?
    /// Тренировка, которую ведут часы.
    @Published private(set) var workout: LiveWorkout?
    /// Тренировка, которую сейчас начинаем.
    @Published private(set) var workoutStarting: WorkoutKind?
    @Published private(set) var workoutEnding = false
    @Published private(set) var metrics = WorkoutMetrics()
    @Published var walkPrompt: WalkPrompt?
    @Published var weightPrompt: WeightPrompt?
    @Published private(set) var notice: WatchNotice?
    /// Телефон сейчас на связи.
    @Published private(set) var reachable = false

    private var saved: WatchSaved
    private var restTimer: Timer?
    private var retryTimer: Timer?
    private var dayTimer: Timer?
    /// На какой момент стоит уведомление о конце отдыха.
    private var notifiedEnd: Date?
    private var started = false
    /// Идёт поиск тренировки, которая шла до перезапуска приложения.
    private var recovering = false
    /// Тренировку заканчивают с часов: отрезок ходьбы спросят часы, а не телефон.
    private var endedHere = false
    private var noticeSeq = 0

    // MARK: Запуск

    static func make() -> WatchModel {
        WatchModel(demo: WatchDemo.fromLaunch())
    }

    init(demo: WatchDemo?) {
        self.demo = demo
        if let demo {
            storage = MemoryStorage()
            link = nil
            workouts = nil
            feedback = nil
            state = demo.state()
            ops = []
            fixedToday = demo.today
            today = demo.today
            saved = WatchSaved()
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let files = FileStorage(directory: base.appendingPathComponent("GymJournalWatch", isDirectory: true))
            storage = files
            link = WatchPhoneLink()
            workouts = WorkoutManager.isAvailable ? WorkoutManager() : nil
            feedback = WatchFeedback()
            state = files.load(WatchState.self, for: "state") ?? WatchState()
            ops = files.load([WatchOp].self, for: "ops") ?? []
            let fixed = WatchDemo.fixedToday()
            fixedToday = fixed
            today = fixed ?? Days.today()
            saved = files.load(WatchSaved.self, for: "memory") ?? WatchSaved()
            workout = files.load(LiveWorkout.self, for: "workout")
        }
    }

    /// Запускает всё, что живёт вместе с приложением. Вызывается один раз при запуске.
    func start() {
        guard !started else { return }
        started = true
        if demo == nil { storage.save(saved, for: "memory") }
        link?.onState = { [weak self] state in self?.receive(state) }
        link?.onStatus = { [weak self] in self?.statusChanged() }
        link?.activate()
        workouts?.onMetrics = { [weak self] metrics in self?.metricsChanged(metrics) }
        workouts?.onEnded = { [weak self] finish in self?.workoutFinished(finish) }
        dayTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshToday() }
        }
        restChanged()
        // тренировка шла, когда приложение закрылось: продолжаем её
        if workout != nil { recoverWorkout() }
        if let demo { runScene(demo) }
    }

    /// Приложение снова на экране.
    func wake() {
        refreshToday()
        restChanged()
        // даже без новых действий: телефон проснётся и пришлёт свежее состояние дня
        flush(queued: false)
    }

    private func refreshToday() {
        guard fixedToday == nil else { return }
        let day = Days.today()
        if day != today { today = day }
    }

    // MARK: Производные данные

    /// Состояние пришло не сегодня: строки в нём уже не те, записывать по ним нельзя.
    var stale: Bool {
        state.configured && state.today != today
    }

    /// Строки дня с действиями часов, которые телефон ещё не подтвердил.
    var rows: [JournalRow] {
        WatchLink.apply(ops, to: state.rows, last: state.last)
    }

    var split: DaySplit {
        Journal.splitDay(rows)
    }

    func row(_ key: String) -> JournalRow? {
        rows.first { $0.key == key }
    }

    /// Вес, с которым делают упражнение: записанный, а пока его нет — с прошлого раза.
    func weight(of row: JournalRow) -> Double? {
        row.weight ?? state.last[row.key]?.weight
    }

    func step(for key: String) -> Double {
        let step = state.steps[key] ?? 0
        return step > 0 ? step : 2.5
    }

    /// Отдых, который показывают часы: свой, пока телефон его не подтвердил, иначе присланный.
    var rest: RestTimer? {
        WatchLink.rest(pending: ops, state: state)
    }

    /// Какие тренировки предложить начать. Пусто — предлагать нечего.
    var workoutOffer: [WorkoutKind] {
        guard state.health, workouts != nil || demo != nil, workout == nil, state.workout == nil, !stale else { return [] }
        return WatchLink.offer(for: rows)
    }

    // MARK: Обмен с телефоном

    /// Состояние дня от телефона. Более старое, чем уже есть, не принимается.
    func receive(_ next: WatchState) {
        guard demo == nil, next.stamp > state.stamp else { return }
        state = next
        ops = WatchLink.pending(ops, state: next, epoch: saved.epoch)
        storage.save(next, for: "state")
        storage.save(ops, for: "ops")
        refreshToday()
        handleIntent()
        reconcileWorkout()
        restChanged()
        prunePath()
        scheduleRetry()
    }

    private func statusChanged() {
        let now = link?.isReachable ?? false
        if now != reachable { reachable = now }
        if now { flush(queued: false) }
    }

    /// Записывает действие и отправляет его телефону.
    private func add(_ action: WatchAction) {
        saved.seq += 1
        ops.append(WatchOp(seq: saved.seq, at: Date(), action: action))
        if demo == nil {
            storage.save(saved, for: "memory")
            storage.save(ops, for: "ops")
        }
        flush(queued: true)
    }

    /// Отправляет телефону все неподтверждённые действия.
    /// - Parameter queued: новые действия: если телефон не на связи, их доставит система.
    private func flush(queued: Bool) {
        guard let link else { return }
        link.send(WatchPacket(epoch: saved.epoch, ops: ops, intentDone: saved.intentDone), queued: queued)
        scheduleRetry()
    }

    /// Пока есть неподтверждённые действия, часы время от времени повторяют отправку.
    private func scheduleRetry() {
        if ops.isEmpty || link == nil {
            retryTimer?.invalidate()
            retryTimer = nil
            return
        }
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.retry() }
        }
    }

    private func retry() {
        if ops.isEmpty {
            scheduleRetry()
        } else if link?.isReachable == true {
            flush(queued: false)
        }
    }

    /// Убирает из пути экраны строк, которых в новом состоянии нет.
    private func prunePath() {
        let keys = Set(state.rows.map { $0.key })
        let kept = path.filter { route in
            switch route {
            case .exercise(let key), .walk(let key): return keys.contains(key)
            case .workout: return workout != nil
            }
        }
        if kept != path { path = kept }
    }

    // MARK: Сообщения

    func show(_ text: String) {
        noticeSeq += 1
        let mine = noticeSeq
        notice = WatchNotice(id: mine, text: text)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard let self, self.notice?.id == mine else { return }
            self.notice = nil
        }
    }

    func dismissNotice() {
        notice = nil
    }

    // MARK: Упражнения

    /// Записывает число повторов в подход; nil стирает его.
    func recordSet(_ key: String, _ index: Int, _ reps: Double?) {
        guard !stale, let row = row(key), !row.isWalk, row.sets.indices.contains(index) else { return }
        let was = row.sets[index]
        guard was != reps else { return }
        add(.reps(key: key, index: index, value: reps))
        feedback?.play(.success)
        if was == nil, reps != nil { afterNewSet(key, index) }
    }

    /// После нового подхода: отдых, если круг пары закончен, и переход к следующему упражнению.
    private func afterNewSet(_ key: String, _ index: Int) {
        let pairs = split.pairs
        guard let pair = pairs.first(where: { pair in pair.contains { $0.key == key } }) else { return }
        if state.autoTimer, Present.restAfterSet(pairs: pairs, pair: pair, key: key, index: index) {
            startRest()
        }
        if let target = WatchLink.nextTarget(pairs: pairs, pair: pair, key: key, index: index) {
            if target != key { path = [.exercise(target)] }
        } else {
            // силовые записаны все: назад к списку дня
            path = []
        }
    }

    /// Куда перейти с экрана упражнения, в котором всё записано: ключ следующего или nil.
    func nextExercise(after key: String) -> String? {
        let pairs = split.pairs
        guard let pair = pairs.first(where: { pair in pair.contains { $0.key == key } }) else { return nil }
        if let partner = pair.first(where: { $0.key != key && !$0.isDone }) { return partner.key }
        for other in pairs {
            if let row = other.first(where: { !$0.isDone }) { return row.key }
        }
        return nil
    }

    func open(_ key: String?) {
        if let key {
            path = [.exercise(key)]
        } else {
            path = []
        }
    }

    func stepWeight(_ key: String, _ direction: Int) {
        guard !stale, let row = row(key), !row.isWalk else { return }
        let base = weight(of: row) ?? 0
        let next = max(0, Numbers.roundTo(base + Double(direction) * step(for: key), 2))
        guard row.weight != next else { return }
        add(.weight(key: key, value: next))
        feedback?.play(.click)
    }

    func setWeight(_ key: String, _ value: Double) {
        guard !stale, let row = row(key), !row.isWalk else { return }
        let next = max(0, Numbers.roundTo(value, 2))
        guard row.weight != next else { return }
        add(.weight(key: key, value: next))
        feedback?.play(.click)
    }

    /// Прибавляет отрезок ходьбы к уже записанному.
    /// - Parameter workout: тренировка, после которой часы сами предложили этот отрезок. Отрезок,
    ///   записанный вручную (nil), телефон запишет ещё и в «Здоровье» как ходьбу.
    func addWalk(_ key: String, km: Double, minutes: Double, workout: String? = nil) {
        guard !stale, let row = row(key), row.isWalk, km > 0 || minutes > 0 else { return }
        add(.walkAdd(
            key: key,
            km: km > 0 ? Numbers.roundTo(km, 2) : nil,
            min: minutes > 0 ? Numbers.roundTo(minutes, 1) : nil,
            workout: workout
        ))
        feedback?.play(.success)
    }

    /// Открывает окно «Отрезок ходьбы». Километры и минуты можно подставить заранее.
    /// - Parameter workout: сохранённая тренировка, после которой предложен отрезок.
    func askWalk(
        _ key: String, km: Double? = nil, minutes: Double? = nil, note: String? = nil, workout: String? = nil
    ) {
        guard let row = row(key), row.isWalk else { return }
        let done = row.summary
        let text = note ?? (done.isEmpty ? "Километры и минуты этого отрезка" : "Прибавится к записанному: \(done)")
        walkPrompt = WalkPrompt(
            key: key,
            km: max(0, Numbers.roundTo(km ?? 0, 2)),
            minutes: max(0, Numbers.roundHalfUp(minutes ?? 0)),
            note: text,
            workout: workout
        )
    }

    // MARK: Отдых

    func startRest() {
        setRest(RestTimer.start(now: Date(), seconds: Double(state.restSec)))
    }

    func extendRest(_ seconds: Double = 30) {
        guard let current = rest else { return }
        setRest(current.extended(now: Date(), seconds: seconds))
    }

    func stopRest() {
        guard rest != nil else { return }
        setRest(nil)
    }

    private func setRest(_ timer: RestTimer?) {
        saved.ownRestEnds = timer?.endsAt
        add(.rest(timer))
        restChanged()
    }

    /// Отдых изменился: чей бы он ни был, часы показывают отсчёт и ждут его конца.
    private func restChanged() {
        restTimer?.invalidate()
        restTimer = nil
        let now = Date()
        guard let current = rest, current.isValid, !current.isOver(now: now) else {
            if activeRest != nil { activeRest = nil }
            setReminder(nil)
            return
        }
        if activeRest != current { activeRest = current }
        let wait = max(0.05, current.endsAt.timeIntervalSince(now))
        restTimer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.restEnded(current) }
        }
        // С опущенной рукой и без тренировки приложение спит: о конце отдыха, который запустили
        // на часах, напомнит уведомление. Пока идёт тренировка, часы вибрируют сами.
        var mine = false
        if let own = saved.ownRestEnds { mine = abs(own.timeIntervalSince(current.endsAt)) < 0.5 }
        setReminder(state.signal && mine && workout == nil ? current.endsAt : nil)
    }

    private func setReminder(_ date: Date?) {
        guard date != notifiedEnd else { return }
        notifiedEnd = date
        if let date {
            feedback?.scheduleRestEnd(at: date)
        } else {
            feedback?.cancelRestEnd()
        }
    }

    private func restEnded(_ ended: RestTimer) {
        guard activeRest == ended else { return }
        activeRest = nil
        restTimer = nil
        let late = Date().timeIntervalSince(ended.endsAt)
        if state.signal, late < WatchModel.signalWindow { feedback?.play(.notification) }
    }

    // MARK: Тренировка

    /// Начинает тренировку в «Здоровье».
    /// - Parameters:
    ///   - indoor: ходьба по дорожке; nil — решить по тренажёру из таблицы.
    ///   - date: день журнала; nil — тот, что показан на часах.
    func startWorkout(_ kind: WorkoutKind, indoor: Bool? = nil, date: String? = nil) {
        guard workout == nil, workoutStarting == nil, !recovering else { return }
        let day = date ?? state.date ?? today
        let inside = indoor ?? (kind == .walk ? WatchLink.isIndoorWalk(rows) : true)
        guard let workouts else {
            // показ с учебными данными: тренировка только на экране
            if demo != nil {
                workout = LiveWorkout(id: "demo", kind: kind, startedAt: Date(), date: day, onWatch: true, indoor: inside)
            }
            return
        }
        workoutStarting = kind
        Task {
            let allowed = await workouts.requestAccess()
            guard allowed else {
                workoutStarting = nil
                show("Нет доступа к «Здоровью». Разрешите запись тренировок в его настройках на iPhone.")
                return
            }
            let began = await workouts.start(kind: kind, indoor: inside)
            workoutStarting = nil
            guard let began else {
                show("Тренировка не началась. Попробуйте ещё раз.")
                return
            }
            let live = LiveWorkout(
                id: UUID().uuidString, kind: kind, startedAt: began, date: day, onWatch: true, indoor: inside
            )
            workout = live
            metrics = WorkoutMetrics()
            storage.save(live, for: "workout")
            add(.workoutStarted(live))
            feedback?.play(.start)
            restChanged()
        }
    }

    /// Телефон открыл приложение на часах, чтобы начать тренировку.
    func workoutRequested(kind: WorkoutKind, indoor: Bool) {
        var date: String?
        if let intent = state.intent, intent.kind == kind { date = intent.date }
        startWorkout(kind, indoor: indoor, date: date)
    }

    /// Заканчивает тренировку. Итог придёт, когда она сохранится в «Здоровье».
    /// - Parameter byPhone: закончить попросил телефон: отрезок ходьбы спросит он.
    func endWorkout(byPhone: Bool = false) {
        guard workout != nil, !workoutEnding else { return }
        guard let workouts, workouts.isRunning else {
            // показ с учебными данными или тренировка, которой на часах уже нет
            workout = nil
            storage.remove("workout")
            prunePath()
            return
        }
        workoutEnding = true
        endedHere = !byPhone
        workouts.end()
    }

    private func metricsChanged(_ next: WorkoutMetrics) {
        guard workout != nil, next != metrics else { return }
        metrics = next
    }

    private func workoutFinished(_ finish: WorkoutFinish) {
        workoutEnding = false
        let here = endedHere
        endedHere = false
        guard let current = workout else { return }
        workout = nil
        storage.remove("workout")
        let summary = WorkoutSummary(
            id: current.id, kind: current.kind, date: current.date, startedAt: current.startedAt,
            endedAt: finish.endedAt, km: finish.km, kcal: finish.kcal, saved: finish.saved
        )
        add(.workoutEnded(summary))
        feedback?.play(finish.saved ? .stop : .failure)
        prunePath()
        restChanged()
        show(finish.saved ? "Тренировка сохранена в «Здоровье»" : "Тренировка не сохранилась в «Здоровье»")
        if here, summary.kind == .walk, summary.date == state.date { askWalkAfter(summary) }
    }

    /// После ходьбы спрашивает отрезок: минуты посчитаны, километры — по датчикам часов.
    private func askWalkAfter(_ summary: WorkoutSummary) {
        let walks = rows.filter { $0.isWalk }
        guard let row = walks.first(where: { !$0.isDone }) ?? walks.first else { return }
        let minutes = summary.minutes
        askWalk(
            row.key, km: summary.km, minutes: minutes,
            note: "Тренировка шла \(Numbers.format(minutes, digits: 0)) мин. Сверьте числа с дорожкой.",
            // тренировка не сохранилась: в «Здоровье» ходьбу запишет телефон по самому отрезку
            workout: summary.saved ? summary.id : nil
        )
    }

    /// Просьба телефона начать или закончить тренировку. Каждая выполняется один раз.
    private func handleIntent() {
        guard let intent = state.intent, intent.id > saved.intentDone else { return }
        if let kind = intent.kind {
            if intent.isFresh(now: Date()) { startWorkout(kind, indoor: intent.indoor, date: intent.date) }
        } else if workout != nil {
            endWorkout(byPhone: true)
        }
        saved.intentDone = intent.id
        storage.save(saved, for: "memory")
        flush(queued: true)
    }

    /// Телефон считает, что тренировку ведут часы, а на часах её нет: сообщаем, что она закончилась.
    private func reconcileWorkout() {
        guard let theirs = state.workout, theirs.onWatch, workout == nil, workoutStarting == nil,
              !workoutEnding, !recovering else { return }
        // сообщение о её конце уже в пути
        let reported = ops.contains { op in
            if case .workoutEnded(let summary) = op.action { return summary.id == theirs.id }
            return false
        }
        if reported { return }
        add(.workoutEnded(WorkoutSummary(
            id: theirs.id, kind: theirs.kind, date: theirs.date, startedAt: theirs.startedAt, endedAt: Date(),
            saved: false
        )))
    }

    /// Продолжает тренировку, которая шла, когда приложение закрылось.
    func recoverWorkout() {
        guard let workouts, !recovering, !workouts.isRunning else { return }
        recovering = true
        Task {
            let found = await workouts.recover()
            recovering = false
            if let found {
                if workout == nil {
                    let live = LiveWorkout(
                        id: UUID().uuidString, kind: found.kind, startedAt: found.startedAt,
                        date: state.date ?? today, onWatch: true, indoor: found.indoor
                    )
                    workout = live
                    storage.save(live, for: "workout")
                    add(.workoutStarted(live))
                }
            } else if let lost = workout {
                // тренировка не пережила перезапуск: в «Здоровье» её нет
                workout = nil
                storage.remove("workout")
                add(.workoutEnded(WorkoutSummary(
                    id: lost.id, kind: lost.kind, date: lost.date, startedAt: lost.startedAt, endedAt: Date(),
                    saved: false
                )))
                prunePath()
            }
            reconcileWorkout()
            restChanged()
        }
    }

    // MARK: Показ с учебными данными

    private func runScene(_ demo: WatchDemo) {
        let strength = rows.filter { !$0.isWalk }
        let walk = rows.first { $0.isWalk }
        switch demo.scene {
        case "exercise":
            if let row = strength.first { path = [.exercise(row.key)] }
        case "rest":
            if strength.count >= 2 {
                recordSet(strength[0].key, 0, 12)
                recordSet(strength[1].key, 0, 12)
            }
        case "sets":
            if strength.count >= 2 {
                recordSet(strength[0].key, 0, 12)
                recordSet(strength[1].key, 0, 11)
                stopRest()
            }
        case "list":
            if strength.count >= 2 {
                for index in 0..<strength[0].strengthPlan.sets { recordSet(strength[0].key, index, 12) }
                recordSet(strength[1].key, 0, 12)
                recordSet(strength[1].key, 1, 11)
                stopRest()
                path = []
            }
        case "weight":
            if let row = strength.first {
                path = [.exercise(row.key)]
                weightPrompt = WeightPrompt(key: row.key)
            }
        case "walk":
            if let walk { path = [.walk(walk.key)] }
        case "segment":
            if let walk {
                path = [.walk(walk.key)]
                askWalk(
                    walk.key, km: 1.52, minutes: 18, note: "Тренировка шла 18 мин. Сверьте числа с дорожкой.",
                    workout: "demo"
                )
            }
        case "workout", "live":
            workout = LiveWorkout(
                id: "demo", kind: .strength, startedAt: Date().addingTimeInterval(-754), date: today, onWatch: true
            )
            metrics = WorkoutMetrics(heartRate: 124, kcal: 86, km: nil)
            if demo.scene == "workout" { path = [.workout] }
        default:
            break
        }
    }
}
