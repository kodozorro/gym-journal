import Foundation
import WatchConnectivity
import GymJournalCore

/// Связь с телефоном со стороны часов.
///
/// Телефон присылает состояние дня целиком, часы возвращают действия пользователя. Действия
/// уходят сообщением, если телефон на связи, а если нет — встают в очередь системы: она доставит
/// их, когда телефон появится.
final class WatchPhoneLink: NSObject, WCSessionDelegate {
    private let session = WCSession.default
    /// Состояние дня от телефона. Вызывается на главном потоке.
    var onState: ((WatchState) -> Void)?
    /// Телефон появился или пропал. Вызывается на главном потоке.
    var onStatus: (() -> Void)?

    func activate() {
        session.delegate = self
        session.activate()
    }

    private var active: WCSession? {
        session.activationState == .activated ? session : nil
    }

    /// Телефон сейчас на связи.
    var isReachable: Bool {
        active?.isReachable ?? false
    }

    /// Отправляет посылку телефону.
    /// - Parameter queued: если сообщение не дошло или телефон не на связи, отдать посылку
    ///   системе: она доставит её позже. Повторные отправки той же посылки в очередь не ставятся.
    func send(_ packet: WatchPacket, queued: Bool) {
        guard let session = active, let data = WatchLink.encode(packet) else { return }
        let payload: [String: Any] = [WatchLink.packetKey: data]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { _ in }, errorHandler: { _ in
                if queued { _ = session.transferUserInfo(payload) }
            })
        } else if queued {
            _ = session.transferUserInfo(payload)
        }
    }

    private func receive(_ payload: [String: Any]) {
        guard let state = WatchLink.decode(WatchState.self, from: payload[WatchLink.stateKey] as? Data) else { return }
        DispatchQueue.main.async {
            self.onState?(state)
        }
    }

    private func statusChanged() {
        DispatchQueue.main.async {
            self.onStatus?()
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // последнее состояние, которое телефон прислал, пока приложение на часах было закрыто
        receive(session.receivedApplicationContext)
        statusChanged()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        statusChanged()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        receive(message)
        replyHandler([:])
    }
}
