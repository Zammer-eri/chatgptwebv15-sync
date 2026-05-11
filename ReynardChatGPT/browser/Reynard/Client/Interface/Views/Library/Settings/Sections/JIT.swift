//
//  JIT.swift
//  Reynard
//
//  Created by Minh Ton on 11/4/26.
//

import UIKit

extension SettingsRootViewController {
    func makeJITFooterView() -> UIView {
        UIView(frame: .zero)
    }

    func presentPairingFilePicker() {
        presentAlert(
            title: "JIT Uses TrollStore",
            message: "This ChatGPT build only supports TrollStore ptrace JIT. Pairing-file JIT is not included."
        )
    }

    @objc func jitSwitchChanged(_ sender: UISwitch) {
        sender.setOn(false, animated: true)
        presentPairingFilePicker()
    }

    @objc func handleJITLessModeActivated(_ notification: Notification) {
        refreshControls()
        tableView.reloadData()
    }

    func presentJITRestartAlert() {
        presentPairingFilePicker()
    }
}
