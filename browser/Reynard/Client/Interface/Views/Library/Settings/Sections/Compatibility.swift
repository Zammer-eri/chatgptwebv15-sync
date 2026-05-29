//
//  Compatibility.swift
//  Reynard
//
//  Created by Minh Ton on 11/4/26.
//

import UIKit

extension SettingsRootViewController {
    @objc func androidUASwitchChanged() {
        preferences.useAndroidUserAgent = androidUASwitch.isOn
        guard let section = visibleSections.firstIndex(of: .compatibility),
              let footer = tableView.footerView(forSection: section) else {
            return
        }
        footer.textLabel?.text = tableView(tableView, titleForFooterInSection: section)
        footer.sizeToFit()
    }
}
