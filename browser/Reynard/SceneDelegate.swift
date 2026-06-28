//
//  SceneDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var enteredBackgroundAt: Date?
    private var backgroundSnapshotView: UIImageView?
    private let contentRecoveryDelay: TimeInterval = 60
    private let recoverySnapshotTimeout: TimeInterval = 12
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        let browserViewController = BrowserViewController()
        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = AppAppearanceController.userInterfaceStyle(for: Prefs.AppearanceSettings.appAppearance)
        window.rootViewController = browserViewController
        window.makeKeyAndVisible()
        self.window = window
        
        handleIncomingURLContexts(connectionOptions.urlContexts)
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handleIncomingURLContexts(URLContexts)
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {}
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        let backgroundDuration = enteredBackgroundAt.map { Date().timeIntervalSince($0) } ?? 0
        enteredBackgroundAt = nil
        let snapshotView = backgroundSnapshotView

        guard backgroundDuration >= contentRecoveryDelay,
              ShellConfig.current.target == .chatGPT,
              let browserViewController = window?.rootViewController as? BrowserViewController else {
            removeBackgroundSnapshot(snapshotView, animated: false)
            return
        }

        browserViewController.recoverContentAfterBackground { [weak self] in
            self?.removeBackgroundSnapshot(snapshotView, animated: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + recoverySnapshotTimeout) { [weak self] in
            self?.removeBackgroundSnapshot(snapshotView, animated: true)
        }
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        installBackgroundSnapshotIfNeeded()
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {}
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        enteredBackgroundAt = Date()
    }
    
    private func handleIncomingURLContexts(_ urlContexts: Set<UIOpenURLContext>) {
        guard let incomingURL = urlContexts.first?.url else {
            return
        }
        handleIncomingURL(incomingURL)
    }
    
    private func handleIncomingURL(_ incomingURL: URL) {
        guard let browserViewController = window?.rootViewController as? BrowserViewController,
              let resolvedURL = resolvedBrowserURL(from: incomingURL) else {
            return
        }
        
        DispatchQueue.main.async {
            browserViewController.loadViewIfNeeded()
            browserViewController.openExternalURL(resolvedURL)
        }
    }
    
    private func resolvedBrowserURL(from incomingURL: URL) -> URL? {
        guard let scheme = incomingURL.scheme?.lowercased() else {
            return nil
        }
        
        if scheme == "http" || scheme == "https" {
            return incomingURL
        }
        
        guard scheme == ShellConfig.urlScheme,
              let components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false),
              let encodedURL = components.queryItems?.first(where: { $0.name == "url" })?.value else {
            return nil
        }
        
        return URL(string: encodedURL)
    }

    private func installBackgroundSnapshotIfNeeded() {
        guard ShellConfig.current.target == .chatGPT,
              backgroundSnapshotView == nil,
              let window,
              window.bounds.width > 1,
              window.bounds.height > 1 else {
            return
        }

        window.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in
            window.layer.render(in: context.cgContext)
        }
        let snapshotView = UIImageView(image: image)
        snapshotView.frame = window.bounds
        snapshotView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        snapshotView.contentMode = .scaleToFill
        window.addSubview(snapshotView)

        backgroundSnapshotView = snapshotView
    }

    private func removeBackgroundSnapshot(_ snapshotView: UIImageView?, animated: Bool) {
        guard let snapshotView,
              backgroundSnapshotView === snapshotView else {
            return
        }
        backgroundSnapshotView = nil

        if animated {
            UIView.animate(withDuration: 0.15, animations: {
                snapshotView.alpha = 0
            }, completion: { _ in
                snapshotView.removeFromSuperview()
            })
        } else {
            snapshotView.removeFromSuperview()
        }
    }
}
