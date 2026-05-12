//
//  AddressBarMenu.swift
//  Reynard
//
//  Created by Minh Ton on 28/4/26.
//

import UIKit

enum AddressBarMenu {
    struct AddonItem {
        let menuItem: AddonMenuItem
        let image: UIImage?
    }
    
    private static let rootIdentifier = UIMenu.Identifier("me.minh-ton.reynard.address-bar-menu")
    private static let manageAddonsIdentifier = UIMenu.Identifier("me.minh-ton.reynard.address-bar-menu.manage-addons")
    static let presentAddonSettingsNotification = Notification.Name("me.minh-ton.reynard.address-bar-menu.present-addon-settings")
    static let changeWebsiteModeNotification = Notification.Name("me.minh-ton.reynard.address-bar-menu.toggle-website-mode")
    
    static func makeMenu(
        selectedTab: Tab?,
        selectedURL: String?,
        addonItems: [AddonItem]
    ) -> UIMenu? {
        return nil
    }
}
