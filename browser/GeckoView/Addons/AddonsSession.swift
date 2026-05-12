//
//  AddonsSession.swift
//  Reynard
//
//  Created by Minh Ton on 28/4/26.
//

import Foundation

public extension GeckoSession {
    func setAddonTabActive(_ active: Bool) {
        // Disabled for the ChatGPT shell. The shell does not expose Reynard's
        // extension UI, and early WebExtension messages crash Gecko on iOS 15.6.
    }
}
