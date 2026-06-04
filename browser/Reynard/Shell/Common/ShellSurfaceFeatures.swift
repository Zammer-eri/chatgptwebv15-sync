//
//  ShellSurfaceFeatures.swift
//  Reynard
//
//  Shell-only gestures and utility UI, isolated from the upstream browser UI.
//

import GeckoView
import ObjectiveC
import UIKit

private enum ShellSurfaceAssociatedKeys {
    static var utilityPanel = 0
    static var utilityPanelVisible = 0
    static var recoveryOverlay = 0
    static var recoveryPill = 0
    static var recoveryLabel = 0
    static var recoveryVisible = 0
    static var recoveryToken = 0
    static var recoveryShownAt = 0
    static var keyboardVisible = 0
}

private enum ShellTimeAwareSettings {
    static let enabledKey = "ReynardShell.TimeAware.enabled"
    static let timeZoneKey = "ReynardShell.TimeAware.timeZone"
    static let recentTimeZonesKey = "ReynardShell.TimeAware.recentTimeZones"
    static let maxRecentTimeZoneCount = 4

    static var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: enabledKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            UserDefaults.standard.synchronize()
        }
    }

    static var timeZoneIdentifier: String? {
        get {
            let value = UserDefaults.standard.string(forKey: timeZoneKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        set {
            let value = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.isEmpty {
                UserDefaults.standard.removeObject(forKey: timeZoneKey)
            } else {
                UserDefaults.standard.set(value, forKey: timeZoneKey)
            }
            UserDefaults.standard.synchronize()
        }
    }

    static var recentTimeZoneIdentifiers: [String] {
        guard let values = UserDefaults.standard.stringArray(forKey: recentTimeZonesKey) else {
            return []
        }

        var seen = Set<String>()
        return values.compactMap { value in
            let identifier = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty,
                  TimeZone(identifier: identifier) != nil,
                  !seen.contains(identifier) else {
                return nil
            }
            seen.insert(identifier)
            return identifier
        }
    }

    static func rememberTimeZoneIdentifier(_ identifier: String?) {
        guard let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty,
              TimeZone(identifier: identifier) != nil,
              identifier != TimeZone.current.identifier else {
            return
        }

        let values = ([identifier] + recentTimeZoneIdentifiers.filter { $0 != identifier })
            .prefix(maxRecentTimeZoneCount)
        UserDefaults.standard.set(Array(values), forKey: recentTimeZonesKey)
        UserDefaults.standard.synchronize()
    }
}

extension BrowserViewController {
    func configureShellSurfaceFeatures() {
        guard ShellConfig.current.target != .browser else {
            return
        }

        if ShellConfig.current.features.usesUtilityPanel {
            configureShellRecoveryOverlay()
            configureShellUtilityPanel()
        }

        if ShellConfig.current.features.usesShellGestures {
            configureShellGestures()
        }
    }

    private var shellUtilityPanel: ShellUtilityPanelView {
        if let panel = objc_getAssociatedObject(self, &ShellSurfaceAssociatedKeys.utilityPanel) as? ShellUtilityPanelView {
            return panel
        }

        let panel = ShellUtilityPanelView()
        objc_setAssociatedObject(self, &ShellSurfaceAssociatedKeys.utilityPanel, panel, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return panel
    }

    private var shellUtilityPanelVisible: Bool {
        get {
            (objc_getAssociatedObject(self, &ShellSurfaceAssociatedKeys.utilityPanelVisible) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &ShellSurfaceAssociatedKeys.utilityPanelVisible,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    private var shellRecoveryOverlay: UIVisualEffectView {
        if let overlay = objc_getAssociatedObject(self, &ShellSurfaceAssociatedKeys.recoveryOverlay) as? UIVisualEffectView {
            return overlay
        }

        let overlay = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        objc_setAssociatedObject(self, &ShellSurfaceAssociatedKeys.recoveryOverlay, overlay, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return overlay
    }

    private var shellRecoveryPill: UIVisualEffectView {
        if let pill = objc_getAssociatedObject(self, &ShellSurfaceAssociatedKeys.recoveryPill) as? UIVisualEffectView {
            return pill
        }

        let pill = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        objc_setAssociatedObject(self, &ShellSurfaceAssociatedKeys.recoveryPill, pill, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return pill
    }

    private var shellRecoveryLabel: UILabel {
        if let label = objc_getAssociatedObject(self, &ShellSurfaceAssociatedKeys.recoveryLabel) as? UILabel {
            return label
        }

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Refreshing"
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        objc_setAssociatedObject(self, &ShellSurfaceAssociatedKeys.recoveryLabel, label, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return label
    }

    private var isShellRecoveryOverlayVisible: Bool {
        get {
            (objc_getAssociatedObject(self, &ShellSurfaceAssociatedKeys.recoveryVisible) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &ShellSurfaceAssociatedKeys.recoveryVisible,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    private var shellRecoveryOverlayToken: UUID {
        get {
            (objc_getAssociatedObject(self, &ShellSurfaceAssociatedKeys.recoveryToken) as? UUID) ?? UUID()
        }
        set {
            objc_setAssociatedObject(self, &ShellSurfaceAssociatedKeys.recoveryToken, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private var shellRecoveryOverlayShownAt: Date? {
        get {
            objc_getAssociatedObject(self, &ShellSurfaceAssociatedKeys.recoveryShownAt) as? Date
        }
        set {
            objc_setAssociatedObject(self, &ShellSurfaceAssociatedKeys.recoveryShownAt, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private var isShellKeyboardVisible: Bool {
        get {
            (objc_getAssociatedObject(self, &ShellSurfaceAssociatedKeys.keyboardVisible) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &ShellSurfaceAssociatedKeys.keyboardVisible,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    private func configureShellGestures() {
        let reloadGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleShellReloadGesture(_:)))
        reloadGesture.edges = .right
        reloadGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(reloadGesture)

        let utilityGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleShellUtilityPanelGesture(_:)))
        utilityGesture.edges = .left
        utilityGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(utilityGesture)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shellKeyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shellKeyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    private func configureShellRecoveryOverlay() {
        let overlay = shellRecoveryOverlay
        let pill = shellRecoveryPill
        let label = shellRecoveryLabel

        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.alpha = 0
        overlay.isHidden = true
        overlay.isUserInteractionEnabled = false

        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.layer.cornerCurve = .continuous
        pill.layer.cornerRadius = 18
        pill.clipsToBounds = true
        pill.contentView.addSubview(label)

        overlay.contentView.addSubview(pill)
        view.addSubview(overlay)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pill.centerXAnchor.constraint(equalTo: overlay.contentView.centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: overlay.contentView.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: pill.contentView.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: pill.contentView.trailingAnchor, constant: -18),
            label.topAnchor.constraint(equalTo: pill.contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: pill.contentView.bottomAnchor, constant: -10),
        ])
    }

    private func configureShellUtilityPanel() {
        let panel = shellUtilityPanel
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.onClose = { [weak self] in
            self?.setShellUtilityPanelVisible(false, animated: true)
        }
        panel.onSaveUserAgent = { [weak self] useAndroidUserAgent in
            guard let self else {
                return
            }

            Prefs.CompatibilitySettings.useAndroidUserAgent = useAndroidUserAgent
            self.setShellUtilityPanelVisible(false, animated: true)
            self.reloadSelectedTabWithCurrentSettings()
        }
        panel.onSaveTimeAware = { [weak self] enabled, timeZoneIdentifier in
            guard let self else {
                return
            }

            ShellTimeAwareSettings.isEnabled = enabled
            ShellTimeAwareSettings.timeZoneIdentifier = timeZoneIdentifier
            self.setShellUtilityPanelVisible(false, animated: true)
            self.reloadSelectedTabForRuntimeSettings()
        }

        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        panel.isHidden = true
        panel.alpha = 0
    }

    @objc private func handleShellReloadGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended || gesture.state == .recognized else {
            return
        }

        guard gesture.translation(in: view).x < -24 else {
            return
        }

        if isShellKeyboardVisible {
            dismissKeyboard()
            return
        }

        guard let tab = tabManager.selectedTab else {
            return
        }

        setShellRecoveryOverlayVisible(true, animated: true)
        reloadTabAfterClearingAppCache(tab)
    }

    @objc private func handleShellUtilityPanelGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended || gesture.state == .recognized else {
            return
        }

        guard gesture.translation(in: view).x > 24 else {
            return
        }

        setShellUtilityPanelVisible(true, animated: true)
    }

    @objc private func shellKeyboardWillChangeFrame(_ notification: Notification) {
        guard let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }

        let frame = view.convert(frameValue.cgRectValue, from: nil)
        isShellKeyboardVisible = frame.minY < view.bounds.maxY
    }

    @objc private func shellKeyboardWillHide(_: Notification) {
        isShellKeyboardVisible = false
    }

    private func reloadTabAfterClearingAppCache(_ tab: Tab) {
        tab.session.stop()
        clearAppCacheForReload { [weak self, weak tab] in
            guard let self,
                  let tab else {
                return
            }
            self.tabManager.recover(tab)
            self.hideShellRecoveryOverlayAfterSettleDelay()
        }
    }

    private func clearAppCacheForReload(completion: @escaping () -> Void) {
        Task {
            await clearGeckoSiteDataForReload()
            await clearLocalAppCacheForReload()

            await MainActor.run {
                completion()
            }
        }
    }

    private func clearGeckoSiteDataForReload() async {
        guard ShellConfig.current.target == .chatGPT else {
            return
        }

        let flags = GeckoRuntime.ClearDataFlags.networkCache |
            GeckoRuntime.ClearDataFlags.imageCache |
            GeckoRuntime.ClearDataFlags.domStorages

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await GeckoRuntime.clearBaseDomainData("chatgpt.com", flags: flags)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }

            await group.next()
            group.cancelAll()
        }
    }

    private func clearLocalAppCacheForReload() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default
                let cacheURLs = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
                let temporaryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

                URLCache.shared.removeAllCachedResponses()

                for directoryURL in cacheURLs + [temporaryURL] {
                    guard let contents = try? fileManager.contentsOfDirectory(
                        at: directoryURL,
                        includingPropertiesForKeys: nil,
                        options: [.skipsSubdirectoryDescendants]
                    ) else {
                        continue
                    }

                    for itemURL in contents {
                        try? fileManager.removeItem(at: itemURL)
                    }
                }

                continuation.resume()
            }
        }
    }

    private func reloadSelectedTabWithCurrentSettings() {
        guard let tab = tabManager.selectedTab else {
            return
        }

        let url = tab.url ?? ShellConfig.current.defaultURL?.absoluteString ?? "about:blank"
        tab.session.updateSettings(
            GeckoSessionController.shared.sessionSettings(for: url, tabID: tab.id)
        )
        tabManager.reload(tab)
    }

    private func reloadSelectedTabForRuntimeSettings() {
        guard let tab = tabManager.selectedTab else {
            return
        }

        let url = tab.url ?? ShellConfig.current.defaultURL?.absoluteString ?? "about:blank"
        tab.session.updateSettings(
            GeckoSessionController.shared.sessionSettings(for: url, tabID: tab.id)
        )
        tab.session.load(url, flags: GeckoSessionLoadFlags.bypassCache | GeckoSessionLoadFlags.replaceHistory)
    }

    private func setShellRecoveryOverlayVisible(_ visible: Bool, animated: Bool) {
        let overlay = shellRecoveryOverlay
        let pill = shellRecoveryPill
        guard visible != isShellRecoveryOverlayVisible || overlay.isHidden else {
            return
        }

        isShellRecoveryOverlayVisible = visible
        if visible {
            shellRecoveryOverlayShownAt = Date()
            overlay.isHidden = false
            view.bringSubviewToFront(overlay)
            pill.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            let token = UUID()
            shellRecoveryOverlayToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                guard let self,
                      self.shellRecoveryOverlayToken == token,
                      self.isShellRecoveryOverlayVisible else {
                    return
                }
                self.setShellRecoveryOverlayVisible(false, animated: true)
            }
        }

        let animations = {
            overlay.alpha = visible ? 1 : 0
            pill.transform = visible ? .identity : CGAffineTransform(scaleX: 0.98, y: 0.98)
        }
        let completion: (Bool) -> Void = { _ in
            if !visible {
                overlay.isHidden = true
                self.shellRecoveryOverlayShownAt = nil
            }
        }

        if animated {
            UIView.animate(
                withDuration: visible ? 0.18 : 0.22,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: animations,
                completion: completion
            )
        } else {
            animations()
            completion(true)
        }
    }

    private func hideShellRecoveryOverlayAfterSettleDelay() {
        let minimumVisibleDuration: TimeInterval = 2.0
        let elapsed = shellRecoveryOverlayShownAt.map { Date().timeIntervalSince($0) } ?? minimumVisibleDuration
        let delay = max(0, minimumVisibleDuration - elapsed)
        let token = shellRecoveryOverlayToken

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.shellRecoveryOverlayToken == token,
                  self.isShellRecoveryOverlayVisible else {
                return
            }
            self.setShellRecoveryOverlayVisible(false, animated: true)
        }
    }

    private func setShellUtilityPanelVisible(_ visible: Bool, animated: Bool) {
        let panel = shellUtilityPanel
        shellUtilityPanelVisible = visible
        panel.syncControls()
        if visible {
            panel.showHome(animated: false)
        }

        panel.isHidden = false
        view.bringSubviewToFront(panel)
        panel.prepareForVisibilityChange(visible)

        let animations = {
            panel.alpha = visible ? 1 : 0
            panel.applyVisibleState(visible)
        }
        let completion: (Bool) -> Void = { _ in
            panel.isHidden = !visible
        }

        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut], animations: animations, completion: completion)
        } else {
            animations()
            completion(true)
        }
    }
}

private final class TimeZoneOptionButton: UIButton {
    var timeZoneIdentifier: String?
}

private final class TimeZoneNavigationRow: UIControl {
    var value: String?
}

private final class ShellUtilityPanelView: UIView, UIGestureRecognizerDelegate {
    var onClose: (() -> Void)?
    var onSaveUserAgent: ((Bool) -> Void)?
    var onSaveTimeAware: ((Bool, String?) -> Void)?

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let dimView = UIView()
    private let cardView = UIView()
    private let homeContent = UIView()
    private let downloadsContent = UIView()
    private let timeAwareContent = UIView()
    private let timeZoneListContent = UIView()
    private let timeAwareScrollView = UIScrollView()
    private let homeStackView = UIStackView()
    private let timeAwareStackView = UIStackView()
    private let timeZoneListStackView = UIStackView()
    private let timeZoneListTitleLabel = UILabel()
    private let timeAwareRow = UIControl()
    private let downloadsRow = UIControl()
    private let androidUASwitch = UISwitch()
    private let timeAwareEnabledSwitch = UISwitch()
    private let timeZoneButton = UIButton(type: .system)
    private let timeAwareHintLabel = UILabel()
    private let timeAwareSaveButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private var cardSideConstraint: NSLayoutConstraint?
    private var cardHeightConstraint: NSLayoutConstraint?
    private var saveButtonHeightConstraint: NSLayoutConstraint?
    private var timeAwareSaveButtonHeightConstraint: NSLayoutConstraint?
    private var savedAndroidUserAgent = false
    private var savedTimeAwareEnabled = true
    private var savedTimeAwareTimeZoneIdentifier: String?
    private var draftTimeAwareTimeZoneIdentifier: String?
    private var timeZoneListMode = TimeZoneListMode.suggestions
    private let showsTimeAwareSettings = ShellConfig.current.target == .chatGPT
    private var activePanel: Panel = .home

    private enum Panel {
        case home
        case timeAware
        case timeZoneList
        case downloads
    }

    private enum TimeZoneListMode {
        case suggestions
        case regions
        case region(String)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        blurView.translatesAutoresizingMaskIntoConstraints = false
        dimView.translatesAutoresizingMaskIntoConstraints = false
        cardView.translatesAutoresizingMaskIntoConstraints = false
        homeContent.translatesAutoresizingMaskIntoConstraints = false
        downloadsContent.translatesAutoresizingMaskIntoConstraints = false
        timeAwareContent.translatesAutoresizingMaskIntoConstraints = false
        timeZoneListContent.translatesAutoresizingMaskIntoConstraints = false

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.24)

        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 22
        cardView.layer.cornerCurve = .continuous
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.25
        cardView.layer.shadowRadius = 28
        cardView.layer.shadowOffset = CGSize(width: 0, height: 12)
        cardView.clipsToBounds = true

        addSubview(blurView)
        addSubview(dimView)
        addSubview(cardView)
        cardView.addSubview(homeContent)
        cardView.addSubview(timeAwareContent)
        cardView.addSubview(timeZoneListContent)
        cardView.addSubview(downloadsContent)
        cardSideConstraint = cardView.widthAnchor.constraint(equalToConstant: 280)
        cardHeightConstraint = cardView.heightAnchor.constraint(equalToConstant: 188)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),

            dimView.topAnchor.constraint(equalTo: topAnchor),
            dimView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: trailingAnchor),

            cardView.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: centerYAnchor),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 18),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18),
            cardSideConstraint!,
            cardHeightConstraint!,

            homeContent.topAnchor.constraint(equalTo: cardView.topAnchor),
            homeContent.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            homeContent.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            homeContent.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            timeAwareContent.topAnchor.constraint(equalTo: cardView.topAnchor),
            timeAwareContent.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            timeAwareContent.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            timeAwareContent.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            timeZoneListContent.topAnchor.constraint(equalTo: cardView.topAnchor),
            timeZoneListContent.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            timeZoneListContent.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            timeZoneListContent.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            downloadsContent.topAnchor.constraint(equalTo: cardView.topAnchor),
            downloadsContent.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            downloadsContent.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            downloadsContent.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
        ])

        configureHomeContent()
        if showsTimeAwareSettings {
            configureTimeAwareContent()
            configureTimeZoneListContent()
        }
        configureDownloadsContent()
        timeAwareContent.isHidden = true
        timeZoneListContent.isHidden = true
        downloadsContent.isHidden = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)

        syncControls()
        showHome(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let availableWidth = max(220, bounds.width - 56)
        let availableHeight = max(220, bounds.height - safeAreaInsets.top - safeAreaInsets.bottom - 80)
        cardSideConstraint?.constant = min(336, min(availableWidth, availableHeight))
        updateCardHeight(animated: false)
    }

    func syncControls() {
        savedAndroidUserAgent = Prefs.CompatibilitySettings.useAndroidUserAgent
        androidUASwitch.isOn = savedAndroidUserAgent
        if showsTimeAwareSettings {
            savedTimeAwareEnabled = ShellTimeAwareSettings.isEnabled
            savedTimeAwareTimeZoneIdentifier = ShellTimeAwareSettings.timeZoneIdentifier
            draftTimeAwareTimeZoneIdentifier = savedTimeAwareTimeZoneIdentifier
            timeAwareEnabledSwitch.isOn = savedTimeAwareEnabled
            updateTimeZoneButton()
        }
        updateSaveButton(animated: false)
        if showsTimeAwareSettings {
            updateTimeAwareSaveButton(animated: false)
        }
    }

    func prepareForVisibilityChange(_ visible: Bool) {
        if visible {
            cardView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }
    }

    func applyVisibleState(_ visible: Bool) {
        cardView.transform = visible ? .identity : CGAffineTransform(scaleX: 0.96, y: 0.96)
    }

    func showHome(animated: Bool) {
        let previous = contentView(for: activePanel)
        activePanel = .home
        switchContent(to: homeContent, from: previous, animated: animated)
        updateCardHeight(animated: animated)
    }

    func showDownloads(animated: Bool) {
        let previous = contentView(for: activePanel)
        activePanel = .downloads
        switchContent(to: downloadsContent, from: previous, animated: animated)
        updateCardHeight(animated: animated)
    }

    func showTimeAware(animated: Bool) {
        let previous = contentView(for: activePanel)
        activePanel = .timeAware
        switchContent(to: timeAwareContent, from: previous, animated: animated)
        updateCardHeight(animated: animated)
    }

    func showTimeZoneList(animated: Bool) {
        timeZoneListMode = .suggestions
        refreshTimeZoneList(animated: false)
        let previous = contentView(for: activePanel)
        activePanel = .timeZoneList
        switchContent(to: timeZoneListContent, from: previous, animated: animated)
        updateCardHeight(animated: animated)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else {
            return true
        }
        return !touchedView.isDescendant(of: cardView)
    }

    private func configureHomeContent() {
        homeStackView.translatesAutoresizingMaskIntoConstraints = false
        homeStackView.axis = .vertical
        homeStackView.spacing = 12

        let uaLabel = UILabel()
        uaLabel.text = "Android User Agent"
        uaLabel.font = .systemFont(ofSize: 17, weight: .medium)
        uaLabel.translatesAutoresizingMaskIntoConstraints = false

        androidUASwitch.addTarget(self, action: #selector(androidUASwitchChanged), for: .valueChanged)
        androidUASwitch.translatesAutoresizingMaskIntoConstraints = false

        let uaRow = UIView()
        uaRow.translatesAutoresizingMaskIntoConstraints = false
        uaRow.backgroundColor = .tertiarySystemBackground
        uaRow.layer.cornerRadius = 14
        uaRow.layer.cornerCurve = .continuous
        uaRow.addSubview(uaLabel)
        uaRow.addSubview(androidUASwitch)

        timeAwareRow.translatesAutoresizingMaskIntoConstraints = false
        timeAwareRow.backgroundColor = .tertiarySystemBackground
        timeAwareRow.layer.cornerRadius = 14
        timeAwareRow.layer.cornerCurve = .continuous
        timeAwareRow.addTarget(self, action: #selector(timeAwareTapped), for: .touchUpInside)

        let timeAwareLabel = UILabel()
        timeAwareLabel.text = "Time Context"
        timeAwareLabel.font = .systemFont(ofSize: 17, weight: .medium)
        timeAwareLabel.translatesAutoresizingMaskIntoConstraints = false

        let timeAwareChevronView = UIImageView(image: UIImage(systemName: "chevron.right"))
        timeAwareChevronView.translatesAutoresizingMaskIntoConstraints = false
        timeAwareChevronView.tintColor = .secondaryLabel
        timeAwareChevronView.contentMode = .scaleAspectFit
        timeAwareRow.addSubview(timeAwareLabel)
        timeAwareRow.addSubview(timeAwareChevronView)

        downloadsRow.translatesAutoresizingMaskIntoConstraints = false
        downloadsRow.backgroundColor = .tertiarySystemBackground
        downloadsRow.layer.cornerRadius = 14
        downloadsRow.layer.cornerCurve = .continuous
        downloadsRow.addTarget(self, action: #selector(downloadsTapped), for: .touchUpInside)

        let downloadsLabel = UILabel()
        downloadsLabel.text = "Downloads"
        downloadsLabel.font = .systemFont(ofSize: 17, weight: .medium)
        downloadsLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevronView = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.tintColor = .secondaryLabel
        chevronView.contentMode = .scaleAspectFit
        downloadsRow.addSubview(downloadsLabel)
        downloadsRow.addSubview(chevronView)

        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.setTitle("Save", for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        saveButton.backgroundColor = .label
        saveButton.tintColor = .systemBackground
        saveButton.layer.cornerRadius = 14
        saveButton.layer.cornerCurve = .continuous
        saveButton.addTarget(self, action: #selector(saveUserAgentTapped), for: .touchUpInside)
        saveButton.isEnabled = false
        saveButton.alpha = 0
        saveButtonHeightConstraint = saveButton.heightAnchor.constraint(equalToConstant: 0)

        homeStackView.addArrangedSubview(uaRow)
        if showsTimeAwareSettings {
            homeStackView.addArrangedSubview(timeAwareRow)
        }
        homeStackView.addArrangedSubview(downloadsRow)
        homeStackView.addArrangedSubview(saveButton)
        homeStackView.setCustomSpacing(12, after: uaRow)
        if showsTimeAwareSettings {
            homeStackView.setCustomSpacing(12, after: timeAwareRow)
        }
        homeStackView.setCustomSpacing(0, after: downloadsRow)
        homeContent.addSubview(homeStackView)

        NSLayoutConstraint.activate([
            homeStackView.leadingAnchor.constraint(equalTo: homeContent.leadingAnchor, constant: 16),
            homeStackView.trailingAnchor.constraint(equalTo: homeContent.trailingAnchor, constant: -16),
            homeStackView.centerYAnchor.constraint(equalTo: homeContent.centerYAnchor),

            uaRow.heightAnchor.constraint(equalToConstant: 72),
            uaLabel.leadingAnchor.constraint(equalTo: uaRow.leadingAnchor, constant: 16),
            uaLabel.centerYAnchor.constraint(equalTo: uaRow.centerYAnchor),
            androidUASwitch.trailingAnchor.constraint(equalTo: uaRow.trailingAnchor, constant: -16),
            androidUASwitch.centerYAnchor.constraint(equalTo: uaRow.centerYAnchor),
            androidUASwitch.leadingAnchor.constraint(greaterThanOrEqualTo: uaLabel.trailingAnchor, constant: 14),

            timeAwareRow.heightAnchor.constraint(equalToConstant: 72),
            timeAwareLabel.leadingAnchor.constraint(equalTo: timeAwareRow.leadingAnchor, constant: 16),
            timeAwareLabel.centerYAnchor.constraint(equalTo: timeAwareRow.centerYAnchor),
            timeAwareChevronView.trailingAnchor.constraint(equalTo: timeAwareRow.trailingAnchor, constant: -18),
            timeAwareChevronView.centerYAnchor.constraint(equalTo: timeAwareRow.centerYAnchor),
            timeAwareChevronView.widthAnchor.constraint(equalToConstant: 14),
            timeAwareChevronView.heightAnchor.constraint(equalToConstant: 18),

            downloadsRow.heightAnchor.constraint(equalToConstant: 72),
            downloadsLabel.leadingAnchor.constraint(equalTo: downloadsRow.leadingAnchor, constant: 16),
            downloadsLabel.centerYAnchor.constraint(equalTo: downloadsRow.centerYAnchor),
            chevronView.trailingAnchor.constraint(equalTo: downloadsRow.trailingAnchor, constant: -18),
            chevronView.centerYAnchor.constraint(equalTo: downloadsRow.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 18),

            saveButtonHeightConstraint!,
        ])
    }

    private func configureTimeAwareContent() {
        let backButton = UIButton(type: .system)
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .label
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        let titleLabel = UILabel()
        titleLabel.text = "Time Context"
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .label
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [backButton, titleLabel, closeButton])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 10

        timeAwareStackView.translatesAutoresizingMaskIntoConstraints = false
        timeAwareStackView.axis = .vertical
        timeAwareStackView.spacing = 12
        timeAwareScrollView.translatesAutoresizingMaskIntoConstraints = false
        timeAwareScrollView.alwaysBounceVertical = true
        timeAwareScrollView.showsVerticalScrollIndicator = true

        let enableLabel = UILabel()
        enableLabel.text = "Add Timestamp"
        enableLabel.font = .systemFont(ofSize: 17, weight: .medium)
        enableLabel.translatesAutoresizingMaskIntoConstraints = false

        timeAwareEnabledSwitch.addTarget(self, action: #selector(timeAwareSwitchChanged), for: .valueChanged)
        timeAwareEnabledSwitch.translatesAutoresizingMaskIntoConstraints = false

        let enableRow = UIView()
        enableRow.translatesAutoresizingMaskIntoConstraints = false
        enableRow.backgroundColor = .tertiarySystemBackground
        enableRow.layer.cornerRadius = 14
        enableRow.layer.cornerCurve = .continuous
        enableRow.addSubview(enableLabel)
        enableRow.addSubview(timeAwareEnabledSwitch)

        let timeZoneLabel = UILabel()
        timeZoneLabel.text = "Time Zone"
        timeZoneLabel.font = .systemFont(ofSize: 17, weight: .medium)
        timeZoneLabel.translatesAutoresizingMaskIntoConstraints = false

        timeZoneButton.translatesAutoresizingMaskIntoConstraints = false
        timeZoneButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        timeZoneButton.titleLabel?.lineBreakMode = .byTruncatingMiddle
        timeZoneButton.contentHorizontalAlignment = .right
        timeZoneButton.tintColor = .label
        timeZoneButton.isUserInteractionEnabled = false

        let timeZoneRow = UIView()
        timeZoneRow.translatesAutoresizingMaskIntoConstraints = false
        timeZoneRow.backgroundColor = .tertiarySystemBackground
        timeZoneRow.layer.cornerRadius = 14
        timeZoneRow.layer.cornerCurve = .continuous
        timeZoneRow.addSubview(timeZoneLabel)
        timeZoneRow.addSubview(timeZoneButton)

        let chooseTimeZoneRow = makeTimeZoneNavigationButton(
            title: "Choose Time Zone",
            value: nil,
            action: #selector(chooseTimeZoneTapped)
        )

        timeAwareHintLabel.text = "System follows iOS by default. Choose Time Zone to use a fixed override."
        timeAwareHintLabel.font = .systemFont(ofSize: 12, weight: .regular)
        timeAwareHintLabel.textColor = .secondaryLabel
        timeAwareHintLabel.numberOfLines = 0
        timeAwareHintLabel.translatesAutoresizingMaskIntoConstraints = false

        timeAwareSaveButton.translatesAutoresizingMaskIntoConstraints = false
        timeAwareSaveButton.setTitle("Save", for: .normal)
        timeAwareSaveButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        timeAwareSaveButton.backgroundColor = .label
        timeAwareSaveButton.tintColor = .systemBackground
        timeAwareSaveButton.layer.cornerRadius = 14
        timeAwareSaveButton.layer.cornerCurve = .continuous
        timeAwareSaveButton.addTarget(self, action: #selector(saveTimeAwareTapped), for: .touchUpInside)
        timeAwareSaveButton.isEnabled = false
        timeAwareSaveButton.alpha = 0
        timeAwareSaveButtonHeightConstraint = timeAwareSaveButton.heightAnchor.constraint(equalToConstant: 0)

        timeAwareStackView.addArrangedSubview(enableRow)
        timeAwareStackView.addArrangedSubview(timeZoneRow)
        timeAwareStackView.addArrangedSubview(chooseTimeZoneRow)
        timeAwareStackView.addArrangedSubview(timeAwareHintLabel)
        timeAwareStackView.setCustomSpacing(8, after: timeZoneRow)

        timeAwareScrollView.addSubview(timeAwareStackView)
        timeAwareContent.addSubview(header)
        timeAwareContent.addSubview(timeAwareScrollView)
        timeAwareContent.addSubview(timeAwareSaveButton)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: timeAwareContent.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: timeAwareContent.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: timeAwareContent.trailingAnchor, constant: -14),
            backButton.widthAnchor.constraint(equalToConstant: 34),
            backButton.heightAnchor.constraint(equalToConstant: 34),
            closeButton.widthAnchor.constraint(equalToConstant: 34),
            closeButton.heightAnchor.constraint(equalToConstant: 34),

            timeAwareScrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            timeAwareScrollView.leadingAnchor.constraint(equalTo: timeAwareContent.leadingAnchor, constant: 16),
            timeAwareScrollView.trailingAnchor.constraint(equalTo: timeAwareContent.trailingAnchor, constant: -16),
            timeAwareScrollView.bottomAnchor.constraint(equalTo: timeAwareSaveButton.topAnchor, constant: -12),

            timeAwareStackView.topAnchor.constraint(equalTo: timeAwareScrollView.contentLayoutGuide.topAnchor),
            timeAwareStackView.leadingAnchor.constraint(equalTo: timeAwareScrollView.contentLayoutGuide.leadingAnchor),
            timeAwareStackView.trailingAnchor.constraint(equalTo: timeAwareScrollView.contentLayoutGuide.trailingAnchor),
            timeAwareStackView.bottomAnchor.constraint(equalTo: timeAwareScrollView.contentLayoutGuide.bottomAnchor),
            timeAwareStackView.widthAnchor.constraint(equalTo: timeAwareScrollView.frameLayoutGuide.widthAnchor),

            enableRow.heightAnchor.constraint(equalToConstant: 62),
            enableLabel.leadingAnchor.constraint(equalTo: enableRow.leadingAnchor, constant: 16),
            enableLabel.centerYAnchor.constraint(equalTo: enableRow.centerYAnchor),
            timeAwareEnabledSwitch.trailingAnchor.constraint(equalTo: enableRow.trailingAnchor, constant: -16),
            timeAwareEnabledSwitch.centerYAnchor.constraint(equalTo: enableRow.centerYAnchor),
            timeAwareEnabledSwitch.leadingAnchor.constraint(greaterThanOrEqualTo: enableLabel.trailingAnchor, constant: 14),

            timeZoneRow.heightAnchor.constraint(equalToConstant: 62),
            timeZoneLabel.leadingAnchor.constraint(equalTo: timeZoneRow.leadingAnchor, constant: 16),
            timeZoneLabel.centerYAnchor.constraint(equalTo: timeZoneRow.centerYAnchor),
            timeZoneButton.trailingAnchor.constraint(equalTo: timeZoneRow.trailingAnchor, constant: -16),
            timeZoneButton.centerYAnchor.constraint(equalTo: timeZoneRow.centerYAnchor),
            timeZoneButton.leadingAnchor.constraint(greaterThanOrEqualTo: timeZoneLabel.trailingAnchor, constant: 12),

            timeAwareSaveButton.leadingAnchor.constraint(equalTo: timeAwareContent.leadingAnchor, constant: 16),
            timeAwareSaveButton.trailingAnchor.constraint(equalTo: timeAwareContent.trailingAnchor, constant: -16),
            timeAwareSaveButton.bottomAnchor.constraint(equalTo: timeAwareContent.bottomAnchor, constant: -16),
            timeAwareSaveButtonHeightConstraint!,
        ])
    }

    private func configureDownloadsContent() {
        let backButton = UIButton(type: .system)
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .label
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        let titleLabel = UILabel()
        titleLabel.text = "Downloads"
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .label
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [backButton, titleLabel, closeButton])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 10

        let downloadsView = ShellLegacyDownloadsManagerView()
        downloadsView.translatesAutoresizingMaskIntoConstraints = false

        downloadsContent.addSubview(header)
        downloadsContent.addSubview(downloadsView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: downloadsContent.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: downloadsContent.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: downloadsContent.trailingAnchor, constant: -14),
            backButton.widthAnchor.constraint(equalToConstant: 34),
            backButton.heightAnchor.constraint(equalToConstant: 34),
            closeButton.widthAnchor.constraint(equalToConstant: 34),
            closeButton.heightAnchor.constraint(equalToConstant: 34),

            downloadsView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            downloadsView.leadingAnchor.constraint(equalTo: downloadsContent.leadingAnchor),
            downloadsView.trailingAnchor.constraint(equalTo: downloadsContent.trailingAnchor),
            downloadsView.bottomAnchor.constraint(equalTo: downloadsContent.bottomAnchor),
        ])
    }

    private func configureTimeZoneListContent() {
        let backButton = UIButton(type: .system)
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .label
        backButton.addTarget(self, action: #selector(timeZoneListBackTapped), for: .touchUpInside)

        timeZoneListTitleLabel.text = "Time Zone"
        timeZoneListTitleLabel.font = .systemFont(ofSize: 22, weight: .semibold)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .label
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [backButton, timeZoneListTitleLabel, closeButton])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 10

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true

        timeZoneListStackView.translatesAutoresizingMaskIntoConstraints = false
        timeZoneListStackView.axis = .vertical
        timeZoneListStackView.spacing = 8

        scrollView.addSubview(timeZoneListStackView)
        timeZoneListContent.addSubview(header)
        timeZoneListContent.addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: timeZoneListContent.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: timeZoneListContent.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: timeZoneListContent.trailingAnchor, constant: -14),
            backButton.widthAnchor.constraint(equalToConstant: 34),
            backButton.heightAnchor.constraint(equalToConstant: 34),
            closeButton.widthAnchor.constraint(equalToConstant: 34),
            closeButton.heightAnchor.constraint(equalToConstant: 34),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: timeZoneListContent.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: timeZoneListContent.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: timeZoneListContent.bottomAnchor, constant: -16),

            timeZoneListStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            timeZoneListStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            timeZoneListStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            timeZoneListStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            timeZoneListStackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func setTimeZoneListMode(_ mode: TimeZoneListMode, animated: Bool) {
        timeZoneListMode = mode
        refreshTimeZoneList(animated: animated)
    }

    private func refreshTimeZoneList(animated: Bool) {
        let rebuild = {
            self.timeZoneListStackView.arrangedSubviews.forEach { view in
                self.timeZoneListStackView.removeArrangedSubview(view)
                view.removeFromSuperview()
            }

            switch self.timeZoneListMode {
            case .suggestions:
                self.timeZoneListTitleLabel.text = "Choose Time Zone"
                self.timeZoneListStackView.addArrangedSubview(
                    self.makeTimeZoneOptionButton(title: "Use System Default", identifier: nil)
                )
                for identifier in self.suggestedTimeZoneIdentifiers() {
                    self.timeZoneListStackView.addArrangedSubview(
                        self.makeTimeZoneOptionButton(title: identifier, identifier: identifier)
                    )
                }
                self.timeZoneListStackView.addArrangedSubview(
                    self.makeTimeZoneNavigationButton(
                        title: "Other",
                        value: nil,
                        action: #selector(self.otherTimeZonesTapped)
                    )
                )

            case .regions:
                self.timeZoneListTitleLabel.text = "Other"
                for regionIdentifier in self.timeZoneRegionIdentifiers() {
                    self.timeZoneListStackView.addArrangedSubview(
                        self.makeTimeZoneNavigationButton(
                            title: regionIdentifier,
                            value: regionIdentifier,
                            action: #selector(self.timeZoneRegionTapped(_:))
                        )
                    )
                }

            case .region(let regionIdentifier):
                self.timeZoneListTitleLabel.text = regionIdentifier
                for identifier in self.timeZoneIdentifiers(in: regionIdentifier) {
                    self.timeZoneListStackView.addArrangedSubview(
                        self.makeTimeZoneOptionButton(title: identifier, identifier: identifier)
                    )
                }
            }
        }

        guard animated else {
            rebuild()
            return
        }

        let direction: CGFloat = 10
        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: {
                self.timeZoneListStackView.alpha = 0
                self.timeZoneListStackView.transform = CGAffineTransform(translationX: -direction, y: 0)
            },
            completion: { _ in
                rebuild()
                self.timeZoneListStackView.transform = CGAffineTransform(translationX: direction, y: 0)
                UIView.animate(
                    withDuration: 0.16,
                    delay: 0,
                    options: [.curveEaseInOut, .allowUserInteraction],
                    animations: {
                        self.timeZoneListStackView.alpha = 1
                        self.timeZoneListStackView.transform = .identity
                    }
                )
            }
        )
    }

    private func makeTimeZoneOptionButton(title: String, identifier: String?) -> TimeZoneOptionButton {
        let selectedIdentifier = normalizedOverrideTimeZoneIdentifier(draftTimeAwareTimeZoneIdentifier)
        let isSelected = selectedIdentifier == normalizedOverrideTimeZoneIdentifier(identifier) ||
            (selectedIdentifier == nil && identifier == nil)
        let button = TimeZoneOptionButton(type: .system)
        button.timeZoneIdentifier = identifier
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(isSelected ? "Selected: \(title)" : title, for: .normal)
        button.setTitleColor(.label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: isSelected ? .semibold : .regular)
        button.titleLabel?.lineBreakMode = .byTruncatingMiddle
        button.contentHorizontalAlignment = .left
        button.backgroundColor = .tertiarySystemBackground
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        button.addTarget(self, action: #selector(timeZoneOptionTapped(_:)), for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
        return button
    }

    private func makeTimeZoneNavigationButton(title: String, value: String?, action: Selector) -> TimeZoneNavigationRow {
        let row = TimeZoneNavigationRow()
        row.value = value
        row.translatesAutoresizingMaskIntoConstraints = false
        row.backgroundColor = .tertiarySystemBackground
        row.layer.cornerRadius = 14
        row.layer.cornerCurve = .continuous
        row.addTarget(self, action: action, for: .touchUpInside)

        let label = UILabel()
        label.text = title
        label.textColor = .label
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false

        let chevronView = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.tintColor = .secondaryLabel
        chevronView.contentMode = .scaleAspectFit

        row.addSubview(label)
        row.addSubview(chevronView)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 54),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevronView.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            chevronView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 18),
            chevronView.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
        ])

        return row
    }

    private func switchContent(to incoming: UIView, from outgoing: UIView, animated: Bool) {
        guard incoming !== outgoing else {
            incoming.isHidden = false
            incoming.alpha = 1
            incoming.transform = .identity
            return
        }

        incoming.isHidden = false
        incoming.alpha = animated ? 0 : 1
        incoming.transform = animated ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity

        let animations = {
            incoming.alpha = 1
            incoming.transform = .identity
            outgoing.alpha = 0
            outgoing.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
        }
        let completion: (Bool) -> Void = { _ in
            outgoing.isHidden = true
            outgoing.transform = .identity
        }

        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut], animations: animations, completion: completion)
        } else {
            animations()
            completion(true)
        }
    }

    private func updateCardHeight(animated: Bool) {
        let side = cardSideConstraint?.constant ?? 280
        let saveHeight: CGFloat = androidUASwitch.isOn != savedAndroidUserAgent ? 60 : 0
        let homeRowCount: CGFloat = showsTimeAwareSettings ? 3 : 2
        let homeSpacing: CGFloat = showsTimeAwareSettings ? 24 : 12
        let homeHeight: CGFloat = (homeRowCount * 72) + homeSpacing + saveHeight + 32
        let targetHeight: CGFloat
        switch activePanel {
        case .home:
            targetHeight = homeHeight
        case .timeAware:
            targetHeight = side
        case .timeZoneList:
            targetHeight = side
        case .downloads:
            targetHeight = side
        }

        let applyHeight = {
            self.cardHeightConstraint?.constant = min(targetHeight, side)
        }

        guard animated else {
            applyHeight()
            return
        }

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut]) {
            applyHeight()
            self.layoutIfNeeded()
        }
    }

    private func updateSaveButton(animated: Bool) {
        let changed = androidUASwitch.isOn != savedAndroidUserAgent
        let updates = {
            self.saveButton.alpha = changed ? 1 : 0
            self.saveButton.isEnabled = changed
            self.saveButtonHeightConstraint?.constant = changed ? 48 : 0
            self.homeStackView.setCustomSpacing(changed ? 12 : 0, after: self.downloadsRow)
            self.homeStackView.layoutIfNeeded()
            self.homeContent.layoutIfNeeded()
            self.cardView.layoutIfNeeded()
            self.updateCardHeight(animated: false)
            self.layoutIfNeeded()
        }

        guard animated else {
            updates()
            return
        }

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut], animations: updates)
    }

    private func updateTimeAwareSaveButton(animated: Bool) {
        let changed = timeAwareEnabledSwitch.isOn != savedTimeAwareEnabled ||
            normalizedOverrideTimeZoneIdentifier(draftTimeAwareTimeZoneIdentifier) != normalizedOverrideTimeZoneIdentifier(savedTimeAwareTimeZoneIdentifier)
        let updates = {
            self.timeAwareSaveButton.alpha = changed ? 1 : 0
            self.timeAwareSaveButton.isEnabled = changed
            self.timeAwareSaveButtonHeightConstraint?.constant = changed ? 48 : 0
            self.timeAwareStackView.layoutIfNeeded()
            self.timeAwareContent.layoutIfNeeded()
            self.cardView.layoutIfNeeded()
            self.updateCardHeight(animated: false)
            self.layoutIfNeeded()
        }

        guard animated else {
            updates()
            return
        }

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut], animations: updates)
    }

    private func updateTimeZoneButton() {
        let selectedIdentifier = normalizedOverrideTimeZoneIdentifier(draftTimeAwareTimeZoneIdentifier)
        let title = selectedIdentifier ?? "System: \(TimeZone.current.identifier)"
        timeZoneButton.setTitle(title, for: .normal)
    }

    private func suggestedTimeZoneIdentifiers() -> [String] {
        let candidates =
            ShellTimeAwareSettings.recentTimeZoneIdentifiers.map { Optional($0) } + [
            savedTimeAwareTimeZoneIdentifier,
            TimeZone.current.identifier,
            localePrimaryTimeZoneIdentifier(),
        ] + matchingOffsetTimeZoneIdentifiers()

        var seen = Set<String>()
        return Array(candidates.compactMap { identifier in
            guard let identifier = normalizedOverrideTimeZoneIdentifier(identifier),
                  TimeZone(identifier: identifier) != nil,
                  !seen.contains(identifier) else {
                return nil
            }
            seen.insert(identifier)
            return identifier
        }.prefix(6))
    }

    private func matchingOffsetTimeZoneIdentifiers() -> [String?] {
        guard let currentTimeZone = TimeZone(identifier: TimeZone.current.identifier) else {
            return []
        }

        let now = Date()
        let currentOffset = currentTimeZone.secondsFromGMT(for: now)
        return commonTimeZoneIdentifiers()
            .filter { identifier in
                TimeZone(identifier: identifier)?.secondsFromGMT(for: now) == currentOffset
            }
            .prefix(6)
            .map { Optional($0) }
    }

    private func timeZoneRegionIdentifiers() -> [String] {
        [
            "Europe",
            "North America",
            "South America",
            "MENA",
            "Asia",
            "South Asia",
            "Africa",
            "Oceania",
            "UTC",
        ]
    }

    private func timeZoneIdentifiers(in regionIdentifier: String) -> [String] {
        switch regionIdentifier {
        case "Europe":
            return [
                "Europe/Paris",
                "Europe/Brussels",
                "Europe/Amsterdam",
                "Europe/Berlin",
                "Europe/London",
                "Europe/Madrid",
                "Europe/Rome",
                "Europe/Zurich",
                "Europe/Istanbul",
            ]
        case "North America":
            return [
                "America/New_York",
                "America/Toronto",
                "America/Chicago",
                "America/Denver",
                "America/Los_Angeles",
                "America/Mexico_City",
            ]
        case "South America":
            return [
                "America/Sao_Paulo",
                "America/Argentina/Buenos_Aires",
                "America/Bogota",
                "America/Lima",
                "America/Santiago",
            ]
        case "MENA":
            return [
                "Africa/Cairo",
                "Africa/Casablanca",
                "Africa/Tunis",
                "Asia/Dubai",
                "Asia/Riyadh",
                "Asia/Jerusalem",
                "Asia/Beirut",
                "Asia/Qatar",
            ]
        case "Asia":
            return [
                "Asia/Bangkok",
                "Asia/Singapore",
                "Asia/Shanghai",
                "Asia/Hong_Kong",
                "Asia/Tokyo",
                "Asia/Seoul",
                "Asia/Jakarta",
            ]
        case "South Asia":
            return [
                "Asia/Kolkata",
                "Asia/Karachi",
                "Asia/Dhaka",
                "Asia/Colombo",
                "Asia/Kathmandu",
            ]
        case "Africa":
            return [
                "Africa/Johannesburg",
                "Africa/Lagos",
                "Africa/Nairobi",
                "Africa/Accra",
                "Africa/Addis_Ababa",
            ]
        case "Oceania":
            return [
                "Australia/Sydney",
                "Australia/Melbourne",
                "Australia/Brisbane",
                "Australia/Perth",
                "Pacific/Auckland",
            ]
        case "UTC":
            return ["UTC"]
        default:
            return []
        }
    }

    private func commonTimeZoneIdentifiers() -> [String] {
        timeZoneRegionIdentifiers().flatMap { timeZoneIdentifiers(in: $0) }
    }

    private func localePrimaryTimeZoneIdentifier() -> String? {
        guard let regionCode = Locale.current.regionCode?.uppercased() else {
            return nil
        }

        let primaryTimeZonesByRegion = [
            "AE": "Asia/Dubai",
            "AU": "Australia/Sydney",
            "BE": "Europe/Brussels",
            "CA": "America/Toronto",
            "DE": "Europe/Berlin",
            "FR": "Europe/Paris",
            "GB": "Europe/London",
            "JP": "Asia/Tokyo",
            "NL": "Europe/Amsterdam",
            "SA": "Asia/Riyadh",
            "US": "America/New_York",
        ]

        return primaryTimeZonesByRegion[regionCode]
    }

    private func normalizedTimeZoneIdentifier(_ identifier: String?) -> String? {
        let value = identifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private func normalizedOverrideTimeZoneIdentifier(_ identifier: String?) -> String? {
        guard let value = normalizedTimeZoneIdentifier(identifier),
              value != TimeZone.current.identifier else {
            return nil
        }
        return value
    }

    private func setDraftTimeZoneIdentifier(_ identifier: String?) {
        draftTimeAwareTimeZoneIdentifier = normalizedOverrideTimeZoneIdentifier(identifier)
        updateTimeZoneButton()
        updateTimeAwareSaveButton(animated: true)
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func backgroundTapped() {
        onClose?()
    }

    @objc private func saveUserAgentTapped() {
        savedAndroidUserAgent = androidUASwitch.isOn
        updateSaveButton(animated: true)
        onSaveUserAgent?(androidUASwitch.isOn)
    }

    @objc private func saveTimeAwareTapped() {
        savedTimeAwareEnabled = timeAwareEnabledSwitch.isOn
        savedTimeAwareTimeZoneIdentifier = normalizedOverrideTimeZoneIdentifier(draftTimeAwareTimeZoneIdentifier)
        ShellTimeAwareSettings.rememberTimeZoneIdentifier(savedTimeAwareTimeZoneIdentifier)
        updateTimeAwareSaveButton(animated: true)
        onSaveTimeAware?(timeAwareEnabledSwitch.isOn, savedTimeAwareTimeZoneIdentifier)
    }

    @objc private func downloadsTapped() {
        showDownloads(animated: true)
    }

    @objc private func timeAwareTapped() {
        showTimeAware(animated: true)
    }

    @objc private func backTapped() {
        showHome(animated: true)
    }

    @objc private func timeZoneListBackTapped() {
        switch timeZoneListMode {
        case .region(_):
            setTimeZoneListMode(.regions, animated: true)
        case .regions:
            setTimeZoneListMode(.suggestions, animated: true)
        case .suggestions:
            showTimeAware(animated: true)
        }
    }

    @objc private func chooseTimeZoneTapped() {
        showTimeZoneList(animated: true)
    }

    @objc private func otherTimeZonesTapped() {
        setTimeZoneListMode(.regions, animated: true)
    }

    @objc private func timeZoneRegionTapped(_ sender: TimeZoneNavigationRow) {
        guard let regionIdentifier = sender.value else {
            return
        }
        setTimeZoneListMode(.region(regionIdentifier), animated: true)
    }

    @objc private func androidUASwitchChanged() {
        updateSaveButton(animated: true)
    }

    @objc private func timeAwareSwitchChanged() {
        updateTimeAwareSaveButton(animated: true)
    }

    @objc private func timeZoneOptionTapped(_ sender: TimeZoneOptionButton) {
        setDraftTimeZoneIdentifier(sender.timeZoneIdentifier)
        showTimeAware(animated: true)
    }

    private func contentView(for panel: Panel) -> UIView {
        switch panel {
        case .home:
            return homeContent
        case .timeAware:
            return timeAwareContent
        case .timeZoneList:
            return timeZoneListContent
        case .downloads:
            return downloadsContent
        }
    }
}
