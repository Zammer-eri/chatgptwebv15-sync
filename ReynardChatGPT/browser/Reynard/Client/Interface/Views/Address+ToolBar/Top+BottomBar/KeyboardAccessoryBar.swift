//
//  KeyboardAccessoryBar.swift
//  Reynard
//

import UIKit

final class KeyboardAccessoryBar {
    let view: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemChromeMaterial)
        let view = UIVisualEffectView(effect: blur)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 0
        view.isHidden = true
        return view
    }()

    let doneButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Done", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.tintColor = .label
        return button
    }()

    init() {
        view.contentView.addSubview(doneButton)
        NSLayoutConstraint.activate([
            doneButton.trailingAnchor.constraint(equalTo: view.contentView.layoutMarginsGuide.trailingAnchor, constant: -4),
            doneButton.centerYAnchor.constraint(equalTo: view.contentView.centerYAnchor),
        ])
    }
}
