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

    let sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Send", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.tintColor = .label
        return button
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
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator

        let stack = UIStackView(arrangedSubviews: [sendButton, separator, doneButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fill
        view.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: view.contentView.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: view.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.contentView.bottomAnchor),
            sendButton.widthAnchor.constraint(equalTo: doneButton.widthAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
    }
}
