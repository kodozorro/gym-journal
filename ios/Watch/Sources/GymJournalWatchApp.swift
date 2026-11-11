import HealthKit
import SwiftUI
import WatchKit
import GymJournalCore

/// Модель создаётся вместе с приложением, а не с первым экраном: телефон может открыть приложение
/// на часах, чтобы начать тренировку, раньше, чем экран появится.
@MainActor
final class WatchDelegate: NSObject, WKApplicationDelegate {
    let model = WatchModel.make()

    func applicationDidFinishLaunching() {
        model.start()
    }

    /// Телефон открыл приложение, чтобы начать тренировку: силовую или ходьбу.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        let wanted = WorkoutManager.kind(of: workoutConfiguration)
        model.start()
        model.workoutRequested(kind: wanted.kind, indoor: wanted.indoor)
    }

    /// Приложение закрылось во время тренировки и открыто заново: тренировка продолжается.
    func handleActiveWorkoutRecovery() {
        model.start()
        model.recoverWorkout()
    }
}

@main
struct GymJournalWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(delegate.model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { delegate.model.wake() }
        }
    }
}
