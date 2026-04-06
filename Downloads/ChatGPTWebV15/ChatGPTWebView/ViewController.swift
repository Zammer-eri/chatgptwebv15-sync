import AVFoundation
import Photos
import UIKit
import WebKit

final class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, UIGestureRecognizerDelegate {
    private var webView: WKWebView!
    private let topChromeView = UIView()
    private let refreshButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let sessionSyncService = SessionSyncService.shared
    private let lightSessionSettingsStore = LightSessionSettingsStore.shared
    private var isInitialLoadComplete = false
    private var syncInFlight = false
    private var lastRecoveryAttempt = Date.distantPast
    private var launchFallbackWorkItem: DispatchWorkItem?
    private let topOffsetTuning: CGFloat = 14.3
    private let initialPermissionPromptKey = "didRequestInitialSystemPermissions"
    private let managedDomains = [
        "chatgpt.com",
        "auth.openai.com",
        "openai.com",
        "chat.openai.com"
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureAudioSessionForVoiceFeatures()
        configureTopChrome()
        configureWebView()
        configureRefreshButton()
        configureSpinner()
        configureHiddenDiagnosticsGesture()
        observeForegroundEvents()
        observeAudioSessionNotifications()
        requestInitialPermissionsIfNeeded()
        bootstrapSession()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.suppressesIncrementalRendering = false

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        prefs.preferredContentMode = .mobile
        config.defaultWebpagePreferences = prefs

        let userContentController = WKUserContentController()

        let sidebarFix = WKUserScript(
            source: """
            try {
              localStorage.setItem('sidebar-expanded-state', 'false');
            } catch (error) {
              console.log('Sidebar state injection failed', error);
            }
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(sidebarFix)

        let lightSessionBootstrap = WKUserScript(
            source: lightSessionSettingsStore.makeBootstrapScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(lightSessionBootstrap)

        let viewportFix = WKUserScript(
            source: """
            (function() {
              var meta = document.querySelector('meta[name="viewport"]');
              if (!meta) {
                meta = document.createElement('meta');
                meta.name = 'viewport';
                document.head.appendChild(meta);
              }
              meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';

              var scrollStyle = document.getElementById('codex-scroll-fix-style');
              if (!scrollStyle) {
                scrollStyle = document.createElement('style');
                scrollStyle.id = 'codex-scroll-fix-style';
                scrollStyle.textContent = `
                  [data-radix-scroll-area-viewport],
                  [data-testid="conversation-turns"],
                  [data-testid="conversation-turns"] > div {
                    -webkit-overflow-scrolling: touch !important;
                    overscroll-behavior-y: auto !important;
                    overflow-anchor: none !important;
                  }
                `;
                document.head.appendChild(scrollStyle);
              }
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(viewportFix)

        config.userContentController = userContentController

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0)
        webView.isOpaque = true
        view.addSubview(webView)
    }

    private func configureTopChrome() {
        topChromeView.backgroundColor = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0)
        topChromeView.isUserInteractionEnabled = false
        view.addSubview(topChromeView)
    }

    private func configureRefreshButton() {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        refreshButton.setImage(UIImage(systemName: "arrow.clockwise", withConfiguration: symbolConfig), for: .normal)
        refreshButton.tintColor = .white
        refreshButton.backgroundColor = .clear
        refreshButton.addTarget(self, action: #selector(handleRefreshButtonTap), for: .touchUpInside)
        refreshButton.accessibilityLabel = "Refresh current page"
        refreshButton.accessibilityHint = "Reloads the current ChatGPT page and reapplies the current Light Session settings."
        view.addSubview(refreshButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let topInset = view.safeAreaInsets.top
        let adjustedTopInset = max(0, topInset - topOffsetTuning)
        topChromeView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: adjustedTopInset)
        webView.frame = CGRect(
            x: 0,
            y: adjustedTopInset,
            width: view.bounds.width,
            height: view.bounds.height - adjustedTopInset
        )
        let refreshSize: CGFloat = 28
        refreshButton.frame = CGRect(
            x: view.bounds.width - 86,
            y: adjustedTopInset + 18,
            width: refreshSize,
            height: refreshSize
        )
        activityIndicator.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    }

    private func configureSpinner() {
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
    }

    private func requestInitialPermissionsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: initialPermissionPromptKey) == false else {
            return
        }

        defaults.set(true, forKey: initialPermissionPromptKey)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            self.requestSystemPermissionsSequence()
        }
    }

    private func requestSystemPermissionsSequence() {
        requestMicrophonePermission { [weak self] in
            self?.requestCameraPermission {
                self?.requestPhotoLibraryPermission()
            }
        }
    }

    private func requestMicrophonePermission(completion: @escaping () -> Void) {
        let permission = AVAudioSession.sharedInstance().recordPermission
        guard permission == .undetermined else {
            completion()
            return
        }

        AVAudioSession.sharedInstance().requestRecordPermission { _ in
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    private func requestCameraPermission(completion: @escaping () -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .notDetermined else {
            completion()
            return
        }

        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    private func requestPhotoLibraryPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .notDetermined else {
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }
    }

    private func configureHiddenDiagnosticsGesture() {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleDiagnosticsLongPress(_:)))
        gesture.numberOfTouchesRequired = 2
        gesture.minimumPressDuration = 1.0
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        view.addGestureRecognizer(gesture)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    private func observeForegroundEvents() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForegroundSync),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    private func bootstrapSession() {
        activityIndicator.startAnimating()
        let fallback = DispatchWorkItem { [weak self] in
            self?.loadChatGPT(forceReload: true)
        }
        launchFallbackWorkItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: fallback)

        syncAndApply(reason: .launch, forceRefresh: false, reloadAfterSync: false) { [weak self] in
            self?.launchFallbackWorkItem?.cancel()
            self?.launchFallbackWorkItem = nil
            if self?.webView.url == nil {
                self?.loadChatGPT(forceReload: true)
            }
        }
    }

    @objc private func handleForegroundSync() {
        configureAudioSessionForVoiceFeatures()
        syncAndApply(reason: .foreground, forceRefresh: false, reloadAfterSync: false, completion: nil)
    }

    private func configureAudioSessionForVoiceFeatures() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try session.overrideOutputAudioPort(.speaker)
            try session.setActive(true, options: [])
        } catch {
            print("Audio session configuration failed: \(error.localizedDescription)")
        }
    }

    private func observeAudioSessionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else {
            return
        }

        if type == .ended {
            configureAudioSessionForVoiceFeatures()
        }
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        configureAudioSessionForVoiceFeatures()
    }

    private func syncAndApply(
        reason: SessionSyncReason,
        forceRefresh: Bool,
        reloadAfterSync: Bool,
        completion: (() -> Void)?
    ) {
        if syncInFlight {
            completion?()
            return
        }

        syncInFlight = true
        sessionSyncService.fetchSession(reason: reason, forceRefresh: forceRefresh) { [weak self] result in
            guard let self else { return }

            DispatchQueue.main.async {
                self.syncInFlight = false

                switch result {
                case .success(let envelope):
                    if let envelope, !envelope.cookies.isEmpty {
                        self.installCookies(envelope.cookies) {
                            if reloadAfterSync {
                                self.loadChatGPT(forceReload: true)
                            }
                            completion?()
                        }
                        return
                    }

                    if let legacyCookie = LegacySessionStore.shared.makeLegacyCookie() {
                        self.installCookies([legacyCookie]) {
                            if reloadAfterSync {
                                self.loadChatGPT(forceReload: true)
                            }
                            completion?()
                        }
                        return
                    }

                    completion?()

                case .failure:
                    if let legacyCookie = LegacySessionStore.shared.makeLegacyCookie() {
                        self.installCookies([legacyCookie]) {
                            if reloadAfterSync {
                                self.loadChatGPT(forceReload: true)
                            }
                            completion?()
                        }
                        return
                    }

                    completion?()
                }
            }
        }
    }

    private func installCookies(_ cookies: [BrowserCookiePayload], completion: @escaping () -> Void) {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        clearManagedCookies(in: cookieStore) {
            let validCookies = cookies.compactMap { $0.asHTTPCookie() }
            guard !validCookies.isEmpty else {
                completion()
                return
            }

            let group = DispatchGroup()
            for cookie in validCookies {
                group.enter()
                cookieStore.setCookie(cookie) {
                    group.leave()
                }
            }

            group.notify(queue: .main, execute: completion)
        }
    }

    private func clearManagedCookies(in cookieStore: WKHTTPCookieStore, completion: @escaping () -> Void) {
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self else {
                completion()
                return
            }

            let managedCookies = cookies.filter { cookie in
                self.managedDomains.contains { domain in
                    cookie.domain == domain || cookie.domain.hasSuffix(".\(domain)") || cookie.domain.hasSuffix(domain)
                }
            }

            guard !managedCookies.isEmpty else {
                completion()
                return
            }

            let group = DispatchGroup()
            for cookie in managedCookies {
                group.enter()
                cookieStore.delete(cookie) {
                    group.leave()
                }
            }

            group.notify(queue: .main, execute: completion)
        }
    }

    private func loadChatGPT(forceReload: Bool) {
        guard let url = URL(string: "https://chatgpt.com") else {
            return
        }

        if !forceReload, webView.url != nil {
            return
        }

        let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30)
        webView.load(request)
    }

    private func shouldAttemptRecovery(for url: URL?) -> Bool {
        guard let url else {
            return false
        }

        let absoluteString = url.absoluteString.lowercased()
        if absoluteString.contains("auth.openai.com") {
            return true
        }

        return absoluteString.contains("/auth/login") || absoluteString.contains("/u/login")
    }

    private func attemptRecoveryIfNeeded(for url: URL?) {
        guard HelperConfigurationStore.shared.configuration != nil else {
            return
        }

        guard shouldAttemptRecovery(for: url) else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastRecoveryAttempt) > 8 else {
            return
        }

        lastRecoveryAttempt = now
        syncAndApply(reason: .loggedOut, forceRefresh: true, reloadAfterSync: true, completion: nil)
    }

    @objc private func showDiagnostics() {
        let helperStatus = HelperConfigurationStore.shared.configuration.map { "\($0.host):\($0.port)" } ?? "Not paired"
        let lastURL = webView.url?.absoluteString ?? "No page loaded"
        let lightSessionSummary = lightSessionSettingsStore.settings.summaryText
        let message = """
        Desktop helper: \(helperStatus)
        Light Session: \(lightSessionSummary)
        Last synced bundle: \(sessionSyncService.lastKnownHash ?? "None")
        Current URL: \(lastURL)
        """

        let alert = UIAlertController(title: "Diagnostics", message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Sync Now", style: .default) { [weak self] _ in
            self?.syncAndApply(reason: .manual, forceRefresh: true, reloadAfterSync: true, completion: nil)
        })
        alert.addAction(UIAlertAction(title: "Refresh Current Page", style: .default) { [weak self] _ in
            self?.refreshCurrentPage()
        })
        alert.addAction(UIAlertAction(title: "Re-pair Desktop", style: .default) { [weak self] _ in
            let pairing = PairingViewController()
            pairing.modalPresentationStyle = .formSheet
            self?.present(pairing, animated: true)
        })
        alert.addAction(UIAlertAction(title: "Performance Settings", style: .default) { [weak self] _ in
            self?.presentLightSessionSettings()
        })
        alert.addAction(UIAlertAction(title: "Clear Local Session", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.clearManagedCookies(in: self.webView.configuration.websiteDataStore.httpCookieStore) {
                self.sessionSyncService.clearKnownHash()
                LegacySessionStore.shared.clear()
                self.loadChatGPT(forceReload: true)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: 60, width: 1, height: 1)
        }

        present(alert, animated: true)
    }

    private func presentLightSessionSettings() {
        let settingsViewController = LightSessionSettingsViewController(settings: lightSessionSettingsStore.settings)
        settingsViewController.modalPresentationStyle = .formSheet
        settingsViewController.onSave = { [weak self] settings in
            self?.applyLightSessionSettings(settings, reloadCurrentPage: true)
        }
        present(settingsViewController, animated: true)
    }

    private func applyLightSessionSettings(_ settings: LightSessionSettings, reloadCurrentPage: Bool) {
        lightSessionSettingsStore.save(settings)
        webView.evaluateJavaScript(lightSessionSettingsStore.makeRuntimeUpdateScript(), completionHandler: nil)

        guard reloadCurrentPage else {
            return
        }

        refreshCurrentPage()
    }

    private func refreshCurrentPage() {
        if webView.url != nil {
            webView.reloadFromOrigin()
        } else {
            loadChatGPT(forceReload: true)
        }
    }

    @objc private func handleDiagnosticsLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else {
            return
        }

        showDiagnostics()
    }

    @objc private func handleRefreshButtonTap() {
        refreshCurrentPage()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activityIndicator.startAnimating()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
        isInitialLoadComplete = true

        let voiceBind = """
        setTimeout(() => {
          try {
            const voiceBtn = document.querySelector('[aria-label="Hold to speak"]');
            const micBtn = document.querySelector('[aria-label="Start voice input"]');
            if (voiceBtn && micBtn) {
              voiceBtn.addEventListener('mousedown', () => micBtn.click());
            }
          } catch (error) {
            console.log('Mic bind failed', error);
          }
        }, 3000);
        """
        webView.evaluateJavaScript(voiceBind, completionHandler: nil)
        attemptRecoveryIfNeeded(for: webView.url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        print("Navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        print("Provisional navigation failed: \(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        switch type {
        case .camera:
            handleCameraDecision(decisionHandler)
        case .microphone:
            handleMicrophoneDecision(decisionHandler)
        case .cameraAndMicrophone:
            handleCombinedMediaDecision(decisionHandler)
        @unknown default:
            decisionHandler(.prompt)
        }
    }

    private func handleCameraDecision(_ decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        configureAudioSessionForVoiceFeatures()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            decisionHandler(.grant)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    decisionHandler(granted ? .grant : .deny)
                }
            }
        default:
            decisionHandler(.deny)
        }
    }

    private func handleMicrophoneDecision(_ decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        configureAudioSessionForVoiceFeatures()
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            decisionHandler(.grant)
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    decisionHandler(granted ? .grant : .deny)
                }
            }
        default:
            decisionHandler(.deny)
        }
    }

    private func handleCombinedMediaDecision(_ decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        handleCameraDecision { [weak self] cameraDecision in
            guard cameraDecision == .grant else {
                decisionHandler(.deny)
                return
            }

            self?.handleMicrophoneDecision { microphoneDecision in
                decisionHandler(microphoneDecision == .grant ? .grant : .deny)
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: "Alert", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }
}
