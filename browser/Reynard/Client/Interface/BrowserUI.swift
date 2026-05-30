//
//  BrowserUI.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import GeckoView
import UIKit

final class BrowserUI {
    typealias TabCollectionHandler = UICollectionViewDataSource & UICollectionViewDelegate & UICollectionViewDelegateFlowLayout
    
    let geckoView: GeckoView = {
        let view = GeckoView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    lazy var chromeContainer = ChromeContainer()
    
    lazy var addressBar: AddressBar = {
        let bar = AddressBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.configure(delegate: self.controller)
        return bar
    }()
    
    lazy var keyboardDismissButton = KeyboardDismissButton()
    
    lazy var toolbarView: PhoneToolbar = {
        let bar = PhoneToolbar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.delegate = self.controller
        return bar
    }()
    
    lazy var topBar = PadTopBar()
    lazy var padTopBarButtons = PadTopBarButtons(controller: self.controller)
    lazy var padTabBar = PadTabBar(tabCollectionHandler: self.tabCollectionHandler)
    
    lazy var tabOverview = TabOverview()
    lazy var tabOverviewCollection = TabOverviewCollection(
        overviewInset: self.overviewInset,
        overviewSpacing: self.overviewSpacing,
        tabCollectionHandler: self.tabCollectionHandler
    )
    lazy var tabOverviewBottomBar = TabOverviewBottomBar()
    lazy var tabOverviewTopBar = TabOverviewTopBar()
    lazy var tabOverviewBarButtons = TabOverviewBarButtons(controller: self.controller)
    
    var geckoTopPhoneConstraint: NSLayoutConstraint!
    var geckoTopPadConstraint: NSLayoutConstraint!
    var geckoBottomPhoneConstraint: NSLayoutConstraint!
    var geckoBottomPhoneSearchPinnedConstraint: NSLayoutConstraint!
    var geckoBottomPhoneKeyboardOverlayConstraint: NSLayoutConstraint!
    var geckoBottomPadConstraint: NSLayoutConstraint!
    var geckoBottomCompactPadConstraint: NSLayoutConstraint!
    var geckoLeadingPhoneConstraint: NSLayoutConstraint!
    var geckoTrailingPhoneConstraint: NSLayoutConstraint!
    var geckoLeadingPadConstraint: NSLayoutConstraint!
    var geckoTrailingPadConstraint: NSLayoutConstraint!
    
    var phoneChromeBottomConstraint: NSLayoutConstraint!
    var phoneChromeHeightConstraint: NSLayoutConstraint!
    var phoneToolbarHeightConstraint: NSLayoutConstraint!
    var phoneToolbarTopConstraint: NSLayoutConstraint!
    var phoneToolbarCompactPadTopConstraint: NSLayoutConstraint!
    var addressBarPhoneLeadingConstraint: NSLayoutConstraint!
    var addressBarPhoneTrailingFullConstraint: NSLayoutConstraint!
    var addressBarPhoneTrailingFocusedConstraint: NSLayoutConstraint!
    var addressBarPhoneTopConstraint: NSLayoutConstraint!
    var addressBarPhoneHeightConstraint: NSLayoutConstraint!
    var addressBarPadLeadingConstraint: NSLayoutConstraint!
    var addressBarPadTrailingConstraint: NSLayoutConstraint!
    var addressBarCompactPadLeadingConstraint: NSLayoutConstraint!
    var addressBarCompactPadTrailingConstraint: NSLayoutConstraint!
    var addressBarPadCenterYConstraint: NSLayoutConstraint!
    var addressBarPadHeightConstraint: NSLayoutConstraint!
    
    private unowned let controller: BrowserViewController
    private let tabCollectionHandler: TabCollectionHandler
    private let overviewInset: CGFloat
    private let overviewSpacing: CGFloat
    
    init(
        controller: BrowserViewController,
        overviewInset: CGFloat,
        overviewSpacing: CGFloat,
        tabCollectionHandler: TabCollectionHandler
    ) {
        self.controller = controller
        self.overviewInset = overviewInset
        self.overviewSpacing = overviewSpacing
        self.tabCollectionHandler = tabCollectionHandler
    }
}
