import Foundation

struct LightSessionSettings: Codable {
    static let defaultKeep = 20
    static let minimumKeep = 1
    static let maximumKeep = 100
    static let defaults = LightSessionSettings(enabled: true, keep: defaultKeep)

    var enabled: Bool
    var keep: Int

    enum CodingKeys: String, CodingKey {
        case enabled
        case keep
    }

    init(enabled: Bool, keep: Int) {
        self.enabled = enabled
        self.keep = keep
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        keep = try container.decodeIfPresent(Int.self, forKey: .keep) ?? Self.defaultKeep
    }

    var sanitized: LightSessionSettings {
        LightSessionSettings(
            enabled: enabled,
            keep: min(Self.maximumKeep, max(Self.minimumKeep, keep))
        )
    }

    var summaryText: String {
        let value = sanitized
        return value.enabled ? "On - last \(value.keep) turns" : "Off"
    }
}

final class LightSessionSettingsStore {
    static let shared = LightSessionSettingsStore()
    static let didChangeNotification = Notification.Name("LightSessionSettingsDidChange")

    private let defaults = UserDefaults.standard
    private let storageKey = "lightSessionSettings"

    var settings: LightSessionSettings {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(LightSessionSettings.self, from: data)
        else {
            return .defaults
        }

        return decoded.sanitized
    }

    func save(_ settings: LightSessionSettings) {
        let sanitized = settings.sanitized
        guard let data = try? JSONEncoder().encode(sanitized) else {
            return
        }

        defaults.set(data, forKey: storageKey)
        defaults.synchronize()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: sanitized)
    }
}
