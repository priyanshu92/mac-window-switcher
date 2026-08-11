import Foundation

public struct SwitcherSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var includeMinimizedWindows: Bool
    public var showWindowTitles: Bool
    public var dockWindowPreviewsEnabled: Bool

    public init(
        isEnabled: Bool,
        includeMinimizedWindows: Bool,
        showWindowTitles: Bool,
        dockWindowPreviewsEnabled: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.includeMinimizedWindows = includeMinimizedWindows
        self.showWindowTitles = showWindowTitles
        self.dockWindowPreviewsEnabled = dockWindowPreviewsEnabled
    }

    public static let `default` = SwitcherSettings(
        isEnabled: true,
        includeMinimizedWindows: true,
        showWindowTitles: true,
        dockWindowPreviewsEnabled: false
    )

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case includeMinimizedWindows
        case showWindowTitles
        case dockWindowPreviewsEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        includeMinimizedWindows = try container.decode(Bool.self, forKey: .includeMinimizedWindows)
        showWindowTitles = try container.decode(Bool.self, forKey: .showWindowTitles)
        dockWindowPreviewsEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .dockWindowPreviewsEnabled) ?? false
    }
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
