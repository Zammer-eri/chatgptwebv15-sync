import Foundation

struct LightSessionSettings: Codable {
    static let defaultKeep = 20
    static let minimumKeep = 1
    static let maximumKeep = 100
    static let defaults = LightSessionSettings(
        enabled: true,
        keep: defaultKeep,
        ultraLean: false,
        reduceBlur: true,
        reduceShadows: true,
        reduceMotion: true,
        containChatRows: true
    )

    var enabled: Bool
    var keep: Int
    var ultraLean: Bool
    var reduceBlur: Bool
    var reduceShadows: Bool
    var reduceMotion: Bool
    var containChatRows: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case keep
        case ultraLean
        case reduceBlur
        case reduceShadows
        case reduceMotion
        case containChatRows
    }

    init(
        enabled: Bool,
        keep: Int,
        ultraLean: Bool,
        reduceBlur: Bool,
        reduceShadows: Bool,
        reduceMotion: Bool,
        containChatRows: Bool
    ) {
        self.enabled = enabled
        self.keep = keep
        self.ultraLean = ultraLean
        self.reduceBlur = reduceBlur
        self.reduceShadows = reduceShadows
        self.reduceMotion = reduceMotion
        self.containChatRows = containChatRows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        keep = try container.decodeIfPresent(Int.self, forKey: .keep) ?? Self.defaultKeep
        ultraLean = try container.decodeIfPresent(Bool.self, forKey: .ultraLean) ?? false
        reduceBlur = try container.decodeIfPresent(Bool.self, forKey: .reduceBlur) ?? true
        reduceShadows = try container.decodeIfPresent(Bool.self, forKey: .reduceShadows) ?? true
        reduceMotion = try container.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? true
        containChatRows = try container.decodeIfPresent(Bool.self, forKey: .containChatRows) ?? true
    }

    var sanitized: LightSessionSettings {
        LightSessionSettings(
            enabled: enabled,
            keep: min(Self.maximumKeep, max(Self.minimumKeep, keep)),
            ultraLean: ultraLean,
            reduceBlur: reduceBlur,
            reduceShadows: reduceShadows,
            reduceMotion: reduceMotion,
            containChatRows: containChatRows
        )
    }

    var summaryText: String {
        let sanitized = sanitized
        if !sanitized.enabled {
            return sanitized.ultraLean ? "Off - ultra lean" : "Off"
        }

        let leanSuffix = sanitized.ultraLean ? " - ultra lean" : ""
        return "On - last \(sanitized.keep) turns\(leanSuffix)"
    }
}

extension Notification.Name {
    static let lightSessionSettingsDidChange = Notification.Name("LightSessionSettingsDidChange")
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
        NotificationCenter.default.post(name: .lightSessionSettingsDidChange, object: nil)
    }

    func makeBootstrapScript() -> String {
        let config = settings
        let configJSON = jsonString(for: config)

        return """
        (function() {
          const DEFAULT_CONFIG = {
            enabled: true,
            keep: 20,
            ultraLean: false,
            reduceBlur: true,
            reduceShadows: true,
            reduceMotion: true,
            containChatRows: true
          };

          function sanitizeConfig(value) {
            const keepValue = Number(value && value.keep);
            const boundedKeep = Number.isFinite(keepValue)
              ? Math.min(100, Math.max(1, Math.round(keepValue)))
              : DEFAULT_CONFIG.keep;

            return {
              enabled: value && typeof value.enabled === 'boolean' ? value.enabled : DEFAULT_CONFIG.enabled,
              keep: boundedKeep,
              ultraLean: Boolean(value && value.ultraLean),
              reduceBlur: value && typeof value.reduceBlur === 'boolean' ? value.reduceBlur : DEFAULT_CONFIG.reduceBlur,
              reduceShadows: value && typeof value.reduceShadows === 'boolean' ? value.reduceShadows : DEFAULT_CONFIG.reduceShadows,
              reduceMotion: value && typeof value.reduceMotion === 'boolean' ? value.reduceMotion : DEFAULT_CONFIG.reduceMotion,
              containChatRows: value && typeof value.containChatRows === 'boolean' ? value.containChatRows : DEFAULT_CONFIG.containChatRows
            };
          }

          function ensureUltraLeanStyle() {
            var style = document.getElementById('codex-ultra-lean-style');
            if (style) {
              return;
            }

            style = document.createElement('style');
            style.id = 'codex-ultra-lean-style';
            style.textContent = `
              html.codex-lean-motion *,
              html.codex-lean-motion *::before,
              html.codex-lean-motion *::after {
                animation-duration: 0.01ms !important;
                animation-delay: 0ms !important;
                animation-iteration-count: 1 !important;
                transition-duration: 0.01ms !important;
                transition-delay: 0ms !important;
                scroll-behavior: auto !important;
              }

              html.codex-lean-blur [class*="backdrop-blur"],
              html.codex-lean-blur [class*="backdrop-blur-"],
              html.codex-lean-blur [style*="backdrop-filter"],
              html.codex-lean-blur header,
              html.codex-lean-blur nav,
              html.codex-lean-blur aside,
              html.codex-lean-blur [role="dialog"] {
                -webkit-backdrop-filter: none !important;
                backdrop-filter: none !important;
              }

              html.codex-lean-shadows [class*="shadow"],
              html.codex-lean-shadows [class*="drop-shadow"],
              html.codex-lean-shadows [style*="box-shadow"] {
                box-shadow: none !important;
              }

              html.codex-lean-shadows [style*="text-shadow"] {
                text-shadow: none !important;
              }

              html.codex-lean-contain [data-testid="conversation-turn"],
              html.codex-lean-contain [data-testid="conversation-turns"] > div,
              html.codex-lean-contain article {
                contain: layout paint style !important;
                content-visibility: auto !important;
                contain-intrinsic-size: 0 720px !important;
              }
            `;

            (document.head || document.documentElement).appendChild(style);
          }

          function applyUltraLean(config) {
            ensureUltraLeanStyle();
            const enabled = Boolean(config && config.ultraLean);
            document.documentElement.classList.toggle('codex-ultra-lean', enabled);
            document.documentElement.classList.toggle('codex-lean-blur', enabled && Boolean(config && config.reduceBlur));
            document.documentElement.classList.toggle('codex-lean-shadows', enabled && Boolean(config && config.reduceShadows));
            document.documentElement.classList.toggle('codex-lean-motion', enabled && Boolean(config && config.reduceMotion));
            document.documentElement.classList.toggle('codex-lean-contain', enabled && Boolean(config && config.containChatRows));
          }

          window.__codexApplyUltraLean__ = applyUltraLean;
          window.__codexLightSessionConfig__ = sanitizeConfig(\(configJSON));
          applyUltraLean(window.__codexLightSessionConfig__);

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

          function dispatchStatus(detail) {
            try {
              window.dispatchEvent(new CustomEvent('codex-lightsession-status', { detail }));
            } catch (error) {
              void error;
            }
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
            applyUltraLean(config);
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

              if (trimmed.visibleKept === trimmed.visibleTotal) {
                dispatchStatus({
                  totalBefore: trimmed.visibleTotal,
                  keptAfter: trimmed.visibleKept,
                  removed: 0,
                  limit: config.keep
                });
                return response;
              }

              dispatchStatus({
                totalBefore: trimmed.visibleTotal,
                keptAfter: trimmed.visibleKept,
                removed: Math.max(0, trimmed.visibleTotal - trimmed.visibleKept),
                limit: config.keep
              });

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
        "window.__codexLightSessionConfig__ = (function(value) { const keep = Number(value && value.keep); return { enabled: Boolean(value && value.enabled), keep: Number.isFinite(keep) ? Math.min(100, Math.max(1, Math.round(keep))) : 20, ultraLean: Boolean(value && value.ultraLean), reduceBlur: !(value && value.reduceBlur === false), reduceShadows: !(value && value.reduceShadows === false), reduceMotion: !(value && value.reduceMotion === false), containChatRows: !(value && value.containChatRows === false) }; })(\(jsonString(for: settings))); if (window.__codexApplyUltraLean__) { window.__codexApplyUltraLean__(window.__codexLightSessionConfig__); }"
    }

    private func jsonString(for settings: LightSessionSettings) -> String {
        let sanitized = settings.sanitized
        guard
            let data = try? JSONEncoder().encode(sanitized),
            let string = String(data: data, encoding: .utf8)
        else {
            return #"{"enabled":true,"keep":20,"ultraLean":false,"reduceBlur":true,"reduceShadows":true,"reduceMotion":true,"containChatRows":true}"#
        }

        return string
    }
}
