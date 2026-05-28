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
        guard !isPadLayout else { return false }
        let isLandscape: Bool
        if let orientation = view.window?.windowScene?.interfaceOrientation {
            isLandscape = orientation.isLandscape
        } else {
            isLandscape = view.bounds.width > view.bounds.height
        }
        guard !isLandscape else { return false }
        return BrowserPreferences.shared.addressBarPosition == .top
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(addressBarPositionDidChange),
            name: Notification.Name("addressBarPositionChanged"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(landscapeTabBarDidChange),
            name: Notification.Name("landscapeTabBarChanged"),
            object: nil
        )
        browserLayout.configureLayout()
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
        browserUI.tabOverviewCollection.collectionView.collectionViewLayout.invalidateLayout()
        browserUI.padTabBar.collectionView.collectionViewLayout.invalidateLayout()
        tabOverviewPresentation.refreshForCurrentOrientation()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard !usesEmbeddedSplitRoot else {
            return
        }

        coordinator.animate { _ in
            self.syncBrowserNavigationChrome(animated: false)
            self.syncPadSidebarButtonItem()
            self.browserUI.tabOverviewCollection.collectionView.collectionViewLayout.invalidateLayout()
            self.browserUI.padTabBar.collectionView.collectionViewLayout.invalidateLayout()
        } completion: { _ in
            self.syncBrowserNavigationChrome(animated: false)
            self.syncPadSidebarButtonItem()
            self.browserUI.geckoView.transform = .identity
            self.tabOverviewPresentation.refreshForCurrentOrientation()
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

        if tabManager.tabs.count == 1 && tabManager.tabs[0].url == nil {
            return
        }

        _ = createTab(selecting: true, at: tabManager.tabs.count)
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

    @objc private func addressBarPositionDidChange() {
        browserLayout.applyChromeLayout(animated: true)
    }

    @objc private func landscapeTabBarDidChange() {
        browserLayout.applyChromeLayout(animated: true)
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
        guard isPadLayout else {
            return
        }

        (splitViewController as? BrowserSplitViewController)?.setLibrarySidebarVisible(visible)
        browserLayout.applyChromeLayout(animated: animated)
    }

    private func activeTabStripHeight() -> CGFloat {
        guard usesPadChromeLayout,
              tabManager.tabs.count > 1 else {
            return 0
        }

        if !isPadLayout {
            guard BrowserPreferences.shared.showsLandscapeTabBar else {
                return 0
            }
            let isLandscape: Bool
            if let orientation = view.window?.windowScene?.interfaceOrientation {
                isLandscape = orientation.isLandscape
            } else {
                isLandscape = view.bounds.width > view.bounds.height
            }
            guard isLandscape else {
                return 0
            }
        }

        return 36
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

        browserUI.tabOverviewCollection.collectionView.reloadData()
        browserUI.padTabBar.collectionView.reloadData()
        browserLayout.applyChromeLayout(animated: false)
    }

    func tabManager(_ tabManager: TabManager, didSelectTabAt index: Int, previousIndex: Int?) {
        if let previousIndex {
            captureThumbnail(for: previousIndex)
        }

        guard tabManager.tabs.indices.contains(index) else {
            return
        }

        let selectedTab = tabManager.tabs[index]
        browserUI.geckoView.session = selectedTab.session
        syncAddressBarLoadingState(progress: selectedTab.progress, isLoading: selectedTab.isLoading)
        refreshAddressBar()

        updateNavigationButtons()
        browserUI.tabOverviewCollection.collectionView.reloadData()
        browserUI.padTabBar.collectionView.reloadData()

        if usesPadChromeLayout {
            centerSelectedPadTab(animated: pendingSelectionAnimation)
        }
        pendingSelectionAnimation = false
    }

    func tabManager(_ tabManager: TabManager, didUpdateTabAt index: Int, reason: TabManagerUpdateReason) {
        guard tabManager.tabs.indices.contains(index) else {
            return
        }

        switch reason {
        case .title:
            browserUI.padTabBar.collectionView.reloadData()
            browserUI.tabOverviewCollection.collectionView.reloadData()

        case .location:
            if index == tabManager.selectedTabIndex {
                refreshAddressBar()
                updateNavigationButtons()
            }

        case .favicon:
            browserUI.padTabBar.collectionView.reloadData()
            browserUI.tabOverviewCollection.collectionView.reloadData()

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
            browserUI.tabOverviewCollection.collectionView.reloadData()
        }
    }

    func tabManager(_ tabManager: TabManager, animateNewTabSelectionAt index: Int, completion: @escaping () -> Void) {
        completion()
    }

    func tabManager(_ tabManager: TabManager, didRequestExternalOpen url: URL) {
        openExternalLinkInSafari(url)
    }

    func tabManager(_ tabManager: TabManager, shouldHandleExternalResponse response: ExternalResponseInfo, for session: GeckoSession) -> Bool {
        return false
    }

    func backButtonClicked() {
    }

    func forwardButtonClicked() {
    }

    func shareButtonClicked() {
    }

    func menuButtonClicked() {
    }

    func downloadsButtonClicked() {
    }

    func tabsButtonClicked() {
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
        let reloadGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleShellReloadGesture(_:)))
        reloadGesture.edges = .right
        reloadGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(reloadGesture)
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
        setLibrarySidebarVisible(!isLibrarySidebarVisible, animated: true)
    }

    @objc func padBackTapped() {
    }

    @objc func padForwardTapped() {
    }

    @objc func topBarMenuTapped() {
    }

    @objc func topBarDownloadsTapped() {
    }

    @objc func dismissKeyboardTapped() {
        view.endEditing(true)
    }

    private func openExternalLinkInSafari(_ url: URL) {
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
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
