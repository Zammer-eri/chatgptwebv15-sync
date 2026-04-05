import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigurationChange),
            name: .helperConfigurationDidChange,
            object: nil
        )

        window = UIWindow(frame: UIScreen.main.bounds)
        showAppropriateRoot()
        window?.makeKeyAndVisible()
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard HelperConfigurationStore.shared.importConfiguration(from: url) else {
            return false
        }

        showAppropriateRoot(forceMainApp: true)
        return true
    }

    @objc private func handleConfigurationChange() {
        showAppropriateRoot()
    }

    private func showAppropriateRoot(forceMainApp: Bool = false) {
        let shouldShowMainApp = forceMainApp ||
            HelperConfigurationStore.shared.configuration != nil ||
            LegacySessionStore.shared.hasLegacySession

        let nextRoot: UIViewController
        if shouldShowMainApp {
            nextRoot = ViewController()
        } else {
            nextRoot = PairingViewController()
        }

        window?.rootViewController = nextRoot
    }
}
