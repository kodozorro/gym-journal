import Foundation
import UserNotifications

/// Уведомление о конце отдыха на случай, когда телефон заблокирован или приложение свёрнуто.
/// Пока приложение на экране, уведомление не показывается: приложение подаёт сигнал само.
final class RestNotifier: NSObject, UNUserNotificationCenterDelegate {
    private static let identifier = "rest-end"
    private let center = UNUserNotificationCenter.current()
    /// Растёт с каждым новым решением: ответ на устаревшую просьбу не ставит уведомление.
    private var generation = 0

    override init() {
        super.init()
        center.delegate = self
    }

    /// Ставит уведомление на момент конца отдыха. Разрешение спрашивается при первом отдыхе.
    func schedule(at date: Date, sound: Bool) {
        cancel()
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
                if sound { content.sound = .default }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                let request = UNNotificationRequest(identifier: RestNotifier.identifier, content: content, trigger: trigger)
                self.center.add(request)
            }
        }
    }

    func cancel() {
        generation += 1
        center.removePendingNotificationRequests(withIdentifiers: [RestNotifier.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [RestNotifier.identifier])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}
