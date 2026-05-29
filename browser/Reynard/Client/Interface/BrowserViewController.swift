//
//  BrowserViewController.swift
//  Reynard
//
//  Created by Minh Ton on 4/3/26.
//

import GeckoView
import UIKit

final class BrowserViewController: UIViewController, AddressBarDelegate, PhoneToolbarDelegate, TabManagerDelegate {
    let overviewInset: CGFloat = 16
    let overviewSpacing: CGFloat = 16
    private let actsAsRootContainer: Bool
    private var embeddedSplitController: BrowserSplitViewController?

    lazy var tabCollectionCoordinator = TabCollectionCoordinator(controller: self)

    lazy var browserUI = BrowserUI(
        controller: self,
        overviewInset: overviewInset,
        overviewSpacing: overviewSpacing,
        tabCollectionHandler: tabCollectionCoordinator
    )

    lazy var tabManager: TabManager = TabManagerImplementation(delegate: self)
    lazy var browserLayout = BrowserLayout(controller: self)
    lazy var tabOverviewPresentation = TabOverviewPresentation(controller: self)

    var isSearchFocused = false
    private var pendingSelectionAnimation = false
    private let utilityPanel = UtilityPanelView()
    private var utilityPanelLeadingConstraint: NSLayoutConstraint?
    private var utilityPanelVisible = false

    override var shouldAutorotate: Bool {
        false
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    var isLibrarySidebarVisible: Bool {
        (splitViewController as? BrowserSplitViewController)?.isLibrarySidebarVisible ?? false
    }

    var isPadLayout: Bool {
        traitCollection.userInterfaceIdiom == .pad
    }

    var usesCompactPadChromeMode: Bool {
        if isPadLayout && traitCollection.horizontalSizeClass == .compact { return true }
        return usesPhoneTopAddressBarLayout
    }

    var usesPadChromeLayout: Bool {
        if isPadLayout { return true }
        if usesPhoneTopAddressBarLayout { return true }
        if let orientation = view.window?.windowScene?.interfaceOrientation {
            return orientation.isLandscape
        }
        return view.bounds.width > view.bounds.height
    }


    var usesPhoneTopAddressBarLayout: Bool {
        false
    }

    var usesPhoneBottomOverviewLayout: Bool {
        guard !isPadLayout else { return false }
        return usesPhoneTopAddressBarLayout || !usesPadChromeLayout
    }

    var activeAddressBar: AddressBar {
        browserUI.addressBar
    }

    init(actsAsRootContainer: Bool = true) {
        self.actsAsRootContainer = actsAsRootContainer
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private var usesEmbeddedSplitRoot: Bool {
        false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        if usesEmbeddedSplitRoot {
            configureEmbeddedSplitRoot()
            return
        }

        browserLayout.configureLayout()
        configureUtilityPanel()
        syncBrowserNavigationChrome(animated: false)
        syncPadSidebarButtonItem()
        configureChatGPTShellGestures()
        browserLayout.observeKeyboard()

        tabManager.createInitialTab()
        refreshAddressBar()
        browserLayout.applyChromeLayout(animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !usesEmbeddedSplitRoot else {
            return
        }
        syncBrowserNavigationChrome(animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard !usesEmbeddedSplitRoot else {
            return
        }
        view.endEditing(true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !usesEmbeddedSplitRoot else {
            return
        }
        syncBrowserNavigationChrome(animated: false)
        syncPadSidebarButtonItem()
        browserLayout.applyChromeLayout(animated: false)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard !usesEmbeddedSplitRoot else {
            embeddedSplitController?.refreshSidebarVisibility()
            return
        }
        syncBrowserNavigationChrome(animated: false)
        syncPadSidebarButtonItem()
        refreshAddressBar()
        browserLayout.applyChromeLayout(animated: false)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard !usesEmbeddedSplitRoot else {
            return
        }

        coordinator.animate { _ in
            self.syncBrowserNavigationChrome(animated: false)
            self.syncPadSidebarButtonItem()
        } completion: { _ in
            self.syncBrowserNavigationChrome(animated: false)
            self.syncPadSidebarButtonItem()
            self.browserUI.geckoView.transform = .identity
            DispatchQueue.main.async {
                guard self.isViewLoaded, self.view.window != nil else {
                    return
                }
                self.browserLayout.applyChromeLayout(animated: false)
            }
        }
    }

    @discardableResult
    func createTab(selecting: Bool, windowId: String? = nil, at index: Int? = nil) -> Int {
        tabManager.addTab(selecting: selecting, windowId: windowId, at: index)
    }

    func selectTab(at index: Int, animated: Bool) {
        pendingSelectionAnimation = animated
        tabManager.selectTab(at: index)
    }

    func closeTab(at index: Int) {
        tabManager.removeTab(at: index)
    }

    func clearAllTabs() {
        tabManager.removeAllTabs()
    }

    func setTabOverviewVisible(_ visible: Bool, animated: Bool) {
        tabOverviewPresentation.setVisible(visible, animated: animated)
    }

    func setSearchFocused(_ focused: Bool, animated: Bool) {
        browserLayout.setSearchFocused(focused, animated: animated)
    }

    func applyChromeLayout(animated: Bool) {
        browserLayout.applyChromeLayout(animated: animated)
    }

    func centerSelectedPadTab(animated: Bool) {
        guard usesPadChromeLayout, tabManager.tabs.indices.contains(tabManager.selectedTabIndex) else {
            return
        }

        let indexPath = IndexPath(item: tabManager.selectedTabIndex, section: 0)
        browserUI.padTabBar.collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: animated)
    }

    func browse(to term: String) {
        tabManager.browse(to: term)
    }

    func openExternalURL(_ url: URL) {
        let targetController = activeContentBrowserViewController
        targetController.loadViewIfNeeded()
        targetController.prepareTabForExternalLoad()
        targetController.browse(to: url.absoluteString)
    }

    private var activeContentBrowserViewController: BrowserViewController {
        embeddedSplitController?.contentBrowserViewController ?? self
    }

    private func prepareTabForExternalLoad() {
        guard !tabManager.tabs.isEmpty else {
            tabManager.createInitialTab()
            return
        }
    }

    func updateNavigationButtons() {
        guard let tab = tabManager.selectedTab else {
            return
        }

        browserUI.toolbarView.updateBackButton(canGoBack: tab.canGoBack)
        browserUI.toolbarView.updateForwardButton(canGoForward: tab.canGoForward)
        let shareEnabled = tabManager.shareableURL(for: tab) != nil
        browserUI.toolbarView.updateShareButton(isEnabled: shareEnabled)
        browserUI.padTopBarButtons.shareButton.isEnabled = shareEnabled
        browserUI.padTopBarButtons.backButton.isEnabled = tab.canGoBack
        browserUI.padTopBarButtons.forwardButton.isEnabled = tab.canGoForward
    }

    private func syncPadSidebarButtonItem() {
        browserUI.padTopBarButtons.syncSidebarButton(splitViewController: splitViewController)
    }

    private func syncBrowserNavigationChrome(animated: Bool) {
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationItem.leftItemsSupplementBackButton = false
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItems = []
        navigationItem.leftBarButtonItem = nil
    }

    private func configureEmbeddedSplitRoot() {
        guard embeddedSplitController == nil else {
            return
        }

        let splitController = BrowserSplitViewController(browserViewController: BrowserViewController(actsAsRootContainer: false))
        addChild(splitController)
        splitController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitController.view)
        NSLayoutConstraint.activate([
            splitController.view.topAnchor.constraint(equalTo: view.topAnchor),
            splitController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        splitController.didMove(toParent: self)
        embeddedSplitController = splitController
    }

    func setLibrarySidebarVisible(_ visible: Bool, animated: Bool) {
        setUtilityPanelVisible(visible, animated: animated)
    }

    private func activeTabStripHeight() -> CGFloat {
        0
    }

    func tabPreviewAspectRatio() -> CGFloat {
        let bounds = browserUI.geckoView.bounds
        let width = max(bounds.width, 1)
        let height = max(bounds.height + activeTabStripHeight(), 1)
        return height / width
    }

    func captureThumbnail(for index: Int) {
        tabManager.updateThumbnail(nil, forTabAt: index)
    }

    func dismissalContentFrame() -> CGRect {
        let frame = browserUI.geckoView.frame
        let stripHeight = activeTabStripHeight()
        guard stripHeight > 0,
              usesPadChromeLayout,
              tabOverviewPresentation.isVisible else {
            return frame
        }

        return CGRect(
            x: frame.minX,
            y: frame.minY + stripHeight,
            width: frame.width,
            height: max(1, frame.height - stripHeight)
        )
    }

    func syncAddressBarLoadingState(progress: Float, isLoading: Bool) {
        browserUI.addressBar.setLoadingProgress(progress, isLoading: isLoading)
    }

    func refreshAddressBar() {
        let selectedTab = tabManager.selectedTab
        let pendingDisplayText = selectedTab?.pendingDisplayText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPendingDisplayText = !(pendingDisplayText?.isEmpty ?? true)
        let selectedURL = selectedTab?.url
        let displayedText = hasPendingDisplayText ? pendingDisplayText : selectedURL
        if !browserUI.addressBar.isEditingText {
            browserUI.addressBar.setText(
                displayedText,
                locationText: selectedURL,
                locationTitle: selectedTab?.title,
                showsBarMenu: !hasPendingDisplayText && selectedURL?.isEmpty == false
            )
        }
        browserUI.addressBar.setLoadingProgress(selectedTab?.progress ?? 0, isLoading: selectedTab?.isLoading ?? false)
        browserUI.addressBar.setLocationMenu(nil)
    }

    func tabManagerDidChangeTabs(_ tabManager: TabManager) {
        if let selectedTab = tabManager.selectedTab {
            if browserUI.geckoView.session !== selectedTab.session {
                browserUI.geckoView.session = selectedTab.session
            }
        } else {
            browserUI.geckoView.session = nil
        }
        refreshAddressBar()

        browserLayout.applyChromeLayout(animated: false)
    }

    func tabManager(_ tabManager: TabManager, didSelectTabAt index: Int, previousIndex: Int?) {
        guard tabManager.tabs.indices.contains(index) else {
            return
        }

        let selectedTab = tabManager.tabs[index]
        browserUI.geckoView.session = selectedTab.session
        syncAddressBarLoadingState(progress: selectedTab.progress, isLoading: selectedTab.isLoading)
        refreshAddressBar()

        updateNavigationButtons()
        pendingSelectionAnimation = false
    }

    func tabManager(_ tabManager: TabManager, didUpdateTabAt index: Int, reason: TabManagerUpdateReason) {
        guard tabManager.tabs.indices.contains(index) else {
            return
        }

        switch reason {
        case .title:
            break

        case .location:
            if index == tabManager.selectedTabIndex {
                refreshAddressBar()
                updateNavigationButtons()
            }

        case .navigationState:
            if index == tabManager.selectedTabIndex {
                updateNavigationButtons()
            }

        case .loading:
            if index == tabManager.selectedTabIndex {
                let tab = tabManager.tabs[index]
                syncAddressBarLoadingState(progress: tab.progress, isLoading: tab.isLoading)
            }

        case .thumbnail:
            break
        }
    }

    func tabManager(_ tabManager: TabManager, animateNewTabSelectionAt index: Int, completion: @escaping () -> Void) {
        completion()
    }

    func tabManager(_ tabManager: TabManager, didRequestExternalOpen url: URL) {
        openExternalLinkInSafari(url)
    }

    func tabManager(_ tabManager: TabManager, shouldHandleExternalResponse response: ExternalResponseInfo, for session: GeckoSession) -> Bool {
        guard let download = DownloadStore.shared.prepareDownload(from: response) else {
            return false
        }

        DownloadStore.shared.startDownload(download)
        setUtilityPanelVisible(true, animated: true)
        return true
    }

    func backButtonClicked() {
    }

    func forwardButtonClicked() {
    }

    func shareButtonClicked() {
    }

    func menuButtonClicked() {
        setUtilityPanelVisible(true, animated: true)
    }

    func downloadsButtonClicked() {
        setUtilityPanelVisible(true, animated: true)
    }

    func addressBarDidSubmit(_ searchTerm: String) {
        browse(to: searchTerm)
        view.endEditing(true)
    }

    func addressBarDidBeginEditing(_ addressBar: AddressBar) {
        refreshAddressBar()
        setSearchFocused(true, animated: true)
    }

    func addressBarDidEndEditing(_ addressBar: AddressBar) {
        refreshAddressBar()
        if !browserUI.addressBar.isEditingText {
            setSearchFocused(false, animated: true)
        }
    }

    func addressBarDidTapTrailingButton(_ addressBar: AddressBar) {
        guard let selectedTab = tabManager.selectedTab else {
            return
        }

        if selectedTab.isLoading {
            selectedTab.session.stop()
            return
        }

        reloadTab(selectedTab)
    }

    private func configureChatGPTShellGestures() {
        let utilityGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleUtilityPanelGesture(_:)))
        utilityGesture.edges = .left
        utilityGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(utilityGesture)

        let reloadGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleShellReloadGesture(_:)))
        reloadGesture.edges = .right
        reloadGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(reloadGesture)
    }

    @objc private func handleUtilityPanelGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended || gesture.state == .recognized else {
            return
        }

        guard gesture.translation(in: view).x > 24 else {
            return
        }

        setUtilityPanelVisible(true, animated: true)
    }

    @objc private func handleShellReloadGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended || gesture.state == .recognized else {
            return
        }

        guard gesture.translation(in: view).x < -24 else {
            return
        }

        guard let tab = tabManager.selectedTab else { return }
        reloadTab(tab)
    }

    private func reloadTab(_ tab: Tab) {
        tabManager.reload(tab)
    }

    @objc func tabsTapped() {
        setUtilityPanelVisible(true, animated: true)
    }

    @objc func doneTapped() {
    }

    @objc func newTabTapped() {
    }

    @objc func clearAllTabsTapped() {
    }

    @objc func shareTapped() {
    }

    @objc func librarySidebarTapped() {
        setUtilityPanelVisible(!utilityPanelVisible, animated: true)
    }

    @objc func padBackTapped() {
    }

    @objc func padForwardTapped() {
    }

    @objc func topBarMenuTapped() {
        setUtilityPanelVisible(true, animated: true)
    }

    @objc func topBarDownloadsTapped() {
        setUtilityPanelVisible(true, animated: true)
    }

    @objc func dismissKeyboardTapped() {
        view.endEditing(true)
    }

    private func openExternalLinkInSafari(_ url: URL) {
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    private func configureUtilityPanel() {
        utilityPanel.translatesAutoresizingMaskIntoConstraints = false
        utilityPanel.onClose = { [weak self] in
            self?.setUtilityPanelVisible(false, animated: true)
        }
        utilityPanel.onAndroidUserAgentChanged = { isOn in
            BrowserPreferences.shared.useAndroidUserAgent = isOn
        }
        view.addSubview(utilityPanel)
        let width = utilityPanel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.88)
        width.priority = .defaultHigh
        utilityPanelLeadingConstraint = utilityPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -380)
        NSLayoutConstraint.activate([
            utilityPanelLeadingConstraint!,
            utilityPanel.topAnchor.constraint(equalTo: view.topAnchor),
            utilityPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            width,
            utilityPanel.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
        ])
        utilityPanel.isHidden = true
    }

    private func setUtilityPanelVisible(_ visible: Bool, animated: Bool) {
        utilityPanelVisible = visible
        utilityPanel.syncControls()
        utilityPanel.isHidden = false
        view.bringSubviewToFront(utilityPanel)
        utilityPanelLeadingConstraint?.constant = visible ? 0 : -(utilityPanel.bounds.width > 0 ? utilityPanel.bounds.width : 380)
        let animations = {
            self.view.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { _ in
            self.utilityPanel.isHidden = !visible
        }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut], animations: animations, completion: completion)
        } else {
            animations()
            completion(true)
        }
    }

}

private final class UtilityPanelView: UIView {
    var onClose: (() -> Void)?
    var onAndroidUserAgentChanged: ((Bool) -> Void)?

    private let androidUASwitch = UISwitch()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemGroupedBackground
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 3, height: 0)

        let titleLabel = UILabel()
        titleLabel.text = "Downloads"
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titleLabel, closeButton])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12

        let uaLabel = UILabel()
        uaLabel.text = "Use Android User Agent"
        uaLabel.font = .systemFont(ofSize: 16, weight: .regular)

        androidUASwitch.addTarget(self, action: #selector(androidUASwitchChanged), for: .valueChanged)

        let uaRow = UIStackView(arrangedSubviews: [uaLabel, androidUASwitch])
        uaRow.translatesAutoresizingMaskIntoConstraints = false
        uaRow.axis = .horizontal
        uaRow.alignment = .center
        uaRow.spacing = 12
        uaRow.layoutMargins = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        uaRow.isLayoutMarginsRelativeArrangement = true
        uaRow.backgroundColor = .secondarySystemGroupedBackground
        uaRow.layer.cornerRadius = 10

        let downloadsView = DownloadsManagerView()

        addSubview(header)
        addSubview(uaRow)
        addSubview(downloadsView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 34),
            closeButton.heightAnchor.constraint(equalToConstant: 34),

            uaRow.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            uaRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            uaRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            downloadsView.topAnchor.constraint(equalTo: uaRow.bottomAnchor, constant: 8),
            downloadsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            downloadsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            downloadsView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        syncControls()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func syncControls() {
        androidUASwitch.isOn = BrowserPreferences.shared.useAndroidUserAgent
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func androidUASwitchChanged() {
        onAndroidUserAgentChanged?(androidUASwitch.isOn)
    }
}

final class BrowserSplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    private let browserViewController: BrowserViewController
    private var sidebarVisible = false
    private lazy var libraryViewController = UIViewController()

    override var shouldAutorotate: Bool {
        false
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    var contentBrowserViewController: BrowserViewController {
        browserViewController
    }

    private lazy var browserNavigationController: UINavigationController = {
        let navigationController = UINavigationController(rootViewController: browserViewController)
        navigationController.setNavigationBarHidden(true, animated: false)
        return navigationController
    }()

    private lazy var libraryNavigationController: UINavigationController = {
        let navigationController = UINavigationController(rootViewController: libraryViewController)
        navigationController.navigationBar.tintColor = .label
        return navigationController
    }()

    init(browserViewController: BrowserViewController) {
        self.browserViewController = browserViewController
        super.init(style: .doubleColumn)
        preferredDisplayMode = .secondaryOnly
        preferredSplitBehavior = .tile
        preferredPrimaryColumnWidth = 320
        minimumPrimaryColumnWidth = 280
        maximumPrimaryColumnWidth = 360
        presentsWithGesture = false
        showsSecondaryOnlyButton = false
        if #available(iOS 14.5, *) {
            displayModeButtonVisibility = .never
        }
        delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        setViewController(libraryNavigationController, for: .primary)
        setViewController(browserNavigationController, for: .secondary)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setLibrarySidebarVisible(_ visible: Bool) {
        sidebarVisible = visible
        if visible {
            show(.primary)
        } else {
            hide(.primary)
        }
        if browserViewController.isViewLoaded {
            browserViewController.applyChromeLayout(animated: false)
        }
    }

    func collapseLibrarySidebar(from sourceView: UIView?) {
        guard let sourceView,
              browserViewController.isViewLoaded,
              let containerView = viewIfLoaded,
              let snapshot = sourceView.snapshotView(afterScreenUpdates: false) else {
            setLibrarySidebarVisible(false)
            return
        }

        let destinationButton = browserViewController.browserUI.padTopBarButtons.sidebarButton
        let sourceFrame = sourceView.convert(sourceView.bounds, to: containerView)
        snapshot.frame = sourceFrame
        containerView.addSubview(snapshot)

        sourceView.isHidden = true
        setLibrarySidebarVisible(false)
        containerView.layoutIfNeeded()
        browserViewController.view.layoutIfNeeded()

        let destinationFrame = destinationButton.convert(destinationButton.bounds, to: containerView)
        destinationButton.alpha = 0
        destinationButton.isHidden = false

        UIView.animate(withDuration: 0.14, delay: 0, options: [.curveEaseOut]) {
            snapshot.frame = destinationFrame
            destinationButton.alpha = 1
        } completion: { _ in
            sourceView.isHidden = false
            destinationButton.alpha = 1
            snapshot.removeFromSuperview()
        }
    }

    func showLibrarySection(_ section: LibrarySection) {
    }

    var isLibrarySidebarVisible: Bool {
        sidebarVisible
    }

    func refreshSidebarVisibility() {
        sidebarVisible = displayMode != .secondaryOnly
        if browserViewController.isViewLoaded {
            browserViewController.applyChromeLayout(animated: false)
        }
    }

    func splitViewController(_ svc: UISplitViewController, willChangeTo displayMode: UISplitViewController.DisplayMode) {
        sidebarVisible = displayMode != .secondaryOnly
        if browserViewController.isViewLoaded {
            browserViewController.applyChromeLayout(animated: false)
        }
    }

    @objc private func applicationDidBecomeActive() {
        refreshSidebarVisibility()
    }
}

enum SidebarToggleButtonConfiguration {
    private static let fallbackImage = UIImage(systemName: "sidebar.left")

    static func configure(_ button: UIButton, in splitViewController: UISplitViewController?) {
        button.setImage(resolvedImage(in: splitViewController), for: .normal)
        button.accessibilityLabel = resolvedAccessibilityLabel(in: splitViewController)
    }

    private static func resolvedImage(in splitViewController: UISplitViewController?) -> UIImage? {
        splitViewController?.displayModeButtonItem.image ?? fallbackImage
    }

    private static func resolvedAccessibilityLabel(in splitViewController: UISplitViewController?) -> String? {
        splitViewController?.displayModeButtonItem.accessibilityLabel
    }
}
