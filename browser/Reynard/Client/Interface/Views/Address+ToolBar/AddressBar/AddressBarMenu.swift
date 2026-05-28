//
//  AddressBarMenu.swift
//  Reynard
//
//  Created by Minh Ton on 28/4/26.
//

import UIKit

enum AddressBarMenu {
    private static let rootIdentifier = UIMenu.Identifier("me.minh-ton.reynard.address-bar-menu")
    static let changeWebsiteModeNotification = Notification.Name("me.minh-ton.reynard.address-bar-menu.toggle-website-mode")

    static func makeMenu(selectedURL: String?) -> UIMenu? {
        guard selectedURL?.isEmpty == false else {
            return nil
        }

        let children: [UIMenuElement] = [
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
        ]

        return UIMenu(title: "", identifier: rootIdentifier, children: children)
    }
}
