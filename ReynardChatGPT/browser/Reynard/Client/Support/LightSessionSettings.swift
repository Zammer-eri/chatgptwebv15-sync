import Foundation

struct LightSessionSettings: Codable {
    static let defaultKeep = 20
    static let minimumKeep = 1
    static let maximumKeep = 100
    static let defaults = LightSessionSettings(enabled: true, keep: defaultKeep)

    var enabled: Bool
    var keep: Int

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
        NotificationCenter.default.post(name: Self.didChangeNotification, object: sanitized)
    }
}
