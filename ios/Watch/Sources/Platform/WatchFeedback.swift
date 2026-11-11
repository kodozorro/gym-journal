import Foundation
import UserNotifications
import WatchKit

/// Сигналы часов: отклик на запись подхода и конец отдыха.
///
/// Часы вибрируют сами, только пока приложение на экране или идёт тренировка: так устроена
/// система. Когда рука опущена, а тренировки нет, о конце отдыха напоминает уведомление. Звук
/// к вибрации добавляют сами часы, если на них выключен бесшумный режим.
final class WatchFeedback: NSObject, UNUserNotificationCenterDelegate {
    private static let identifier = "rest-end"
    private let center = UNUserNotificationCenter.current()
    /// Растёт с каждым новым решением: ответ на устаревшую просьбу не ставит уведомление.
    private var generation = 0

    override init() {
        super.init()
        center.delegate = self
    }

    func play(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }

    /// Ставит уведомление на момент конца отдыха. Разрешение спрашивается при первом отдыхе.
    func scheduleRestEnd(at date: Date) {
        cancelRestEnd()
        guard date.timeIntervalSinceNow > 1 else { return }
        let mine = generation
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                guard let self, self.generation == mine else { return }
                let delay = date.timeIntervalSinceNow
                guard delay > 1 else { return }
                let content = UNMutableNotificationContent()
                content.title = "Отдых окончен"
                content.body = "Пора делать следующий подход."
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                let request = UNNotificationRequest(identifier: WatchFeedback.identifier, content: content, trigger: trigger)
                self.center.add(request)
            }
        }
    }

    func cancelRestEnd() {
        generation += 1
        center.removePendingNotificationRequests(withIdentifiers: [WatchFeedback.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [WatchFeedback.identifier])
    }

    /// Пока приложение на экране, уведомление не показывается: часы вибрируют сами.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}
