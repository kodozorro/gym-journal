import Foundation
import Network

/// Есть ли сеть. Значение меняется на главном потоке, после чего вызывается onChange.
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private var measured = true
    /// Показ с учебными данными: сеть «выключена» независимо от настоящей.
    var forcedOffline = false {
        didSet {
            if forcedOffline != oldValue { onChange?() }
        }
    }
    var onChange: (() -> Void)?

    var online: Bool { !forcedOffline && measured }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self, self.measured != online else { return }
                self.measured = online
                self.onChange?()
            }
        }
        monitor.start(queue: DispatchQueue(label: "gym-journal.network"))
    }
}
