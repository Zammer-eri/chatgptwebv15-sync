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
    static let presentAddonSettingsNotification = Notification.Name("me.minh-ton.reynard.address-bar-menu.present-addon-settings")
    static let changeWebsiteModeNotification = Notification.Name("me.minh-ton.reynard.address-bar-menu.toggle-website-mode")

    static func makeMenu(
        selectedURL: String?,
        addonItems: [AddonItem]
    ) -> UIMenu? {
        guard selectedURL?.isEmpty == false || !addonItems.isEmpty else {
            return nil
        }

        var children: [UIMenuElement] = []

        if !addonItems.isEmpty {
            let addonActions = addonItems.map { item in
                UIAction(
                    title: item.menuItem.title,
                    image: item.image
                ) { _ in
                    NotificationCenter.default.post(
                        name: presentAddonSettingsNotification,
                        object: nil,
                        userInfo: ["addonItem": item.menuItem]
                    )
                }
            }
            children.append(UIMenu(title: "Add-ons", options: .displayInline, children: addonActions))
        }

        children.append(
            UIMenu(
                title: "",
                options: .displayInline,
                children: [
                    UIAction(title: "Request Desktop Website", image: UIImage(systemName: "desktopcomputer")) { _ in
                        NotificationCenter.default.post(
                            name: changeWebsiteModeNotification,
                            object: nil
                        )
                    },
                ]
            )
        )

        return UIMenu(title: "", identifier: rootIdentifier, children: children)
    }
}
