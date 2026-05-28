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
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = 18
        view.clipsToBounds = true
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
            doneButton.leadingAnchor.constraint(equalTo: view.contentView.leadingAnchor, constant: 14),
            doneButton.trailingAnchor.constraint(equalTo: view.contentView.trailingAnchor, constant: -14),
            doneButton.topAnchor.constraint(equalTo: view.contentView.topAnchor),
            doneButton.bottomAnchor.constraint(equalTo: view.contentView.bottomAnchor),
        ])
    }
}
