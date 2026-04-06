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
        let sanitized = sanitized
        return sanitized.enabled ? "On - last \(sanitized.keep) turns" : "Off"
    }
}

final class LightSessionSettingsStore {
    static let shared = LightSessionSettingsStore()

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
    }

    func makeBootstrapScript() -> String {
        let configJSON = jsonString(for: settings)

        return """
        (function() {
          const DEFAULT_CONFIG = { enabled: true, keep: 20 };
          const STATUS_ID = 'codex-lightsession-status';
          const STATUS_STYLE_ID = 'codex-lightsession-status-style';
          let statusHideTimer = null;

          function sanitizeConfig(value) {
            const keepValue = Number(value && value.keep);
            const boundedKeep = Number.isFinite(keepValue)
              ? Math.min(100, Math.max(1, Math.round(keepValue)))
              : DEFAULT_CONFIG.keep;

            return {
              enabled: value && typeof value.enabled === 'boolean' ? value.enabled : DEFAULT_CONFIG.enabled,
              keep: boundedKeep
            };
          }

          function ensureStatusStyle() {
            if (document.getElementById(STATUS_STYLE_ID)) {
              return;
            }

            const style = document.createElement('style');
            style.id = STATUS_STYLE_ID;
            style.textContent = `
              #${STATUS_ID} {
                position: fixed;
                top: calc(env(safe-area-inset-top, 0px) + 12px);
                left: 16px;
                right: 16px;
                z-index: 2147483646;
                display: flex;
                justify-content: center;
                pointer-events: none;
                opacity: 0;
                transform: translateY(-6px);
                transition: opacity 160ms ease, transform 160ms ease;
              }

              #${STATUS_ID}.visible {
                opacity: 1;
                transform: translateY(0);
              }

              #${STATUS_ID} .pill {
                max-width: 100%;
                padding: 9px 14px;
                border-radius: 12px;
                background: rgba(24, 135, 84, 0.96);
                color: #ffffff;
                font: 600 13px/1.35 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                box-shadow: 0 8px 22px rgba(0, 0, 0, 0.22);
                white-space: nowrap;
                overflow: hidden;
                text-overflow: ellipsis;
              }
            `;
            (document.head || document.documentElement).appendChild(style);
          }

          function ensureStatusElement() {
            ensureStatusStyle();

            let container = document.getElementById(STATUS_ID);
            if (container) {
              return container;
            }

            container = document.createElement('div');
            container.id = STATUS_ID;
            const pill = document.createElement('div');
            pill.className = 'pill';
            container.appendChild(pill);
            (document.body || document.documentElement).appendChild(container);
            return container;
          }

          function showStatus(text, timeoutMs) {
            const container = ensureStatusElement();
            const pill = container.firstElementChild;
            if (!pill) {
              return;
            }

            pill.textContent = text;
            container.classList.add('visible');

            if (statusHideTimer) {
              clearTimeout(statusHideTimer);
              statusHideTimer = null;
            }

            if (timeoutMs && timeoutMs > 0) {
              statusHideTimer = setTimeout(() => {
                container.classList.remove('visible');
                statusHideTimer = null;
              }, timeoutMs);
            }
          }

          window.__codexLightSessionConfig__ = sanitizeConfig(\(configJSON));
          if (window.__codexLightSessionConfig__.enabled) {
            showStatus('LightSession enabled - limit ' + window.__codexLightSessionConfig__.keep, 2200);
          }

          if (window.__codexLightSessionPatched__) {
            return;
          }

          window.__codexLightSessionPatched__ = true;

          const HIDDEN_ROLES = new Set(['system', 'tool', 'thinking']);

          function isVisibleMessage(node) {
            const role = node && node.message && node.message.author && node.message.author.role;
            return Boolean(role) && !HIDDEN_ROLES.has(role);
          }

          function trimMapping(data, limit) {
            const mapping = data && data.mapping;
            const currentNode = data && data.current_node;

            if (!mapping || !currentNode || !mapping[currentNode]) {
              return null;
            }

            const path = [];
            let cursor = currentNode;
            const visited = new Set();

            while (cursor) {
              const node = mapping[cursor];
              if (!node || visited.has(cursor)) {
                break;
              }

              visited.add(cursor);
              path.push(cursor);
              cursor = node.parent || null;
            }

            path.reverse();

            let visibleTotal = 0;
            let lastVisibleRole = null;
            for (const nodeId of path) {
              const node = mapping[nodeId];
              if (node && isVisibleMessage(node)) {
                const role = (node.message && node.message.author && node.message.author.role) || '';
                if (role !== lastVisibleRole) {
                  visibleTotal += 1;
                  lastVisibleRole = role;
                }
              }
            }

            const effectiveLimit = Math.max(1, limit);
            let turnCount = 0;
            let cutIndex = 0;
            let lastRole = null;

            for (let index = path.length - 1; index >= 0; index -= 1) {
              const nodeId = path[index];
              const node = mapping[nodeId];
              if (!node || !isVisibleMessage(node)) {
                continue;
              }

              const role = (node.message && node.message.author && node.message.author.role) || '';
              if (role !== lastRole) {
                turnCount += 1;
                lastRole = role;
              }

              if (turnCount > effectiveLimit) {
                cutIndex = index + 1;
                break;
              }
            }

            const keptRaw = path.slice(cutIndex);
            const kept = keptRaw.filter((nodeId) => {
              const node = mapping[nodeId];
              return Boolean(node) && isVisibleMessage(node);
            });

            if (!kept.length) {
              return null;
            }

            const originalRootId = path[0];
            const originalRootNode = originalRootId ? mapping[originalRootId] : null;
            const hasOriginalRoot = Boolean(
              originalRootId &&
              originalRootNode &&
              !isVisibleMessage(originalRootNode)
            );

            const newMapping = {};
            let visibleKept = 0;
            let previousRole = null;

            if (hasOriginalRoot) {
              newMapping[originalRootId] = Object.assign({}, originalRootNode, {
                parent: null,
                children: kept[0] ? [kept[0]] : []
              });
            }

            for (let index = 0; index < kept.length; index += 1) {
              const nodeId = kept[index];
              const originalNode = mapping[nodeId];
              const previousId = index === 0
                ? (hasOriginalRoot ? originalRootId : null)
                : kept[index - 1];
              const nextId = kept[index + 1] || null;

              if (!originalNode) {
                continue;
              }

              newMapping[nodeId] = Object.assign({}, originalNode, {
                parent: previousId || null,
                children: nextId ? [nextId] : []
              });

              const role = (originalNode.message && originalNode.message.author && originalNode.message.author.role) || '';
              if (isVisibleMessage(originalNode) && role !== previousRole) {
                visibleKept += 1;
                previousRole = role;
              }
            }

            const root = hasOriginalRoot ? originalRootId : kept[0];
            const current = kept[kept.length - 1];

            if (!root || !current) {
              return null;
            }

            return {
              mapping: newMapping,
              current_node: current,
              root,
              visibleKept,
              visibleTotal
            };
          }

          function isConversationRequest(method, url) {
            if (method !== 'GET') {
              return false;
            }

            return /^\\/backend-api\\/(conversation|shared_conversation)\\/[^/]+\\/?$/.test(url.pathname);
          }

          function isJsonResponse(response) {
            const contentType = response.headers.get('content-type') || '';
            return contentType.toLowerCase().includes('application/json');
          }

          function createModifiedResponse(originalResponse, modifiedData) {
            const headers = new Headers(originalResponse.headers);
            headers.delete('content-length');
            headers.delete('content-encoding');
            headers.set('content-type', 'application/json; charset=utf-8');

            const response = new Response(JSON.stringify(modifiedData), {
              status: originalResponse.status,
              statusText: originalResponse.statusText,
              headers
            });

            try {
              if (originalResponse.url) {
                Object.defineProperty(response, 'url', { value: originalResponse.url });
              }
              if (originalResponse.type) {
                Object.defineProperty(response, 'type', { value: originalResponse.type });
              }
            } catch (error) {
              void error;
            }

            return response;
          }

          const nativeFetch = window.fetch.bind(window);

          window.fetch = async function(...args) {
            const [input, init] = args;
            let urlString;
            let method;

            if (input instanceof Request) {
              urlString = input.url;
              method = (init && init.method ? init.method : input.method).toUpperCase();
            } else if (input instanceof URL) {
              urlString = input.href;
              method = (init && init.method ? init.method : 'GET').toUpperCase();
            } else {
              urlString = String(input);
              method = (init && init.method ? init.method : 'GET').toUpperCase();
            }

            const url = new URL(urlString, location.href);
            if (!isConversationRequest(method, url)) {
              return nativeFetch(...args);
            }

            const config = sanitizeConfig(window.__codexLightSessionConfig__ || DEFAULT_CONFIG);
            if (!config.enabled) {
              return nativeFetch(...args);
            }

            const response = await nativeFetch(...args);

            try {
              if (!isJsonResponse(response)) {
                return response;
              }

              const json = await response.clone().json().catch(() => null);
              if (!json || typeof json !== 'object' || !json.mapping || !json.current_node) {
                return response;
              }

              const trimmed = trimMapping(json, config.keep);
              if (!trimmed) {
                return response;
              }

              const removed = Math.max(0, trimmed.visibleTotal - trimmed.visibleKept);
              if (trimmed.visibleKept === trimmed.visibleTotal) {
                showStatus(
                  'LightSession: kept ' + trimmed.visibleKept + '/' + trimmed.visibleTotal +
                  ' turn(s) (limit ' + config.keep + ')',
                  2600
                );
                return response;
              }

              const removedPercent = trimmed.visibleTotal > 0
                ? Math.round((removed / trimmed.visibleTotal) * 100)
                : 0;

              showStatus(
                'LightSession: kept ' + trimmed.visibleKept + '/' + trimmed.visibleTotal +
                ' turn(s) (limit ' + config.keep + ') - removed ' + removed +
                ' (~' + removedPercent + '%)',
                3400
              );

              return createModifiedResponse(response, Object.assign({}, json, {
                mapping: trimmed.mapping,
                current_node: trimmed.current_node,
                root: trimmed.root
              }));
            } catch (error) {
              return response;
            }
          };
        })();
        """
    }

    func makeRuntimeUpdateScript() -> String {
        "window.__codexLightSessionConfig__ = (function(value) { const keep = Number(value && value.keep); return { enabled: Boolean(value && value.enabled), keep: Number.isFinite(keep) ? Math.min(100, Math.max(1, Math.round(keep))) : 20 }; })(\(jsonString(for: settings)));"
    }

    private func jsonString(for settings: LightSessionSettings) -> String {
        let sanitized = settings.sanitized
        guard
            let data = try? JSONEncoder().encode(sanitized),
            let string = String(data: data, encoding: .utf8)
        else {
            return #"{"enabled":true,"keep":20}"#
        }

        return string
    }
}
