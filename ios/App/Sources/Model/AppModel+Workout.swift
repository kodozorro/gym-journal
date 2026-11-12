import Foundation
import UIKit
import GymJournalCore

// Тренировка в «Здоровье» и обмен с часами.
//
// Тренировку начинают кнопкой на экране дня: силовую, если в дне есть тренажёры, и ходьбу, если
// есть ходьба. Телефон просит часы начать её; настоящую тренировку с пульсом ведут часы. Если
// часов рядом нет или они не ответили, телефон записывает в «Здоровье» вид тренировки и её время.
// Калории и пульс телефон не выдумывает.

/// Время на то, чтобы закончить обмен с таблицей, когда действие с часов пришло в свёрнутое приложение.
@MainActor
private final class BackgroundHold {
    private var id = UIBackgroundTaskIdentifier.invalid

    func begin() {
        id = UIApplication.shared.beginBackgroundTask(withName: "watch-sync") { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

extension AppModel {
    // MARK: Тренировка

    /// Какие тренировки предложить начать для дня. Пусто — предлагать нечего.
    func workoutOffer(for day: JournalDay) -> [WorkoutKind] {
        guard settings.health, health != nil || demo != nil, workout == nil, isLive(day.date) else { return [] }
        return WatchLink.offer(for: day.rows)
    }

    func startWorkout(_ kind: WorkoutKind, date: String) {
        guard workout == nil, workoutPending == nil else { return }
        feedback.prime()
        let rows = sync.journal.filter { $0.date == date }
        let indoor = kind == .walk ? WatchLink.isIndoorWalk(rows) : true
        guard let health else {
            // показ с учебными данными: тренировка только на экране
            if demo != nil {
                workout = LiveWorkout(
                    id: UUID().uuidString, kind: kind, startedAt: now(), date: date, onWatch: true, indoor: indoor
                )
            }
            return
        }
        workoutPending = kind
        Task {
            let allowed = await health.requestAccess()
            healthAccess = health.access
            guard allowed else {
                workoutPending = nil
                showToast("Нет доступа к «Здоровью». Разрешите запись тренировок в настройках телефона.")
                return
            }
            let startedAt = now()
            var asked = false
            if watch?.isInstalled == true {
                asked = true
                intent = WorkoutIntent(id: nextStamp(), kind: kind, date: date, indoor: indoor, at: startedAt)
                pushWatchState()
                let launched = await health.startWatchApp(kind: kind, indoor: indoor)
                if launched || watch?.isReachable == true {
                    // ждём до 15 секунд, пока часы сообщат, что тренировка началась
                    for _ in 0..<60 {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        if workout != nil || workoutPending != kind { return }
                    }
                }
            }
            guard workout == nil, workoutPending == kind else { return }
            // часов нет или они не ответили: тренировку ведёт телефон
            workoutPending = nil
            workout = LiveWorkout(
                id: UUID().uuidString, kind: kind, startedAt: startedAt, date: date, onWatch: false, indoor: indoor
            )
            rememberWorkout()
            scheduleWatchPush()
            if asked { showToast("Часы не ответили. Тренировку записывает телефон.") }
        }
    }

    /// Кнопка «Завершить»: сначала вопрос, чтобы тренировка не оборвалась от случайного касания.
    func askStopWorkout() {
        guard let current = workout else { return }
        if demo != nil, health == nil {
            workout = nil
            return
        }
        if workoutStale {
            openSheet(
                title: "Убрать тренировку?",
                .confirm(ConfirmState(
                    text: "Часы не отвечают. Если тренировка на них ещё идёт, завершите её на часах: она сохранится в «Здоровье». Здесь она просто исчезнет с экрана.",
                    confirmLabel: "Убрать", action: .dropWorkout
                ))
            )
            return
        }
        let minutes = max(0, Numbers.int(now().timeIntervalSince(current.startedAt) / 60))
        let place = current.onWatch ? "Её ведут часы. " : ""
        openSheet(
            title: "Завершить тренировку?",
            .confirm(ConfirmState(
                text: "\(current.kind.title) идёт \(minutes) мин. \(place)Она сохранится в «Здоровье».",
                confirmLabel: "Завершить", action: .endWorkout
            ))
        )
    }

    func stopWorkout() {
        guard let current = workout, !workoutEnding else { return }
        if current.onWatch {
            workoutEnding = true
            stopRequested = true
            intent = WorkoutIntent(id: nextStamp(), kind: nil, date: current.date, indoor: current.indoor, at: now())
            pushWatchState()
            Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard workoutEnding, workout?.id == current.id else { return }
                workoutEnding = false
                workoutStale = true
                showToast("Часы не ответили. Завершите тренировку на часах.")
            }
            return
        }
        workoutEnding = true
        Task {
            let end = now()
            let saved = await health?.saveWorkout(
                kind: current.kind, indoor: current.indoor, start: current.startedAt, end: end
            ) ?? false
            workoutEnding = false
            workout = nil
            rememberWorkout()
            scheduleWatchPush()
            finished(
                WorkoutSummary(
                    id: current.id, kind: current.kind, date: current.date, startedAt: current.startedAt,
                    endedAt: end, saved: saved
                ),
                askWalk: true
            )
        }
    }

    /// Убирает с экрана тренировку, о которой часы не отвечают. В «Здоровье» ничего не пишет.
    func dropWorkout() {
        workout = nil
        workoutEnding = false
        workoutStale = false
        stopRequested = false
        intent = nil
        rememberWorkout()
        scheduleWatchPush()
    }

    func rememberWorkout() {
        if let workout {
            storage.save(workout, for: "workout")
        } else {
            storage.remove("workout")
        }
    }

    private func finished(_ summary: WorkoutSummary, askWalk: Bool) {
        lastWorkout = summary
        showToast(summary.saved ? "Тренировка сохранена в «Здоровье»" : "Тренировка не сохранилась в «Здоровье»")
        if summary.kind == .walk, askWalk {
            pendingWalk = summary
            presentPendingWalk()
        }
    }

    /// После ходьбы спрашивает отрезок: минуты уже посчитаны, километры — если их мерили часы.
    func presentPendingWalk() {
        guard let summary = pendingWalk, sheet == nil, UIApplication.shared.applicationState == .active else { return }
        pendingWalk = nil
        let walks = sync.journal.filter { $0.date == summary.date && $0.isWalk }
        guard let row = walks.first(where: { !$0.isDone }) ?? walks.first else { return }
        let minutes = summary.minutes
        openWalk(
            row.key, .add,
            km: summary.km.map { Numbers.roundTo($0, 2) },
            minutes: minutes > 0 ? minutes : nil,
            sub: "Тренировка шла \(Numbers.format(minutes, digits: 0)) мин. Проверьте числа перед записью.",
            // тренировка не сохранилась: в «Здоровье» ходьбу запишет сам отрезок
            tracked: summary.saved
        )
    }

    // MARK: Ходьба отрезком

    /// Отрезок ходьбы, записанный вручную на телефоне или на часах, попадает в «Здоровье» как
    /// тренировка «Ходьба»: она кончается в момент записи и длится столько минут, сколько в
    /// отрезке, километры идут в неё расстоянием. Шаги, пульс и калории телефон не выдумывает.
    /// - Parameters:
    ///   - end: когда отрезок записали.
    ///   - fromWatch: отрезок записали на часах: подсказок о нём телефон не показывает.
    ///   - afterSheet: отрезок только что ввели в окне, и оно ещё закрывается.
    func logWalk(
        _ key: String, km: Double?, minutes: Double?, end: Date, fromWatch: Bool = false, afterSheet: Bool = false
    ) {
        guard settings.health, health != nil, let row = engine.row(for: key), row.isWalk, isLive(row.date) else { return }
        // ходьба идёт или запускается: её время уже пишется
        if workout?.kind == .walk || workoutPending == .walk { return }
        let indoor = WatchLink.isIndoorWalk(sync.journal.filter { $0.date == row.date })
        switch WalkLog.outcome(km: km, minutes: minutes, end: end, indoor: indoor, last: lastWorkout) {
        case .noMinutes:
            if !fromWatch, (km ?? 0) > 0 { showToast("Без минут отрезок в «Здоровье» не записан") }
        case .covered:
            // эту ходьбу только что сохранила тренировка
            break
        case .save(let entry):
            walkQueue.append(entry)
            storage.save(walkQueue, for: "walks")
            flushWalks(afterSheet: afterSheet)
        }
    }

    /// Запуск и возврат в приложение: ходьба, которая ждала в очереди, и вопрос о расстоянии.
    func healthWake() {
        if walkQueue.isEmpty {
            askDistanceAccess()
        } else {
            flushWalks()
        }
    }

    /// Писать расстояние приложение научилось позже, чем тренировки. У тех, кто тренировки уже
    /// разрешил, «Здоровье» один раз спросит о нём при входе в приложение. На свежей установке
    /// вопрос задаётся как раньше: с первой тренировкой или первым отрезком.
    private func askDistanceAccess() {
        guard settings.health, let health, !askingDistance, !walksFlushing, health.access == .granted,
              health.distanceUnasked, UIApplication.shared.applicationState == .active else { return }
        askingDistance = true
        Task {
            _ = await health.requestAccess()
            healthAccess = health.access
            askingDistance = false
            if walksAgain {
                walksAgain = false
                flushWalks()
            }
        }
    }

    /// Записывает очередь ходьбы в «Здоровье». Двух разборов очереди одновременно не бывает.
    func flushWalks(afterSheet: Bool = false) {
        guard let health else { return }
        if walksFlushing || askingDistance {
            walksAgain = true
            return
        }
        let fresh = WalkLog.fresh(walkQueue, now: now())
        if fresh != walkQueue {
            walkQueue = fresh
            storage.save(walkQueue, for: "walks")
        }
        guard !walkQueue.isEmpty else { return }
        walksFlushing = true
        let hold = BackgroundHold()
        hold.begin()
        Task {
            await writeWalks(health, afterSheet: afterSheet)
            hold.end()
            walksFlushing = false
            if walksAgain {
                walksAgain = false
                flushWalks()
            }
        }
    }

    /// Отрезки с часов приходят в свёрнутое приложение, и телефон при этом может быть заблокирован.
    /// Там разрешение не спрашивается, а несохранённая ходьба остаётся ждать возврата в приложение.
    private func writeWalks(_ health: HealthStore, afterSheet: Bool) async {
        var access = health.access
        if isOnScreen, access == .unknown || (access == .granted && health.distanceUnasked) {
            // системный лист «Здоровья» не показывается поверх окна, которое ещё закрывается
            if afterSheet { try? await Task.sleep(nanoseconds: 500_000_000) }
            _ = await health.requestAccess()
            access = health.access
            healthAccess = access
        }
        guard access == .granted else {
            guard isOnScreen else { return }
            walkQueue = []
            storage.save(walkQueue, for: "walks")
            showToast("Нет доступа к «Здоровью». Разрешите запись тренировок в настройках телефона.")
            return
        }
        var saved = false
        var lost = false
        for entry in walkQueue {
            let done = await health.saveWorkout(
                kind: .walk, indoor: entry.indoor, start: entry.start, end: entry.end, km: entry.km
            )
            // в свёрнутом приложении неудача не окончательна: «Здоровье» может быть закрыто до разблокировки
            guard done || isOnScreen else { continue }
            if let index = walkQueue.firstIndex(of: entry) { walkQueue.remove(at: index) }
            storage.save(walkQueue, for: "walks")
            if done {
                saved = true
            } else {
                lost = true
            }
        }
        if lost {
            showToast("Ходьба не сохранилась в «Здоровье»")
        } else if saved {
            showToast("Ходьба записана в «Здоровье»")
        }
    }

    private var isOnScreen: Bool {
        UIApplication.shared.applicationState == .active
    }

    /// Переключатель «Записывать тренировки в „Здоровье“»: при включении спрашивает разрешение.
    func setHealth(_ on: Bool) {
        update { $0.health = on }
        guard on, let health else { return }
        Task {
            _ = await health.requestAccess()
            healthAccess = health.access
        }
    }

    // MARK: Часы

    func nextStamp() -> Int64 {
        watchMemory.stamp = WatchLink.nextStamp(after: watchMemory.stamp, now: now())
        return watchMemory.stamp
    }

    /// Отправит часам состояние после того, как закончится текущее действие.
    func scheduleWatchPush() {
        guard watch != nil, !watchPushScheduled else { return }
        watchPushScheduled = true
        Task { [weak self] in
            guard let self else { return }
            self.watchPushScheduled = false
            self.pushWatchState()
        }
    }

    /// Отправляет часам состояние дня, если оно изменилось.
    func pushWatchState() {
        guard let watch else { return }
        var state = WatchLink.dayState(
            journal: sync.journal, today: today, live: live?.date, settings: settings,
            configured: sync.configured && sync.snapshot != nil
        )
        state.rest = timer
        state.workout = workout
        state.intent = intent
        state.ackEpoch = watchMemory.epoch
        state.ackSeq = watchMemory.seq
        if state == lastWatchState { return }
        var stamped = state
        stamped.stamp = nextStamp()
        if watch.send(stamped) {
            lastWatchState = state
            storage.save(watchMemory, for: "watch")
        }
    }

    func watchStatusChanged() {
        guard let watch else { return }
        let installed = watch.isInstalled
        if installed != watchInstalled { watchInstalled = installed }
        // часы появились или открыли приложение: состояние уходит заново
        lastWatchState = nil
        pushWatchState()
    }

    /// Посылка от часов: действия применяются по одному разу, сколько бы раз они ни пришли.
    func receive(_ packet: WatchPacket) {
        // часы могли разбудить свёрнутое приложение уже на следующий день
        refreshToday()
        let accepted = WatchLink.accept(packet, epoch: watchMemory.epoch, seq: watchMemory.seq)
        watchMemory.epoch = packet.epoch
        watchMemory.seq = accepted.seq
        storage.save(watchMemory, for: "watch")
        var edited = false
        for op in accepted.ops {
            if apply(op) { edited = true }
        }
        if let current = intent, packet.intentDone >= current.id { intent = nil }
        pushWatchState()
        if edited { holdBackground() }
    }

    /// Применяет действие часов. Возвращает true, если в очередь попала правка журнала.
    private func apply(_ op: WatchOp) -> Bool {
        switch op.action {
        case .reps(let key, let index, let value):
            guard let row = engine.row(for: key) else { return false }
            let wasEmpty = row.sets.indices.contains(index) && row.sets[index] == nil
            let last = Journal.lastTime(sync.journal, for: row)
            guard let fields = WatchLink.patch(for: op.action, row: row, last: last) else { return false }
            engine.queue(row, fields)
            if wasEmpty, value != nil { follow(key) }
            return true
        case .weight(let key, _):
            guard let row = engine.row(for: key) else { return false }
            let last = Journal.lastTime(sync.journal, for: row)
            guard let fields = WatchLink.patch(for: op.action, row: row, last: last) else { return false }
            engine.queue(row, fields)
            return true
        case .walkAdd(let key, let km, let minutes, let workout):
            guard let row = engine.row(for: key) else { return false }
            let last = Journal.lastTime(sync.journal, for: row)
            guard let fields = WatchLink.patch(for: op.action, row: row, last: last) else { return false }
            engine.queue(row, fields)
            // отрезок записали на часах вручную: ходьбу в «Здоровье» пишет телефон
            if workout == nil {
                logWalk(key, km: km, minutes: minutes, end: min(op.at, now()), fromWatch: true)
            }
            return true
        case .rest(let timer):
            adoptRest(timer)
            return false
        case .workoutStarted(let started):
            var adopted = started
            adopted.onWatch = true
            workout = adopted
            workoutPending = nil
            workoutEnding = false
            workoutStale = false
            rememberWorkout()
            return false
        case .workoutEnded(let summary):
            if let current = workout, current.onWatch || current.id == summary.id {
                workout = nil
                rememberWorkout()
            }
            workoutEnding = false
            workoutStale = false
            let askWalk = stopRequested
            stopRequested = false
            finished(summary, askWalk: askWalk)
            return false
        }
    }

    /// Подход записали на часах: телефон открывает ту же пару.
    private func follow(_ key: String) {
        guard let row = row(key) else { return }
        let pairs = Journal.splitDay(sync.journal.filter { $0.date == row.date }).pairs
        guard let index = pairs.firstIndex(where: { pair in pair.contains { $0.key == key } }) else { return }
        focus = Focus(date: row.date, pair: index)
    }

    /// Приложение свернули: если в очереди есть записи, просим у системы время, чтобы они успели уйти.
    func enteredBackground() {
        if sync.pending > 0 { holdBackground() }
    }

    private func holdBackground() {
        guard UIApplication.shared.applicationState != .active else { return }
        let hold = BackgroundHold()
        hold.begin()
        Task {
            _ = await engine.sync().value
            hold.end()
        }
    }
}
