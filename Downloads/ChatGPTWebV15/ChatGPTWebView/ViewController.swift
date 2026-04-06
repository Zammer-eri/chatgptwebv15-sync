import UIKit
import WebKit

final class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private let topChromeView = UIView()
    private let topTapZoneView = UIView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let refreshControl = UIRefreshControl()
    private let sessionSyncService = SessionSyncService.shared
    private let lightSessionSettingsStore = LightSessionSettingsStore.shared
    private var syncInFlight = false
    private var lastRecoveryAttempt = Date.distantPast
    private var launchFallbackWorkItem: DispatchWorkItem?
    private let topOffsetTuning: CGFloat = 14.3
    private let managedDomains = [
        "chatgpt.com",
        "auth.openai.com",
        "openai.com",
        "chat.openai.com"
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureTopChrome()
        configureWebView()
        configureSpinner()
        configureHiddenDiagnosticsGesture()
        observeForegroundEvents()
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
                  html,
                  body,
                  main,
                  nav,
                  aside,
                  section,
                  article,
                  [role="main"],
                  [data-radix-scroll-area-viewport] {
                    scroll-snap-type: none !important;
                    scroll-behavior: auto !important;
                    overscroll-behavior-y: auto !important;
                    overflow-anchor: none !important;
                  }

                  * {
                    scroll-snap-align: none !important;
                    scroll-snap-stop: normal !important;
                  }

                  a,
                  button,
                  input,
                  label,
                  select,
                  summary,
                  textarea,
                  [role="button"],
                  [tabindex] {
                    touch-action: manipulation !important;
                    -webkit-tap-highlight-color: rgba(0, 0, 0, 0) !important;
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
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_6_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.delaysContentTouches = false
        webView.scrollView.canCancelContentTouches = true
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        webView.backgroundColor = .systemBackground
        webView.isOpaque = false
        view.addSubview(webView)
    }

    private func configureTopChrome() {
        topChromeView.backgroundColor = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0)
        topChromeView.isUserInteractionEnabled = false
        view.addSubview(topChromeView)

        topTapZoneView.backgroundColor = .clear
        topTapZoneView.isUserInteractionEnabled = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTopChromeTap))
        topTapZoneView.addGestureRecognizer(tapGesture)
        view.addSubview(topTapZoneView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let topInset = view.safeAreaInsets.top
        let adjustedTopInset = max(0, topInset - topOffsetTuning)
        let topMaskHeight: CGFloat
        let topTapHeight: CGFloat

        if view.bounds.width > view.bounds.height {
            topMaskHeight = max(adjustedTopInset, 16)
            topTapHeight = 30
        } else {
            topMaskHeight = adjustedTopInset
            topTapHeight = max(adjustedTopInset + 10, 24)
        }

        topChromeView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: topMaskHeight)
        topTapZoneView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: topTapHeight)
        webView.frame = CGRect(
            x: 0,
            y: adjustedTopInset,
            width: view.bounds.width,
            height: view.bounds.height - adjustedTopInset
        )
        activityIndicator.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    }

    private func configureSpinner() {
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
    }

    private func configureHiddenDiagnosticsGesture() {
        let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleDiagnosticsEdgeSwipe(_:)))
        gesture.edges = .right
        gesture.cancelsTouchesInView = false
        gesture.minimumNumberOfTouches = 1
        gesture.maximumNumberOfTouches = 1
        view.addGestureRecognizer(gesture)
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
        syncAndApply(reason: .foreground, forceRefresh: false, reloadAfterSync: false, completion: nil)
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
        alert.addAction(UIAlertAction(title: "Light Session Settings", style: .default) { [weak self] _ in
            self?.presentLightSessionSettings()
        })
        alert.addAction(UIAlertAction(title: "Re-pair Desktop", style: .default) { [weak self] _ in
            let pairing = PairingViewController()
            pairing.modalPresentationStyle = .formSheet
            self?.present(pairing, animated: true)
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
            self?.applyLightSessionSettings(settings)
        }
        present(settingsViewController, animated: true)
    }

    private func applyLightSessionSettings(_ settings: LightSessionSettings) {
        lightSessionSettingsStore.save(settings)
        webView.evaluateJavaScript(lightSessionSettingsStore.makeRuntimeUpdateScript(), completionHandler: nil)
        refreshCurrentPage()
    }

    private func refreshCurrentPage() {
        if webView.url != nil {
            webView.reloadFromOrigin()
        } else {
            loadChatGPT(forceReload: true)
        }
    }

    private func scrollCurrentPageToTop() {
        let scrollScript = """
        (function() {
          const candidates = [
            document.querySelector('[data-radix-scroll-area-viewport]'),
            document.querySelector('[data-testid="conversation-turns"]'),
            document.querySelector('[role="main"]'),
            document.scrollingElement,
            document.documentElement,
            document.body
          ].filter(Boolean);

          for (const candidate of candidates) {
            try {
              if (candidate && typeof candidate.scrollTo === 'function') {
                candidate.scrollTo({ top: 0, left: 0, behavior: 'smooth' });
              } else if (candidate) {
                candidate.scrollTop = 0;
              }
            } catch (error) {}
          }

          try {
            window.scrollTo({ top: 0, left: 0, behavior: 'smooth' });
          } catch (error) {
            window.scrollTo(0, 0);
          }
        })();
        """

        webView.evaluateJavaScript(scrollScript, completionHandler: nil)
        webView.scrollView.setContentOffset(CGPoint(x: 0, y: -webView.scrollView.adjustedContentInset.top), animated: true)
    }

    private func isNearTop() -> Bool {
        webView.scrollView.contentOffset.y <= (-webView.scrollView.adjustedContentInset.top + 24)
    }

    @objc private func handlePullToRefresh() {
        refreshCurrentPage()
    }

    @objc private func handleTopChromeTap() {
        if isNearTop() {
            refreshCurrentPage()
        } else {
            scrollCurrentPageToTop()
        }
    }

    @objc private func handleDiagnosticsEdgeSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended || gesture.state == .recognized else {
            return
        }

        let translation = gesture.translation(in: view)
        guard translation.x < -24 else {
            return
        }

        showDiagnostics()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activityIndicator.startAnimating()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
        refreshControl.endRefreshing()
        attemptRecoveryIfNeeded(for: webView.url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        refreshControl.endRefreshing()
        print("Navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        refreshControl.endRefreshing()
        print("Provisional navigation failed: \(error.localizedDescription)")
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
