import Foundation
import WatchConnectivity
import GymJournalCore

/// Связь с часами со стороны телефона.
///
/// Телефон присылает часам состояние дня целиком, часы возвращают действия пользователя.
/// Состояние уходит двумя путями: «последнее известное» система доставит, когда сможет, а
/// сообщение дойдёт сразу, если приложение на часах открыто.
final class PhoneWatchLink: NSObject, WCSessionDelegate {
    private let session: WCSession?
    /// Посылка от часов. Вызывается на главном потоке.
    var onPacket: ((WatchPacket) -> Void)?
    /// Часы появились, пропали или приложение на них открыли. Вызывается на главном потоке.
    var onStatus: (() -> Void)?

    override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    private var active: WCSession? {
        guard let session, session.activationState == .activated else { return nil }
        return session
    }

    /// Часы привязаны к телефону, и приложение на них установлено.
    var isInstalled: Bool {
        guard let session = active else { return false }
        return session.isPaired && session.isWatchAppInstalled
    }

    /// Приложение на часах сейчас открыто.
    var isReachable: Bool {
        active?.isReachable ?? false
    }

    /// Отправляет состояние дня. Возвращает false, если отправить некому.
    @discardableResult
    func send(_ state: WatchState) -> Bool {
        guard let session = active, session.isPaired, session.isWatchAppInstalled,
              let data = WatchLink.encode(state) else { return false }
        let payload: [String: Any] = [WatchLink.stateKey: data]
        do {
            try session.updateApplicationContext(payload)
        } catch {
            return false
        }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
        return true
    }

    private func receive(_ payload: [String: Any]) {
        guard let packet = WatchLink.decode(WatchPacket.self, from: payload[WatchLink.packetKey] as? Data) else { return }
        DispatchQueue.main.async {
            self.onPacket?(packet)
        }
    }

    private func statusChanged() {
        DispatchQueue.main.async {
            self.onStatus?()
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        statusChanged()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // пользователь сменил часы: связь нужно открыть заново
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        statusChanged()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        statusChanged()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        receive(message)
        replyHandler([:])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo)
    }
}
