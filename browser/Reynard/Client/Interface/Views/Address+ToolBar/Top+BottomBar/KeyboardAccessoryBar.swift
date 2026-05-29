//
//  KeyboardAccessoryBar.swift
//  Reynard
//

import UIKit

final class KeyboardAccessoryBar {
    let view: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 0
        view.isHidden = true
        return view
    }()

    private static func makePill() -> UIVisualEffectView {
        let blur = UIBlurEffect(style: .systemChromeMaterial)
        let view = UIVisualEffectView(effect: blur)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = 18
        view.clipsToBounds = true
        return view
    }

    private let sendPill = makePill()
    private let donePill = makePill()

    let sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Send", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.tintColor = .systemBlue
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
        let stack = UIStackView(arrangedSubviews: [sendPill, donePill])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 8
        stack.distribution = .fillEqually
        view.addSubview(stack)
        sendPill.contentView.addSubview(sendButton)
        donePill.contentView.addSubview(doneButton)
        configurePressFeedback(for: sendButton, pill: sendPill)
        configurePressFeedback(for: doneButton, pill: donePill)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sendButton.leadingAnchor.constraint(equalTo: sendPill.contentView.leadingAnchor, constant: 14),
            sendButton.trailingAnchor.constraint(equalTo: sendPill.contentView.trailingAnchor, constant: -14),
            sendButton.topAnchor.constraint(equalTo: sendPill.contentView.topAnchor),
            sendButton.bottomAnchor.constraint(equalTo: sendPill.contentView.bottomAnchor),
            doneButton.leadingAnchor.constraint(equalTo: donePill.contentView.leadingAnchor, constant: 14),
            doneButton.trailingAnchor.constraint(equalTo: donePill.contentView.trailingAnchor, constant: -14),
            doneButton.topAnchor.constraint(equalTo: donePill.contentView.topAnchor),
            doneButton.bottomAnchor.constraint(equalTo: donePill.contentView.bottomAnchor),
        ])
    }

    private func configurePressFeedback(for button: UIButton, pill: UIView) {
        button.addAction(
            UIAction { [weak pill] _ in
                Self.animatePress(on: pill)
            },
            for: .touchDown
        )
        button.addAction(
            UIAction { [weak pill] _ in
                Self.animateRelease(on: pill)
            },
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
    }

    private static func animatePress(on view: UIView?) {
        UIView.animate(
            withDuration: 0.09,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            view?.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            view?.alpha = 0.72
        }
    }

    private static func animateRelease(on view: UIView?) {
        UIView.animate(
            withDuration: 0.16,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            view?.transform = .identity
            view?.alpha = 1
        }
    }
}
