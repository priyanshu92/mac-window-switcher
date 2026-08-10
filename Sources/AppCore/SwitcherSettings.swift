import Foundation

public struct SwitcherSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var includeMinimizedWindows: Bool
    public var showWindowTitles: Bool

    public init(
        isEnabled: Bool,
        includeMinimizedWindows: Bool,
        showWindowTitles: Bool
    ) {
        self.isEnabled = isEnabled
        self.includeMinimizedWindows = includeMinimizedWindows
        self.showWindowTitles = showWindowTitles
    }

    public static let `default` = SwitcherSettings(
        isEnabled: true,
        includeMinimizedWindows: true,
        showWindowTitles: true
    )
}

public protocol SwitcherSettingsStore: Sendable {
    func load() -> SwitcherSettings
    func save(_ settings: SwitcherSettings) throws
}

public enum SwitcherSettingsStoreError: Error {
    case failedToEncode
}

public final class UserDefaultsSwitcherSettingsStore: SwitcherSettingsStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey = "switcherSettings"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> SwitcherSettings {
        guard
            let data = defaults.data(forKey: storageKey),
            let settings = try? decoder.decode(SwitcherSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    public func save(_ settings: SwitcherSettings) throws {
        guard let data = try? encoder.encode(settings) else {
            throw SwitcherSettingsStoreError.failedToEncode
        }
        defaults.set(data, forKey: storageKey)
    }
}
