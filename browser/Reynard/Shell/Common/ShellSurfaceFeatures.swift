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

    private func configureShellGestures() {
        let reloadGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleShellReloadGesture(_:)))
        reloadGesture.edges = .left
        reloadGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(reloadGesture)

        let keyboardDismissGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleShellKeyboardDismissGesture(_:)))
        keyboardDismissGesture.edges = .right
        keyboardDismissGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(keyboardDismissGesture)

        let utilityGesture = UITapGestureRecognizer(target: self, action: #selector(handleUtilityPanelTap(_:)))
        utilityGesture.numberOfTouchesRequired = 2
        utilityGesture.numberOfTapsRequired = 1
        utilityGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(utilityGesture)
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

        guard gesture.translation(in: view).x > 24 else {
            return
        }

        guard let tab = tabManager.selectedTab else {
            return
        }

        setShellRecoveryOverlayVisible(true, animated: true)
        reloadTabAfterClearingAppCache(tab)
    }

    @objc private func handleShellKeyboardDismissGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended || gesture.state == .recognized else {
            return
        }

        guard gesture.translation(in: view).x < -24 else {
            return
        }

        view.endEditing(true)
    }

    @objc private func handleUtilityPanelTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended || gesture.state == .recognized else {
            return
        }

        setShellUtilityPanelVisible(true, animated: true)
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

            DispatchQueue.main.async {
                completion()
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

private final class ShellUtilityPanelView: UIView, UIGestureRecognizerDelegate {
    var onClose: (() -> Void)?
    var onSaveUserAgent: ((Bool) -> Void)?

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let dimView = UIView()
    private let cardView = UIView()
    private let homeContent = UIView()
    private let downloadsContent = UIView()
    private let homeStackView = UIStackView()
    private let downloadsRow = UIControl()
    private let androidUASwitch = UISwitch()
    private let saveButton = UIButton(type: .system)
    private var cardSideConstraint: NSLayoutConstraint?
    private var cardHeightConstraint: NSLayoutConstraint?
    private var saveButtonHeightConstraint: NSLayoutConstraint?
    private var savedAndroidUserAgent = false
    private var activePanel: Panel = .home

    private enum Panel {
        case home
        case downloads
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        blurView.translatesAutoresizingMaskIntoConstraints = false
        dimView.translatesAutoresizingMaskIntoConstraints = false
        cardView.translatesAutoresizingMaskIntoConstraints = false
        homeContent.translatesAutoresizingMaskIntoConstraints = false
        downloadsContent.translatesAutoresizingMaskIntoConstraints = false

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

            downloadsContent.topAnchor.constraint(equalTo: cardView.topAnchor),
            downloadsContent.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            downloadsContent.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            downloadsContent.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
        ])

        configureHomeContent()
        configureDownloadsContent()
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
        updateSaveButton(animated: false)
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
        homeStackView.addArrangedSubview(downloadsRow)
        homeStackView.addArrangedSubview(saveButton)
        homeStackView.setCustomSpacing(12, after: uaRow)
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
        let homeHeight: CGFloat = 72 + 12 + 72 + saveHeight + 32
        let targetHeight: CGFloat
        switch activePanel {
        case .home:
            targetHeight = homeHeight
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

    @objc private func downloadsTapped() {
        showDownloads(animated: true)
    }

    @objc private func backTapped() {
        showHome(animated: true)
    }

    @objc private func androidUASwitchChanged() {
        updateSaveButton(animated: true)
    }

    private func contentView(for panel: Panel) -> UIView {
        switch panel {
        case .home:
            return homeContent
        case .downloads:
            return downloadsContent
        }
    }
}
