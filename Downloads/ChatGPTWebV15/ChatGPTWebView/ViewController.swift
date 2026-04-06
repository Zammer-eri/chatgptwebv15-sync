import UIKit
import WebKit

final class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, UIGestureRecognizerDelegate {
    private var webView: WKWebView!
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let sessionSyncService = SessionSyncService.shared
    private var isInitialLoadComplete = false
    private var syncInFlight = false
    private var lastRecoveryAttempt = Date.distantPast
    private var diagnosticsGesture: UILongPressGestureRecognizer?

    private let managedDomains = [
        "chatgpt.com",
        "auth.openai.com",
        "openai.com",
        "chat.openai.com"
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
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

        let viewportFix = WKUserScript(
            source: """
            (function() {
              var meta = document.querySelector('meta[name="viewport"]');
              if (!meta) {
                meta = document.createElement('meta');
                meta.name = 'viewport';
                document.head.appendChild(meta);
              }
              meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';

              var safeAreaStyle = document.getElementById('codex-safe-area-style');
              if (!safeAreaStyle) {
                safeAreaStyle = document.createElement('style');
                safeAreaStyle.id = 'codex-safe-area-style';
                safeAreaStyle.textContent = `
                  :root {
                    --codex-safe-area-top: calc(env(safe-area-inset-top, 0px) + 8px);
                  }

                  body {
                    padding-top: max(var(--codex-safe-area-top), 8px) !important;
                    box-sizing: border-box !important;
                  }

                  @supports selector(header) {
                    header,
                    nav,
                    [data-testid="page-header"],
                    [data-testid="page-layout-header"] {
                      padding-top: max(env(safe-area-inset-top, 0px), 0px) !important;
                    }
                  }
                `;
                document.head.appendChild(safeAreaStyle);
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
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = .systemBackground
        webView.isOpaque = false
        view.addSubview(webView)
    }

    private func configureSpinner() {
        activityIndicator.center = view.center
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
    }

    private func configureHiddenDiagnosticsGesture() {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleDiagnosticsLongPress(_:)))
        gesture.numberOfTouchesRequired = 2
        gesture.minimumPressDuration = 1.0
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        view.addGestureRecognizer(gesture)
        diagnosticsGesture = gesture
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
        syncAndApply(reason: .launch, forceRefresh: false, reloadAfterSync: false) { [weak self] in
            self?.loadChatGPT(forceReload: true)
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
        let message = """
        Desktop helper: \(helperStatus)
        Last synced bundle: \(sessionSyncService.lastKnownHash ?? "None")
        Current URL: \(lastURL)
        """

        let alert = UIAlertController(title: "Diagnostics", message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Sync Now", style: .default) { [weak self] _ in
            self?.syncAndApply(reason: .manual, forceRefresh: true, reloadAfterSync: true, completion: nil)
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

    @objc private func handleDiagnosticsLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else {
            return
        }

        showDiagnostics()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let location = touch.location(in: view)
        return location.y <= max(view.safeAreaInsets.top + 72, 120)
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
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: "Alert", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }
}
