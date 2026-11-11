import Foundation

/// Хранилище на устройстве: настройки, последний снимок журнала и очередь записей.
/// Запись синхронная, поэтому правка переживает мгновенное закрытие приложения.
public protocol StateStorage: AnyObject {
    func data(for name: String) -> Data?
    /// Сохраняет значение; nil — удалить. Возвращает, удалось ли сохранить.
    @discardableResult
    func set(_ data: Data?, for name: String) -> Bool
}

public extension StateStorage {
    func load<T: Decodable>(_ type: T.Type, for name: String) -> T? {
        guard let data = data(for: name) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    @discardableResult
    func save<T: Encodable>(_ value: T, for name: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return set(data, for: name)
    }

    func remove(_ name: String) {
        set(nil, for: name)
    }
}

/// Хранилище в памяти: для тестов, показа с учебными данными и случая, когда диск недоступен.
public final class MemoryStorage: StateStorage {
    private var values: [String: Data] = [:]
    /// Тесты выставляют false, чтобы изобразить телефон, который не даёт сохранять.
    public var writable = true

    public init() {}

    public func data(for name: String) -> Data? {
        values[name]
    }

    @discardableResult
    public func set(_ data: Data?, for name: String) -> Bool {
        guard writable else { return false }
        values[name] = data
        return true
    }
}

/// Файлы в папке приложения: по одному файлу JSON на значение.
public final class FileStorage: StateStorage {
    private let directory: URL
    /// false — папку не удалось создать: данные живут только до закрытия приложения.
    public private(set) var persistent: Bool
    private let fallback = MemoryStorage()

    public init(directory: URL) {
        self.directory = directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            persistent = true
        } catch {
            persistent = false
        }
    }

    private func file(_ name: String) -> URL {
        directory.appendingPathComponent("\(name).json")
    }

    public func data(for name: String) -> Data? {
        guard persistent else { return fallback.data(for: name) }
        return try? Data(contentsOf: file(name))
    }

    @discardableResult
    public func set(_ data: Data?, for name: String) -> Bool {
        guard persistent else {
            fallback.set(data, for: name)
            return false
        }
        do {
            if let data {
                try data.write(to: file(name), options: [.atomic])
            } else if FileManager.default.fileExists(atPath: file(name).path) {
                try FileManager.default.removeItem(at: file(name))
            }
            return true
        } catch {
            return false
        }
    }
}
