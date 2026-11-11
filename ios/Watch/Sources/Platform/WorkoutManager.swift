import Foundation
import HealthKit
import GymJournalCore

/// Показатели идущей тренировки.
struct WorkoutMetrics: Equatable {
    /// Пульс, ударов в минуту.
    var heartRate: Double?
    /// Активные калории.
    var kcal: Double?
    /// Километры по датчикам часов.
    var km: Double?
}

/// Чем закончилась тренировка на часах.
struct WorkoutFinish {
    var endedAt: Date
    var km: Double?
    var kcal: Double?
    /// Тренировка сохранена в «Здоровье».
    var saved: Bool
}

/// Тренировка, которую часы продолжили после перезапуска приложения.
struct RecoveredWorkout {
    var kind: WorkoutKind
    var indoor: Bool
    var startedAt: Date
}

/// Тренировка в «Здоровье» на часах: настоящая, с пульсом и калориями.
///
/// Пока тренировка идёт, часы меряют пульс чаще обычного, а приложение продолжает работать с
/// опущенной рукой. Сохранённая тренировка идёт в кольца активности.
@MainActor
final class WorkoutManager: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// Тренировка уже сохраняется: второй раз её не заканчиваем.
    private var finishing = false

    /// Новые показатели: пульс, калории, расстояние.
    var onMetrics: ((WorkoutMetrics) -> Void)?
    /// Тренировка закончилась: её завершили, или она оборвалась.
    var onEnded: ((WorkoutFinish) -> Void)?

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var isRunning: Bool {
        session != nil
    }

    static func configuration(kind: WorkoutKind, indoor: Bool) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        switch kind {
        case .strength:
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
        case .walk:
            configuration.activityType = .walking
            configuration.locationType = indoor ? .indoor : .outdoor
        }
        return configuration
    }

    /// Вид тренировки, которую попросил начать телефон.
    static func kind(of configuration: HKWorkoutConfiguration) -> (kind: WorkoutKind, indoor: Bool) {
        let kind: WorkoutKind = configuration.activityType == .walking ? .walk : .strength
        return (kind, configuration.locationType != .outdoor)
    }

    /// Спрашивает разрешение, если его ещё не спрашивали. Возвращает, можно ли писать тренировки.
    func requestAccess() async -> Bool {
        guard WorkoutManager.isAvailable else { return false }
        let store = self.store
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
        ]
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.requestAuthorization(toShare: share, read: read) { _, _ in
                continuation.resume()
            }
        }
        return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    /// Начинает тренировку. Возвращает время начала или nil, если начать не удалось.
    func start(kind: WorkoutKind, indoor: Bool) async -> Date? {
        guard WorkoutManager.isAvailable, session == nil else { return nil }
        let configuration = WorkoutManager.configuration(kind: kind, indoor: indoor)
        let started: HKWorkoutSession
        do {
            started = try HKWorkoutSession(healthStore: store, configuration: configuration)
        } catch {
            return nil
        }
        let live = started.associatedWorkoutBuilder()
        live.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
        started.delegate = self
        live.delegate = self
        session = started
        builder = live
        finishing = false
        let start = Date()
        started.startActivity(with: start)
        let began = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            live.beginCollection(withStart: start) { success, _ in
                continuation.resume(returning: success)
            }
        }
        if began { return start }
        // сбор данных не начался: чаще всего нет разрешения записывать тренировки
        if session === started {
            session = nil
            builder = nil
            started.end()
            live.discardWorkout()
        }
        return nil
    }

    /// Заканчивает тренировку. Итог придёт в onEnded, когда она сохранится.
    func end() {
        guard let current = session, !finishing else { return }
        current.stopActivity(with: Date())
        Task { [weak self] in
            // обычно часы сразу сообщают, что тренировка остановлена; если нет — заканчиваем сами
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, self.session === current, !self.finishing else { return }
            current.end()
        }
    }

    /// Продолжает тренировку, которая шла, когда приложение закрылось.
    func recover() async -> RecoveredWorkout? {
        guard WorkoutManager.isAvailable, session == nil else { return nil }
        let store = self.store
        let found = await withCheckedContinuation { (continuation: CheckedContinuation<HKWorkoutSession?, Never>) in
            store.recoverActiveWorkoutSession { session, _ in
                continuation.resume(returning: session)
            }
        }
        guard let found, session == nil else { return nil }
        guard found.state == .running || found.state == .paused else {
            if found.state != .ended { found.end() }
            return nil
        }
        let live = found.associatedWorkoutBuilder()
        live.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: found.workoutConfiguration)
        found.delegate = self
        live.delegate = self
        session = found
        builder = live
        finishing = false
        if found.state == .paused { found.resume() }
        let parts = WorkoutManager.kind(of: found.workoutConfiguration)
        return RecoveredWorkout(
            kind: parts.kind, indoor: parts.indoor, startedAt: found.startDate ?? live.startDate ?? Date()
        )
    }

    /// Сохраняет тренировку после остановки и сообщает итог.
    private func finish(_ ended: HKWorkoutSession, at date: Date, alreadyEnded: Bool) {
        guard ended === session, !finishing, let live = builder else { return }
        finishing = true
        Task {
            let collected = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                live.endCollection(withEnd: date) { success, _ in
                    continuation.resume(returning: success)
                }
            }
            var saved = false
            if collected {
                saved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    live.finishWorkout { workout, _ in
                        continuation.resume(returning: workout != nil)
                    }
                }
            } else {
                live.discardWorkout()
            }
            let totals = WorkoutManager.metrics(of: live)
            session = nil
            builder = nil
            finishing = false
            if !alreadyEnded { ended.end() }
            onEnded?(WorkoutFinish(endedAt: date, km: totals.km, kcal: totals.kcal, saved: saved))
        }
    }

    /// Показатели, которые собрала тренировка к этому моменту.
    private nonisolated static func metrics(of builder: HKLiveWorkoutBuilder) -> WorkoutMetrics {
        var out = WorkoutMetrics()
        if let quantity = builder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity() {
            out.heartRate = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
        if let quantity = builder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity() {
            out.kcal = quantity.doubleValue(for: .kilocalorie())
        }
        if let quantity = builder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity() {
            out.km = quantity.doubleValue(for: .meterUnit(with: .kilo))
        }
        return out
    }

    // MARK: HKWorkoutSessionDelegate

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState, date: Date
    ) {
        guard toState == .stopped || toState == .ended else { return }
        let ended = toState == .ended
        Task { @MainActor [weak self] in
            self?.finish(workoutSession, at: date, alreadyEnded: ended)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        // тренировка оборвалась: сохраняем то, что успели собрать
        Task { @MainActor [weak self] in
            self?.finish(workoutSession, at: Date(), alreadyEnded: false)
        }
    }

    // MARK: HKLiveWorkoutBuilderDelegate

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let metrics = WorkoutManager.metrics(of: workoutBuilder)
        Task { @MainActor [weak self] in
            self?.onMetrics?(metrics)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
