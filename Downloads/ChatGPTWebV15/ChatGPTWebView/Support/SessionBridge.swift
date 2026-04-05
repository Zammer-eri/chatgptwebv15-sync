import Foundation
import UIKit

enum SessionSyncReason: String {
    case launch
    case foreground
    case loggedOut = "logged_out"
    case manual
}

struct HelperConfiguration: Codable {
    let host: String
    let port: Int
    let secret: String

    var baseURL: URL? {
        URL(string: "http://\(host):\(port)")
    }
}

struct BrowserCookiePayload: Codable {
    let domain: String
    let name: String
    let value: String
    let path: String
    let secure: Bool
    let httpOnly: Bool
    let session: Bool
    let sameSite: String?
    let expirationDate: Double?

    func asHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: domain,
            .path: path,
            .name: name,
            .value: value
        ]

        if secure {
            properties[.secure] = "TRUE"
        }

        if let expirationDate {
            properties[.expires] = Date(timeIntervalSince1970: expirationDate)
        }

        return HTTPCookie(properties: properties)
    }
}

struct SessionEnvelope: Codable {
    let schema: Int
    let bundleHash: String?
    let capturedAt: String?
    let cookies: [BrowserCookiePayload]
    let refreshed: Bool?
    let refreshStatus: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case schema
        case bundleHash = "bundle_hash"
        case capturedAt = "captured_at"
        case cookies
        case refreshed
        case refreshStatus = "refresh_status"
        case reason
    }
}

struct EnsureFreshRequest: Codable {
    let knownHash: String?
    let reason: String

    enum CodingKeys: String, CodingKey {
        case knownHash = "known_hash"
        case reason
    }
}

extension Notification.Name {
    static let helperConfigurationDidChange = Notification.Name("HelperConfigurationDidChange")
}

final class HelperConfigurationStore {
    static let shared = HelperConfigurationStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "desktopHelperConfiguration"

    var configuration: HelperConfiguration? {
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }

        return try? JSONDecoder().decode(HelperConfiguration.self, from: data)
    }

    func save(host: String, port: Int, secret: String) {
        let configuration = HelperConfiguration(host: host, port: port, secret: secret)
        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }

        defaults.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: .helperConfigurationDidChange, object: nil)
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
        NotificationCenter.default.post(name: .helperConfigurationDidChange, object: nil)
    }

    func importConfiguration(from url: URL) -> Bool {
        guard url.scheme?.lowercased() == "chatgptwebv15" else {
            return false
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard url.host?.lowercased() == "pair" else {
            return false
        }

        let queryItems = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        guard
            let host = queryItems["host"], !host.isEmpty,
            let portString = queryItems["port"], let port = Int(portString),
            let secret = queryItems["secret"], !secret.isEmpty
        else {
            return false
        }

        save(host: host, port: port, secret: secret)
        return true
    }

    func importConfiguration(from string: String) -> Bool {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }

        return importConfiguration(from: url)
    }
}

final class LegacySessionStore {
    static let shared = LegacySessionStore()

    private let defaults = UserDefaults.standard
    private let sessionCookieKey = "sessionCookie"

    var hasLegacySession: Bool {
        !(legacyCookieValue ?? "").isEmpty
    }

    var legacyCookieValue: String? {
        let value = defaults.string(forKey: sessionCookieKey)
        return value?.isEmpty == false ? value : nil
    }

    func clear() {
        defaults.removeObject(forKey: sessionCookieKey)
    }

    func makeLegacyCookie() -> BrowserCookiePayload? {
        guard let legacyCookieValue else {
            return nil
        }

        return BrowserCookiePayload(
            domain: "chat.openai.com",
            name: "__Secure-next-auth.session-token",
            value: legacyCookieValue,
            path: "/",
            secure: true,
            httpOnly: true,
            session: false,
            sameSite: nil,
            expirationDate: Date().addingTimeInterval(60 * 60 * 24 * 30).timeIntervalSince1970
        )
    }
}

final class SessionSyncService {
    static let shared = SessionSyncService()

    private let defaults = UserDefaults.standard
    private let knownHashKey = "lastKnownSessionBundleHash"
    private let urlSession = URLSession(configuration: .default)

    var lastKnownHash: String? {
        defaults.string(forKey: knownHashKey)
    }

    func clearKnownHash() {
        defaults.removeObject(forKey: knownHashKey)
    }

    func fetchSession(
        reason: SessionSyncReason,
        forceRefresh: Bool,
        completion: @escaping (Result<SessionEnvelope?, Error>) -> Void
    ) {
        guard let configuration = HelperConfigurationStore.shared.configuration,
              let baseURL = configuration.baseURL else {
            completion(.success(nil))
            return
        }

        let endpoint = forceRefresh || reason == .loggedOut ? "/v1/ensure-fresh" : "/v1/session"
        guard let url = URL(string: endpoint, relativeTo: baseURL) else {
            completion(.success(nil))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(configuration.secret)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12

        if endpoint == "/v1/ensure-fresh" {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(
                EnsureFreshRequest(knownHash: lastKnownHash, reason: reason.rawValue)
            )
        }

        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  let data else {
                completion(.success(nil))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.success(nil))
                return
            }

            do {
                let envelope = try JSONDecoder().decode(SessionEnvelope.self, from: data)
                if let hash = envelope.bundleHash {
                    self?.defaults.set(hash, forKey: self?.knownHashKey ?? "")
                }
                completion(.success(envelope))
            } catch {
                completion(.failure(error))
            }
        }

        task.resume()
    }
}
