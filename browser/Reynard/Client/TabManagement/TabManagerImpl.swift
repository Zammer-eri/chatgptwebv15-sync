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
    private var loadWatchdogs: [UUID: DispatchWorkItem] = [:]

    private lazy var isURLLenient: NSRegularExpression = {
        let pattern = "^\\s*(\\w+-+)*[\\w\\[]+(://[/]*|:|\\.)(\\w+-+)*[\\w\\[:]+([\\S&&[^\\w-]]\\S*)?\\s*$"
        return try! NSRegularExpression(pattern: pattern)
    }()

    init(delegate: TabManagerDelegate?) {
        self.delegate = delegate
    }

    private func closeSession(_ session: GeckoSession) {
        ShellDiagnostics.log("closeSession session=\(session.diagnosticID ?? "nil")")
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
        ShellDiagnostics.log("loadURL tab=\(tab.id.uuidString) flags=\(flags) url=\(url)")
        tab.session.updateSettings(UserAgentController.shared.sessionSettings(for: url, tabID: tab.id))
        tab.session.load(url, flags: flags)
    }

    private func makeTab(windowId: String?) -> Tab {
        let tab = Tab(session: createSession(windowId: windowId))
        ShellDiagnostics.log("makeTab tab=\(tab.id.uuidString) session=\(tab.session.diagnosticID ?? "nil") windowId=\(windowId ?? "nil")")
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

        ShellDiagnostics.log("externalOpen url=\(url.absoluteString)")
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.tabManager(self, didRequestExternalOpen: url)
        }
        return true
    }

    private func scheduleFaviconUpdate(forTabAt index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].favicon = nil
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .favicon)
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
        ShellDiagnostics.log("loadRestoredURL tab=\(tab.id.uuidString) url=\(url)")
        loadURL(url, in: tab)
    }

    func createInitialTab() {
        let index = addTab(selecting: true, windowId: nil, at: nil)
        if let tab = tabs[safe: index] {
            ShellDiagnostics.log("createInitialTab tab=\(tab.id.uuidString)")
            load(Self.shellHomeURL, in: tab)
        }
    }

    @discardableResult
    func addTab(selecting: Bool, windowId: String? = nil, at insertionIndex: Int? = nil) -> Int {
        let tab = makeTab(windowId: windowId)
        let index = min(max(insertionIndex ?? tabs.count, 0), tabs.count)

        if index == tabs.count {
            tabs.append(tab)
        } else {
            tabs.insert(tab, at: index)
            if selectedTabIndex >= index {
                selectedTabIndex += 1
            }
        }

        delegate?.tabManagerDidChangeTabs(self)
        ShellDiagnostics.log("addTab tab=\(tab.id.uuidString) index=\(index) selecting=\(selecting) count=\(tabs.count)")

        if selecting {
            selectTab(at: index)
        } else {
            persistState()
        }

        return index
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else {
            return
        }

        let previousIndex = tabs.indices.contains(selectedTabIndex) ? selectedTabIndex : nil

        selectedTabIndex = index
        tabs[index].session.setActive(true)
        ShellDiagnostics.log("selectTab index=\(index) tab=\(tabs[index].id.uuidString) previous=\(previousIndex.map(String.init) ?? "nil")")

        delegate?.tabManager(self, didSelectTabAt: index, previousIndex: previousIndex)
        loadRestoredURLIfNeeded(for: index)
        persistState()
    }

    func removeTab(at index: Int) {
        guard tabs.indices.contains(index) else {
            return
        }

        let wasSelected = index == selectedTabIndex
        let removedTab = tabs.remove(at: index)
        UserAgentController.shared.clearOverrides(forTabID: removedTab.id)
        cancelLoadWatchdog(for: removedTab)
        ShellDiagnostics.log("removeTab index=\(index) tab=\(removedTab.id.uuidString) wasSelected=\(wasSelected)")

        if tabs.isEmpty {
            selectedTabIndex = -1
            delegate?.tabManagerDidChangeTabs(self)
            let replacementIndex = addTab(selecting: true, windowId: nil, at: nil)
            if let replacementTab = tabs[safe: replacementIndex] {
                load(Self.shellHomeURL, in: replacementTab)
            }
            closeSession(removedTab.session)
            return
        }

        if wasSelected {
            selectedTabIndex = -1
        } else if index < selectedTabIndex {
            selectedTabIndex -= 1
        }

        delegate?.tabManagerDidChangeTabs(self)

        if wasSelected {
            let fallback = min(index, tabs.count - 1)
            selectTab(at: fallback)
        } else {
            persistState()
        }

        closeSession(removedTab.session)
    }

    func removeAllTabs() {
        guard !tabs.isEmpty else {
            return
        }

        let removedTabs = tabs
        tabs.removeAll(keepingCapacity: true)
        removedTabs.forEach(cancelLoadWatchdog)
        removedTabs.forEach { UserAgentController.shared.clearOverrides(forTabID: $0.id) }
        selectedTabIndex = -1
        ShellDiagnostics.log("removeAllTabs count=\(removedTabs.count)")
        delegate?.tabManagerDidChangeTabs(self)
        let replacementIndex = addTab(selecting: true, windowId: nil)
        if let replacementTab = tabs[safe: replacementIndex] {
            load(Self.shellHomeURL, in: replacementTab)
        }

        removedTabs.forEach { closeSession($0.session) }
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
        ShellDiagnostics.log("browse tab=\(tab.id.uuidString) term=\(trimmedValue)")

        let fullRange = NSRange(location: 0, length: (trimmedValue as NSString).length)
        let isURL = isURLLenient.firstMatch(in: trimmedValue, range: fullRange) != nil

        if isURL {
            load(trimmedValue, in: tab, flags: GeckoSessionLoadFlags.none)
            return
        }

        let searchTarget = searchURL(for: trimmedValue)
        loadURL(searchTarget, in: tab)
    }

    func load(_ url: String, in tab: Tab, flags: Int = GeckoSessionLoadFlags.none) {
        let trimmedValue = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return
        }

        tab.suppressInitialNavigation = false
        tab.pendingDisplayText = trimmedValue
        ShellDiagnostics.log("load tab=\(tab.id.uuidString) flags=\(flags) url=\(trimmedValue)")
        loadURL(trimmedValue, in: tab, flags: flags)
    }

    func reload(_ tab: Tab) {
        guard let target = restoredURL(from: tab.url) else {
            ShellDiagnostics.log("reload fallback tab=\(tab.id.uuidString) flags=\(reloadFlags)")
            load(Self.shellHomeURL, in: tab, flags: reloadFlags)
            return
        }

        ShellDiagnostics.log("reload tab=\(tab.id.uuidString) flags=\(reloadFlags) url=\(target)")
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
        ShellDiagnostics.log("createSession session=\(session.diagnosticID ?? "nil") windowId=\(windowId ?? "nil")")
        return session
    }

    private func scheduleLoadWatchdog(for tab: Tab, url: String) {
        cancelLoadWatchdog(for: tab)
        let tabID = tab.id
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  let index = self.tabs.firstIndex(where: { $0.id == tabID }),
                  self.tabs[index].isLoading else {
                return
            }

            ShellDiagnostics.log(
                "loadWatchdog stuck tab=\(tabID.uuidString) progress=\(self.tabs[index].progress) currentURL=\(self.tabs[index].url ?? "nil") startedURL=\(url)"
            )
        }
        loadWatchdogs[tabID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: workItem)
    }

    private func cancelLoadWatchdog(for tab: Tab) {
        loadWatchdogs.removeValue(forKey: tab.id)?.cancel()
    }
}

extension TabManagerImplementation: ContentDelegate {
    func onTitleChange(session: GeckoSession, title: String) {
        guard let index = tabIndex(for: session) else {
            return
        }

        tabs[index].title = title
        ShellDiagnostics.log("titleChange tab=\(tabs[index].id.uuidString) title=\(title)")
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .title)
        persistState()
    }

    func onPreviewImage(session: GeckoSession, previewImageUrl: String) {
        ShellDiagnostics.log("previewImage session=\(session.diagnosticID ?? "nil") url=\(previewImageUrl)")
    }

    func onFocusRequest(session: GeckoSession) {
        guard selectedTab?.session === session else {
            return
        }

        session.setActive(true)
        session.setFocused(true)
        ShellDiagnostics.log("focusRequest session=\(session.diagnosticID ?? "nil")")
    }

    func onCloseRequest(session: GeckoSession) {
        guard let index = tabIndex(for: session) else {
            return
        }
        ShellDiagnostics.log("closeRequest tab=\(tabs[index].id.uuidString) session=\(session.diagnosticID ?? "nil")")
        removeTab(at: index)
    }

    func onFullScreen(session: GeckoSession, fullScreen: Bool) {
        ShellDiagnostics.log("fullscreen session=\(session.diagnosticID ?? "nil") fullScreen=\(fullScreen)")
    }

    func onMetaViewportFitChange(session: GeckoSession, viewportFit: String) {
        ShellDiagnostics.log("metaViewportFit session=\(session.diagnosticID ?? "nil") viewportFit=\(viewportFit)")
    }

    func onProductUrl(session: GeckoSession) {
        ShellDiagnostics.log("productURL session=\(session.diagnosticID ?? "nil")")
    }

    func onCrash(session: GeckoSession) {
        guard let index = tabIndex(for: session) else {
            return
        }
        ShellDiagnostics.log("contentCrash tab=\(tabs[index].id.uuidString) session=\(session.diagnosticID ?? "nil") url=\(tabs[index].url ?? "nil")")
        removeTab(at: index)
    }

    func onKill(session: GeckoSession) {
        guard let index = tabIndex(for: session) else {
            return
        }
        ShellDiagnostics.log("contentKill tab=\(tabs[index].id.uuidString) session=\(session.diagnosticID ?? "nil") url=\(tabs[index].url ?? "nil")")
        removeTab(at: index)
    }

    func onFirstComposite(session: GeckoSession) {
        ShellDiagnostics.log("firstComposite session=\(session.diagnosticID ?? "nil")")
    }

    func onFirstContentfulPaint(session: GeckoSession) {
        ShellDiagnostics.log("firstContentfulPaint session=\(session.diagnosticID ?? "nil")")
    }

    func onPaintStatusReset(session: GeckoSession) {
        ShellDiagnostics.log("paintStatusReset session=\(session.diagnosticID ?? "nil")")
    }

    func onWebAppManifest(session: GeckoSession, manifest: Any) {
        ShellDiagnostics.log("webAppManifest session=\(session.diagnosticID ?? "nil")")
    }

    func onSlowScript(session: GeckoSession, scriptFileName: String) async -> SlowScriptResponse {
        guard let index = tabIndex(for: session) else {
            ShellDiagnostics.log("slowScript unknownSession=\(session.diagnosticID ?? "nil") file=\(scriptFileName) action=halt")
            return .halt
        }

        let tab = tabs[index]
        if isChatGPTURL(tab.url) ||
            isChatGPTURL(tab.pendingDisplayText) ||
            isChatGPTURL(tab.pendingRestoreURL) {
            ShellDiagnostics.log("slowScript tab=\(tab.id.uuidString) file=\(scriptFileName) action=resume url=\(tab.url ?? "nil")")
            return .resume
        }

        ShellDiagnostics.log("slowScript tab=\(tab.id.uuidString) file=\(scriptFileName) action=halt url=\(tab.url ?? "nil")")
        return .halt
    }

    func onShowDynamicToolbar(session: GeckoSession) {
        ShellDiagnostics.log("showDynamicToolbar session=\(session.diagnosticID ?? "nil")")
    }

    func onCookieBannerDetected(session: GeckoSession) {
        ShellDiagnostics.log("cookieBannerDetected session=\(session.diagnosticID ?? "nil")")
    }

    func onCookieBannerHandled(session: GeckoSession) {
        ShellDiagnostics.log("cookieBannerHandled session=\(session.diagnosticID ?? "nil")")
    }

    func onExternalResponse(session: GeckoSession, response: ExternalResponseInfo) {
        ShellDiagnostics.log("externalResponse session=\(session.diagnosticID ?? "nil") url=\(response.url) mime=\(response.mimeType ?? "nil")")
    }

    func onSavePdf(session: GeckoSession, request: SavePdfInfo) {
        ShellDiagnostics.log("savePdf session=\(session.diagnosticID ?? "nil") url=\(request.url)")
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
            ShellDiagnostics.log("locationIgnored tab=\(tabs[index].id.uuidString) url=\(url ?? "nil")")
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
        tabs[index].favicon = nil
        ShellDiagnostics.log("locationChange tab=\(tabs[index].id.uuidString) session=\(session.diagnosticID ?? "nil") url=\(url ?? "nil") permissions=\(permissions.count)")
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .location)
        scheduleFaviconUpdate(forTabAt: index)
        persistState()
    }

    func onCanGoBack(session: GeckoSession, canGoBack: Bool) {
        guard let index = tabIndex(for: session) else {
            return
        }

        tabs[index].canGoBack = canGoBack
        ShellDiagnostics.log("canGoBack tab=\(tabs[index].id.uuidString) value=\(canGoBack)")
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .navigationState)
    }

    func onCanGoForward(session: GeckoSession, canGoForward: Bool) {
        guard let index = tabIndex(for: session) else {
            return
        }

        tabs[index].canGoForward = canGoForward
        ShellDiagnostics.log("canGoForward tab=\(tabs[index].id.uuidString) value=\(canGoForward)")
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .navigationState)
    }

    func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        if shouldOpenLoadRequestExternally(session: session, request: request) {
            ShellDiagnostics.log("loadRequest denyExternal session=\(session.diagnosticID ?? "nil") uri=\(request.uri) trigger=\(request.triggerUri ?? "nil") redirect=\(request.isRedirect) gesture=\(request.hasUserGesture)")
            return .deny
        }

        ShellDiagnostics.log("loadRequest allow session=\(session.diagnosticID ?? "nil") uri=\(request.uri) trigger=\(request.triggerUri ?? "nil") redirect=\(request.isRedirect) gesture=\(request.hasUserGesture)")
        return .allow
    }

    func onSubframeLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        ShellDiagnostics.log("subframeLoadRequest allow session=\(session.diagnosticID ?? "nil") uri=\(request.uri)")
        return .allow
    }

    func onNewSession(session: GeckoSession, uri: String, windowId: String) async -> GeckoSession? {
        if let index = tabIndex(for: session),
           shouldOpenExternallyFromChatGPT(targetURLString: uri, sourceURLString: tabs[index].url),
           requestExternalOpen(uri) {
            ShellDiagnostics.log("newSession deniedExternal sourceSession=\(session.diagnosticID ?? "nil") uri=\(uri)")
            return nil
        }

        ShellDiagnostics.log("newSession sourceSession=\(session.diagnosticID ?? "nil") windowId=\(windowId) uri=\(uri)")
        let newSession = GeckoSession()
        newSession.contentDelegate = self
        newSession.progressDelegate = self
        newSession.navigationDelegate = self

        let newTab = Tab(session: newSession)
        newSession.updateSettings(UserAgentController.shared.sessionSettings(for: uri, tabID: newTab.id))
        newTab.url = uri
        newTab.favicon = nil

        let insertionIndex = tabIndex(for: session).map { $0 + 1 }
        let index = min(max(insertionIndex ?? tabs.count, 0), tabs.count)
        if index == tabs.count {
            tabs.append(newTab)
        } else {
            tabs.insert(newTab, at: index)
            if selectedTabIndex >= index {
                selectedTabIndex += 1
            }
        }

        delegate?.tabManagerDidChangeTabs(self)
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .location)
        scheduleFaviconUpdate(forTabAt: index)
        persistState()
        delegate?.tabManager(self, animateNewTabSelectionAt: index) { [weak self] in
            self?.selectTab(at: index)
        }
        return newSession
    }
}

extension TabManagerImplementation: ProgressDelegate {
    func onPageStart(session: GeckoSession, url: String) {
        guard let index = tabIndex(for: session) else {
            ShellDiagnostics.log("pageStart unknownSession=\(session.diagnosticID ?? "nil") url=\(url)")
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
            ShellDiagnostics.log("pageStart reloadForSettings tab=\(tabs[index].id.uuidString) currentHost=\(currentHost ?? "nil") requestedHost=\(requestedHost ?? "nil") url=\(url)")
            loadURL(url, in: tabs[index])
        }

        tabs[index].isLoading = true
        tabs[index].progress = 0
        ShellDiagnostics.log("pageStart tab=\(tabs[index].id.uuidString) session=\(session.diagnosticID ?? "nil") url=\(url)")
        scheduleLoadWatchdog(for: tabs[index], url: url)
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .loading)
    }

    func onPageStop(session: GeckoSession, success: Bool) {
        guard let index = tabIndex(for: session) else {
            ShellDiagnostics.log("pageStop unknownSession=\(session.diagnosticID ?? "nil") success=\(success)")
            return
        }

        tabs[index].isLoading = false
        cancelLoadWatchdog(for: tabs[index])
        ShellDiagnostics.log("pageStop tab=\(tabs[index].id.uuidString) session=\(session.diagnosticID ?? "nil") success=\(success) progress=\(tabs[index].progress) url=\(tabs[index].url ?? "nil")")
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .loading)
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .thumbnail)
    }

    func onProgressChange(session: GeckoSession, progress: Int) {
        guard let index = tabIndex(for: session) else {
            ShellDiagnostics.log("progress unknownSession=\(session.diagnosticID ?? "nil") progress=\(progress)")
            return
        }

        tabs[index].progress = Float(progress) / 100
        if progress == 0 || progress == 100 || progress % 25 == 0 {
            ShellDiagnostics.log("progress tab=\(tabs[index].id.uuidString) session=\(session.diagnosticID ?? "nil") progress=\(progress) url=\(tabs[index].url ?? "nil")")
        }
        delegate?.tabManager(self, didUpdateTabAt: index, reason: .loading)
    }
}

enum ShellDiagnostics {
    private static let queue = DispatchQueue(label: "com.codex.chatgpt.shell-diagnostics")
    private static let maxLogBytes: UInt64 = 1_000_000

    static func log(_ message: String) {
        let line = "[CHATGPT_SHELL_DIAG] \(timestamp()) \(message)"
        NSLog("%@", line)
        writeToFile(line)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func writeToFile(_ line: String) {
        queue.async {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
                  let data = (line + "\n").data(using: .utf8) else {
                return
            }

            let fileURL = documentsURL.appendingPathComponent("ChatGPTShellDiagnostics.log", isDirectory: false)
            rotateLogIfNeeded(at: fileURL)

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

    private static func rotateLogIfNeeded(at fileURL: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? UInt64,
              fileSize > maxLogBytes else {
            return
        }

        let rotatedURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("ChatGPTShellDiagnostics.previous.log", isDirectory: false)
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: fileURL, to: rotatedURL)
    }
}
