import Foundation

final class ShellRuntimeScriptHandler: GeckoEventListenerInternal {
    static let eventType = "ReynardShell:GetPageRuntime"

    init(session _: GeckoSession) {}

    @MainActor
    func handleMessage(type: String, message: [String: Any?]?) async throws -> Any? {
        guard type == Self.eventType else {
            throw GeckoHandlerError("unknown shell runtime event \(type)")
        }

        return ShellRuntimeScriptStore.shared.payload(for: message)
    }
}

private final class ShellRuntimeScriptStore {
    static let shared = ShellRuntimeScriptStore()

    private struct Script {
        let id: String
        let file: String
        let matches: [String]
    }

    private let directoryName = "ShellRuntime"
    private var cachedManifest: [Script]?
    private var cachedSources: [String: String] = [:]

    private var runtimeDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent(directoryName, isDirectory: true)
    }

    func payload(for message: [String: Any?]?) -> [String: Any] {
        let urlString = message?["url"] as? String
        let host = normalizedHost(from: message?["host"] as? String ?? urlString.flatMap { URL(string: $0)?.host })
        let scripts = loadManifest()
            .filter { script in script.matches.contains { matches(pattern: $0, host: host) } }
            .compactMap { script -> [String: Any]? in
                guard let source = source(for: script) else {
                    return nil
                }
                return [
                    "id": script.id,
                    "source": source,
                ]
            }

        return ["scripts": scripts]
    }

    private func loadManifest() -> [Script] {
        if let cachedManifest {
            return cachedManifest
        }

        guard let runtimeDirectory else {
            cachedManifest = []
            return []
        }

        let manifestURL = runtimeDirectory.appendingPathComponent("manifest.json", isDirectory: false)
        guard let data = try? Data(contentsOf: manifestURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["scripts"] as? [[String: Any]] else {
            cachedManifest = []
            return []
        }

        let scripts = entries.compactMap { entry -> Script? in
            guard let id = entry["id"] as? String,
                  let file = entry["file"] as? String,
                  let matches = entry["matches"] as? [String],
                  !id.isEmpty,
                  !file.isEmpty,
                  !matches.isEmpty,
                  isSafeRelativePath(file) else {
                return nil
            }
            return Script(id: id, file: file, matches: matches)
        }

        cachedManifest = scripts
        return scripts
    }

    private func source(for script: Script) -> String? {
        if let source = cachedSources[script.file] {
            return source
        }

        guard let runtimeDirectory else {
            return nil
        }

        let scriptURL = runtimeDirectory.appendingPathComponent(script.file, isDirectory: false).standardizedFileURL
        let runtimePath = runtimeDirectory.standardizedFileURL.path
        guard scriptURL.path.hasPrefix(runtimePath + "/"),
              let source = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            return nil
        }

        cachedSources[script.file] = source
        return source
    }

    private func normalizedHost(from host: String?) -> String {
        (host ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func matches(pattern: String, host: String) -> Bool {
        let pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !pattern.isEmpty, !host.isEmpty else {
            return false
        }

        if pattern == "*" || pattern == host {
            return true
        }

        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2))
            return host == suffix || host.hasSuffix("." + suffix)
        }

        return false
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        !path.hasPrefix("/") &&
        !path.hasPrefix("\\") &&
        !path.contains("..") &&
        !path.contains(":")
    }
}
