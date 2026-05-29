//
//  TabManagerImpl.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import Foundation
import GeckoView
import UIKit

final class TabManagerImplementation: NSObject, TabManager {
    private static let shellHomeURL = "https://chatgpt.com"
    // Keep login/challenge handoffs in Gecko; route normal content links out.
    private static let embeddedChatGPTFlowHosts: Set<String> = [
        "account.live.com",
        "accounts.google.com",
        "accounts.openai.com",
        "appleid.apple.com",
        "auth.openai.com",
        "auth0.openai.com",
        "challenges.cloudflare.com",
        "idmsa.apple.com",
        "login.live.com",
        "login.microsoftonline.com",
        "login.openai.com",
        "openid.apple.com",
    ]
    private(set) var tabs: [Tab] = []
    private(set) var selectedTabIndex = -1

    var selectedTab: Tab? {
        tabs[safe: selectedTabIndex]
    }

    private weak var delegate: TabManagerDelegate?

    init(delegate: TabManagerDelegate?) {
        self.delegate = delegate
    }

    private func closeSession(_ session: GeckoSession) {
        if session.isOpen() {
            session.setActive(false)
        }
        session.close()
    }

    private func persistState() {}

    private var reloadFlags: Int {
        GeckoSessionLoadFlags.none
    }

    private func loadURL(_ url: String, in tab: Tab, flags: Int = GeckoSessionLoadFlags.none) {
        tab.session.updateSettings(UserAgentController.shared.sessionSettings(for: url, tabID: tab.id))
        tab.session.load(url, flags: flags)
    }

    private func makeTab(windowId: String?) -> Tab {
        let tab = Tab(session: createSession(windowId: windowId))
        return tab
    }

    private func restoredURL(from value: String?) -> String? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty,
              trimmedValue.lowercased() != "about:blank" else {
            return nil
        }

        return trimmedValue
    }

    private func remoteURL(from value: String?) -> URL? {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: trimmedValue),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }

        return url
    }

    private func normalizedAddressInput(_ value: String) -> String? {
        if remoteURL(from: value) != nil {
            return value
        }

        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              value.contains("."),
              remoteURL(from: "https://" + value) != nil else {
            return nil
        }

        return "https://" + value
    }

    private func shouldOpenLoadRequestExternally(session: GeckoSession, request: LoadRequest) -> Bool {
        guard (request.hasUserGesture || request.isRedirect),
              let index = tabIndex(for: session),
              shouldOpenExternallyFromChatGPT(
                targetURLString: request.uri,
                sourceURLString: request.triggerUri ?? tabs[index].url
              ) else {
            return false
        }

        return requestExternalOpen(request.uri)
    }

    private func shouldOpenExternallyFromChatGPT(targetURLString: String, sourceURLString: String?) -> Bool {
        guard let targetURL = remoteURL(from: targetURLString),
              isChatGPTURL(sourceURLString),
              !shouldKeepEmbeddedForChatGPT(targetURL) else {
            return false
        }

        return true
    }

    private func isChatGPTURL(_ value: String?) -> Bool {
        guard let url = remoteURL(from: value),
              let host = url.host?.lowercased() else {
            return false
        }

        return host == "chatgpt.com" ||
            host.hasSuffix(".chatgpt.com") ||
            host == "chat.openai.com"
    }

    private func isChatConversationURL(_ value: String) -> Bool {
        guard let url = remoteURL(from: value),
              let host = url.host?.lowercased() else {
            return false
        }

        return (host == "chatgpt.com" || host.hasSuffix(".chatgpt.com")) &&
            url.path.hasPrefix("/c/")
    }

    private func shouldKeepEmbeddedForChatGPT(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return isChatGPTURL(url.absoluteString) ||
            Self.embeddedChatGPTFlowHosts.contains { hostMatches(host, domain: $0) }
    }

    private func hostMatches(_ host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    @discardableResult
    private func requestExternalOpen(_ value: String) -> Bool {
        guard let url = remoteURL(from: value) else {
            return false
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.tabManager(self, didRequestExternalOpen: url)
        }
        return true
    }

    private func loadRestoredURLIfNeeded(for index: Int) {
        guard tabs.indices.contains(index) else {
            return
        }

        let tab = tabs[index]
        guard let url = tab.pendingRestoreURL else {
            return
        }

        tab.pendingRestoreURL = nil
        tab.suppressInitialNavigation = false
        loadURL(url, in: tab)
    }

    func createInitialTab() {
        let index = addTab(selecting: true, windowId: nil, at: nil)
        if let tab = tabs[safe: index] {
            load(Self.shellHomeURL, in: tab)
        }
    }

    @discardableResult
    func addTab(selecting: Bool, windowId: String? = nil, at insertionIndex: Int? = nil) -> Int {
        if let existing = tabs.first {
            if selecting {
                selectedTabIndex = 0
                existing.session.setActive(true)
            }
            return 0
        }

        let tab = makeTab(windowId: windowId)
        tabs.append(tab)

        delegate?.tabManagerDidChangeTabs(self)

        if selecting {
            selectTab(at: 0)
        } else {
            persistState()
        }

        return 0
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else {
            return
        }

        let previousIndex = tabs.indices.contains(selectedTabIndex) ? selectedTabIndex : nil

        selectedTabIndex = index
        tabs[index].session.setActive(true)

        delegate?.tabManager(self, didSelectTabAt: index, previousIndex: previousIndex)
        loadRestoredURLIfNeeded(for: index)
        persistState()
    }

    func removeTab(at index: Int) {
        guard let tab = selectedTab else {
            createInitialTab()
            return
        }

        load(Self.shellHomeURL, in: tab)
    }

    func removeAllTabs() {
        guard let tab = selectedTab else {
            createInitialTab()
            return
        }

        load(Self.shellHomeURL, in: tab)
    }

    func browse(to term: String) {
        guard let tab = selectedTab else {
            return
        }
        browse(to: term, in: tab)
    }

    func browse(to term: String, in tab: Tab) {
        let trimmedValue = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return
        }

        tab.suppressInitialNavigation = false
        tab.pendingDisplayText = trimmedValue

        guard let target = normalizedAddressInput(trimmedValue) else {
            return
        }

        load(target, in: tab, flags: GeckoSessionLoadFlags.none)
    }

    func load(_ url: String, in tab: Tab, flags: Int = GeckoSessionLoadFlags.none) {
        let trimmedValue = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return
        }

        tab.suppressInitialNavigation = false
        tab.pendingDisplayText = trimmedValue
        loadURL(trimmedValue, in: tab, flags: flags)
    }

    func reload(_ tab: Tab) {
        guard let target = restoredURL(from: tab.url) else {
            load(Self.shellHomeURL, in: tab, flags: reloadFlags)
            return
        }

        tab.session.updateSettings(UserAgentController.shared.sessionSettings(for: target, tabID: tab.id))
        tab.session.reload(flags: reloadFlags)
    }

    func tabIndex(for session: GeckoSession) -> Int? {
        tabs.firstIndex(where: { $0.session === session })
    }

    func shareableURL(for tab: Tab) -> URL? {
        guard let value = tab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.lowercased() != "about:blank",
              let url = URL(string: value),
              let scheme = url.scheme,
              !scheme.isEmpty else {
            return nil
        }
        return url
    }

    func updateThumbnail(_ _: UIImage?, forTabAt index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].thumbnail = nil
    }

    private func createSession(windowId: String?) -> GeckoSession {
        let session = GeckoSession()
        session.contentDelegate = self
        session.progressDelegate = self
        session.navigationDelegate = self
        session.open(windowId: windowId)
        return session
    }

}

extension TabManagerImplementation: ContentDelegate {
    func onTitleChange(session: GeckoSession, title: String) {
        guard let index = tabIndex(for: session) else {
            return
        }

        tabs[index].title = title
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .title)
        persistState()
    }

    func onPreviewImage(session: GeckoSession, previewImageUrl: String) {
    }

    func onFocusRequest(session: GeckoSession) {
        guard selectedTab?.session === session else {
            return
        }

        session.setActive(true)
        session.setFocused(true)
    }

    func onCloseRequest(session: GeckoSession) {
        session.load(Self.shellHomeURL)
    }

    func onFullScreen(session: GeckoSession, fullScreen: Bool) {
    }

    func onMetaViewportFitChange(session: GeckoSession, viewportFit: String) {
    }

    func onProductUrl(session: GeckoSession) {
    }

    func onCrash(session: GeckoSession) {
        session.reload()
    }

    func onKill(session: GeckoSession) {
        session.reload()
    }

    func onFirstComposite(session: GeckoSession) {
    }

    func onFirstContentfulPaint(session: GeckoSession) {
    }

    func onPaintStatusReset(session: GeckoSession) {
    }

    func onWebAppManifest(session: GeckoSession, manifest: Any) {
    }

    func onSlowScript(session: GeckoSession, scriptFileName: String) async -> SlowScriptResponse {
        guard let index = tabIndex(for: session) else {
            return .halt
        }

        let tab = tabs[index]
        if isChatGPTURL(tab.url) ||
            isChatGPTURL(tab.pendingDisplayText) ||
            isChatGPTURL(tab.pendingRestoreURL) {
            return .resume
        }

        return .halt
    }

    func onShowDynamicToolbar(session: GeckoSession) {
    }

    func onCookieBannerDetected(session: GeckoSession) {
    }

    func onCookieBannerHandled(session: GeckoSession) {
    }

    func onExternalResponse(session: GeckoSession, response: ExternalResponseInfo) {
        _ = delegate?.tabManager(self, shouldHandleExternalResponse: response, for: session)
    }

    func onSavePdf(session: GeckoSession, request: SavePdfInfo) {
        if let download = DownloadStore.shared.prepareDownload(from: request) {
            DownloadStore.shared.startDownload(download)
        }
    }

    func onChatGPTTapTarget(session: GeckoSession, info: [String: Any]) {
        ChatGPTTapTargetLog.write(info)
    }
}

private enum ChatGPTTapTargetLog {
    private static let queue = DispatchQueue(label: "com.codex.chatgpt.tap-target-log")
    private static let maxLogBytes: UInt64 = 250_000

    static func write(_ info: [String: Any]) {
        queue.async {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }

            let fileURL = documentsURL.appendingPathComponent("ChatGPTTapTargets.log", isDirectory: false)
            rotateIfNeeded(fileURL)

            let line = "\(timestamp()) \(compactDescription(info))\n"
            guard let data = line.data(using: .utf8) else {
                return
            }

            if FileManager.default.fileExists(atPath: fileURL.path),
               let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                return
            }

            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func rotateIfNeeded(_ fileURL: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? UInt64,
              fileSize > maxLogBytes else {
            return
        }

        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func compactDescription(_ info: [String: Any]) -> String {
        let eventType = info["eventType"] ?? ""
        let x = info["x"] ?? ""
        let y = info["y"] ?? ""
        let activeTag = info["activeTag"] ?? ""
        let activeAria = info["activeAria"] ?? ""
        let activeTestid = info["activeTestid"] ?? ""
        let chain = (info["chain"] as? [[String: Any]] ?? []).map { item in
            let tag = item["tag"] ?? ""
            let aria = item["aria"] ?? ""
            let testid = item["testid"] ?? ""
            let role = item["role"] ?? ""
            let text = item["text"] ?? ""
            let rect = item["rect"] ?? ""
            return "[tag=\(tag) role=\(role) aria=\(aria) testid=\(testid) text=\(text) rect=\(rect)]"
        }.joined(separator: " <- ")
        return "event=\(eventType) x=\(x) y=\(y) active=\(activeTag) activeAria=\(activeAria) activeTestid=\(activeTestid) chain=\(chain)"
    }
}

extension TabManagerImplementation: NavigationDelegate {
    func onLocationChange(session: GeckoSession, url: String?, permissions: [ContentPermission]) {
        guard let index = tabIndex(for: session) else {
            return
        }

        let normalizedURL = url?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if tabs[index].suppressInitialNavigation,
           let normalizedURL,
           normalizedURL.hasPrefix("about:blank") {
            return
        }

        if let normalizedURL, !normalizedURL.isEmpty {
            tabs[index].suppressInitialNavigation = false
        }

        if let url {
            session.updateSettings(UserAgentController.shared.sessionSettings(for: url, tabID: tabs[index].id))
        }

        tabs[index].url = url
        tabs[index].pendingDisplayText = nil
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .location)
        persistState()
    }

    func onCanGoBack(session: GeckoSession, canGoBack: Bool) {
        guard let index = tabIndex(for: session) else {
            return
        }

        tabs[index].canGoBack = canGoBack
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .navigationState)
    }

    func onCanGoForward(session: GeckoSession, canGoForward: Bool) {
        guard let index = tabIndex(for: session) else {
            return
        }

        tabs[index].canGoForward = canGoForward
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .navigationState)
    }

    func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        if shouldOpenLoadRequestExternally(session: session, request: request) {
            return .deny
        }

        return .allow
    }

    func onSubframeLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        return .allow
    }

    func onNewSession(session: GeckoSession, uri: String, windowId: String) async -> GeckoSession? {
        if let index = tabIndex(for: session),
           shouldOpenExternallyFromChatGPT(targetURLString: uri, sourceURLString: tabs[index].url),
           requestExternalOpen(uri) {
            return nil
        }

        if let tab = selectedTab {
            loadURL(uri, in: tab)
        }
        return nil
    }
}

extension TabManagerImplementation: ProgressDelegate {
    func onPageStart(session: GeckoSession, url: String) {
        guard let index = tabIndex(for: session) else {
            return
        }

        let currentHost = tabs[index].url.flatMap { UserAgentController.shared.extractHost(from: $0) }
        let requestedHost = UserAgentController.shared.extractHost(from: url)
        let desiredSettings = UserAgentController.shared.sessionSettings(for: url, tabID: tabs[index].id)

        if currentHost != nil,
           requestedHost != nil,
           currentHost != requestedHost,
           (desiredSettings.userAgentOverride != session.userAgentOverride ||
            desiredSettings.userAgentMode != session.userAgentMode ||
            desiredSettings.viewportMode != session.viewportMode) {
            loadURL(url, in: tabs[index])
        }

        tabs[index].isLoading = true
        tabs[index].progress = 0
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .loading)
    }

    func onPageStop(session: GeckoSession, success: Bool) {
        guard let index = tabIndex(for: session) else {
            return
        }

        tabs[index].isLoading = false
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .loading)
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .thumbnail)
    }

    func onProgressChange(session: GeckoSession, progress: Int) {
        guard let index = tabIndex(for: session) else {
            return
        }

        tabs[index].progress = Float(progress) / 100
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .loading)
    }
}
