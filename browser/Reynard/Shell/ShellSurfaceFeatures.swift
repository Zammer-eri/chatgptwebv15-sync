//
//  ShellSurfaceFeatures.swift
//  Reynard
//
//  Shell-only gestures and utility UI. Keep this layer isolated so upstream
//  Reynard updates only need a small hook from BrowserViewController.
//

import ObjectiveC
import GeckoView
import UIKit

private enum ShellSurfaceAssociatedKeys {
    static var utilityPanel = 0
    static var utilityPanelVisible = 0
}

extension BrowserViewController {
    func configureShellSurfaceFeatures() {
        guard ShellConfig.current.target != .browser else {
            return
        }

        if ShellConfig.current.features.usesUtilityPanel {
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

    private func configureShellGestures() {
        let refreshGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleShellRefreshGesture(_:)))
        refreshGesture.edges = .left
        refreshGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(refreshGesture)

        let dismissKeyboardGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleShellDismissKeyboardGesture(_:)))
        dismissKeyboardGesture.edges = .right
        dismissKeyboardGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(dismissKeyboardGesture)

        let settingsGesture = UITapGestureRecognizer(target: self, action: #selector(handleShellSettingsGesture(_:)))
        settingsGesture.numberOfTapsRequired = 2
        settingsGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(settingsGesture)
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

    @objc private func handleShellRefreshGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended || gesture.state == .recognized else {
            return
        }

        guard gesture.translation(in: view).x > 24 else {
            return
        }

        refreshSelectedTabLikeBrowserChrome()
    }

    @objc private func handleShellDismissKeyboardGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended || gesture.state == .recognized else {
            return
        }

        guard gesture.translation(in: view).x < -24 else {
            return
        }

        view.endEditing(true)
    }

    @objc private func handleShellSettingsGesture(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended || gesture.state == .recognized else {
            return
        }

        setShellUtilityPanelVisible(true, animated: true)
    }

    private func refreshSelectedTabLikeBrowserChrome() {
        guard let selectedTab = tabManager.selectedTab else {
            return
        }

        if selectedTab.isLoading {
            selectedTab.session.stop()
            return
        }

        selectedTab.session.reload()
    }

    private func reloadSelectedTabWithCurrentSettings() {
        guard let selectedTab = tabManager.selectedTab else {
            return
        }

        let url = selectedTab.url ?? ShellConfig.current.defaultURL?.absoluteString ?? "https://chatgpt.com"
        selectedTab.session.updateSettings(
            GeckoSessionController.shared.sessionSettings(for: url, tabID: selectedTab.id)
        )
        selectedTab.session.reload()
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
    private let androidUASwitch = UISwitch()
    private let saveButton = UIButton(type: .system)
    private var cardSideConstraint: NSLayoutConstraint?
    private var savedAndroidUserAgent = false

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
        cardView.clipsToBounds = false

        addSubview(blurView)
        addSubview(dimView)
        addSubview(cardView)
        cardView.addSubview(homeContent)
        cardView.addSubview(downloadsContent)
        cardSideConstraint = cardView.widthAnchor.constraint(equalToConstant: 280)

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
            cardView.heightAnchor.constraint(equalTo: cardView.widthAnchor),

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
        switchContent(to: homeContent, from: downloadsContent, animated: animated)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else {
            return true
        }
        return !touchedView.isDescendant(of: cardView)
    }

    private func configureHomeContent() {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 12

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

        let downloadsRow = UIControl()
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
        saveButton.isHidden = true
        saveButton.alpha = 0

        stackView.addArrangedSubview(uaRow)
        stackView.addArrangedSubview(downloadsRow)
        stackView.addArrangedSubview(saveButton)
        homeContent.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: homeContent.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: homeContent.trailingAnchor, constant: -16),
            stackView.centerYAnchor.constraint(equalTo: homeContent.centerYAnchor),

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

            saveButton.heightAnchor.constraint(equalToConstant: 48),
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

        let downloadsView = DownloadsManagerView()
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

    private func updateSaveButton(animated: Bool) {
        let changed = androidUASwitch.isOn != savedAndroidUserAgent
        if changed {
            saveButton.isHidden = false
        }

        let updates = {
            self.saveButton.alpha = changed ? 1 : 0
            self.saveButton.isEnabled = changed
            self.homeContent.layoutIfNeeded()
        }

        guard animated else {
            updates()
            saveButton.isHidden = !changed
            return
        }

        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseInOut], animations: updates) { _ in
            self.saveButton.isHidden = !changed
        }
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
        switchContent(to: downloadsContent, from: homeContent, animated: true)
    }

    @objc private func backTapped() {
        showHome(animated: true)
    }

    @objc private func androidUASwitchChanged() {
        updateSaveButton(animated: true)
    }
}
