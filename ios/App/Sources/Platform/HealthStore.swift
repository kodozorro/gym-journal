import Foundation
import HealthKit
import GymJournalCore

/// «Здоровье» на телефоне: разрешение, запуск тренировки на часах и запись тренировки самим
/// телефоном, когда часов рядом нет.
///
/// Телефон не меряет пульс и калории, поэтому сам он записывает только вид тренировки и её
/// время. Настоящую тренировку с пульсом ведут часы.
final class HealthStore {
    private let store = HKHealthStore()

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Что приложение пишет: тренировки.
    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType()]
    }

    /// Что читают часы во время тренировки: пульс, калории и расстояние. Разрешение у телефона
    /// и часов общее, поэтому вопрос задаётся один раз, на телефоне.
    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
        ]
    }

    var access: HealthAccess {
        guard HealthStore.isAvailable else { return .unavailable }
        switch store.authorizationStatus(for: HKObjectType.workoutType()) {
        case .sharingAuthorized: return .granted
        case .sharingDenied: return .denied
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }

    /// Спрашивает разрешение, если его ещё не спрашивали. Возвращает, можно ли писать тренировки.
    func requestAccess() async -> Bool {
        guard HealthStore.isAvailable else { return false }
        let share = shareTypes
        let read = readTypes
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            store.requestAuthorization(toShare: share, read: read) { _, _ in
                continuation.resume(returning: self.access == .granted)
            }
        }
    }

    private func makeConfiguration(kind: WorkoutKind, indoor: Bool) -> HKWorkoutConfiguration {
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

    /// Открывает приложение на часах и просит его начать тренировку.
    func startWatchApp(kind: WorkoutKind, indoor: Bool) async -> Bool {
        guard HealthStore.isAvailable else { return false }
        let configuration = makeConfiguration(kind: kind, indoor: indoor)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            store.startWatchApp(with: configuration) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    /// Записывает в «Здоровье» тренировку, которую вёл телефон: вид и время, без пульса и калорий.
    func saveWorkout(kind: WorkoutKind, indoor: Bool, start: Date, end: Date) async -> Bool {
        guard HealthStore.isAvailable, end > start else { return false }
        let builder = HKWorkoutBuilder(
            healthStore: store, configuration: makeConfiguration(kind: kind, indoor: indoor), device: HKDevice.local()
        )
        let began = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            builder.beginCollection(withStart: start) { success, _ in
                continuation.resume(returning: success)
            }
        }
        guard began else { return false }
        let ended = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            builder.endCollection(withEnd: end) { success, _ in
                continuation.resume(returning: success)
            }
        }
        guard ended else {
            builder.discardWorkout()
            return false
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            builder.finishWorkout { workout, _ in
                continuation.resume(returning: workout != nil)
            }
        }
    }
}
