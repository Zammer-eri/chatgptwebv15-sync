//
//  JITController.swift
//  Reynard
//
//  Created by Minh Ton on 11/3/26.
//

import Foundation
import Darwin
import UIKit

final class JITController {
    static let shared = JITController()

    private let attachQueue = DispatchQueue(label: "me.minh-ton.jit.jit-attach-queue", qos: .userInitiated)
    private let watchdogQueue = DispatchQueue(label: "me.minh-ton.jit.jit-preflight-watchdog", qos: .userInitiated)
    private var attachedPIDs: Set<Int32> = []
    private var preflightWatchdogs: [Int32: DispatchWorkItem] = [:]
    private var hasHandledFailure = false
    private(set) var isJITLessModeActive = false
    private var pendingFailureAction: (() -> Void)?
    private let preflightTimeoutSeconds: Int = 5
    private let failurePresentationRetryLimit = 12

    private init() {}

    private func usePtraceJIT() -> Bool {
        getEntitlementValue("com.apple.private.security.no-sandbox")
    }

    func start() {
        guard usePtraceJIT() else {
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChildProcessNotification(_:)),
            name: NSNotification.Name("GeckoRuntimeChildProcessDidStart"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    private func shouldAttach(to processType: String) -> Bool {
        let normalized = processType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "tab"
    }

    func childProcessDidStart(pid: Int32, processType: String) {
        guard pid > 0 else {
            return
        }

        guard !isJITLessModeActive, !hasHandledFailure, usePtraceJIT() else {
            ReportJITStatusForChild(pid, false, false)
            return
        }

        guard shouldAttach(to: processType) else {
            ReportJITStatusForChild(pid, false, false)
            return
        }

        attachQueue.async {
            if self.attachedPIDs.contains(pid) {
                return
            }
            self.attachedPIDs.insert(pid)
            self.schedulePreflightWatchdog(for: pid)
            self.attachToProcess(pid: pid)
        }
    }

    private func attachToProcess(pid: Int32) {
        do {
            try JITEnabler.shared.enableJIT(forPID: pid, hasTXM26: false)
            cancelPreflightWatchdog(for: pid)
            ReportJITStatusForChild(pid, true, false)
        } catch {
            let nsError = error as NSError
            cancelPreflightWatchdog(for: pid)
            ReportJITStatusForChild(pid, false, false)
            handleJITFailure(error: nsError)
        }
    }

    private func schedulePreflightWatchdog(for pid: Int32) {
        var watchdog: DispatchWorkItem?
        watchdog = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            guard let watchdog, !watchdog.isCancelled else {
                return
            }

            ReportJITStatusForChild(pid, false, false)
            self.handleJITFailure(error: NSError(domain: "Reynard.JIT", code: Int(ETIMEDOUT), userInfo: nil))
        }

        guard let watchdog else {
            return
        }

        preflightWatchdogs[pid] = watchdog
        watchdogQueue.asyncAfter(deadline: .now() + .seconds(preflightTimeoutSeconds), execute: watchdog)
    }

    private func cancelPreflightWatchdog(for pid: Int32) {
        preflightWatchdogs[pid]?.cancel()
        preflightWatchdogs.removeValue(forKey: pid)
    }

    private func cancelAllPreflightWatchdogs() {
        for pid in preflightWatchdogs.keys {
            cancelPreflightWatchdog(for: pid)
        }
    }

    private func handleJITFailure(error: NSError) {
        DispatchQueue.main.async {
            guard !self.hasHandledFailure else {
                return
            }
            self.hasHandledFailure = true
            self.presentEnablementFailureScreen(
                error: error,
                showsErrorDetails: error.code != Int(ETIMEDOUT)
            )
        }
    }

    private func presentEnablementFailureScreen(error: NSError, showsErrorDetails: Bool, retryCount: Int = 0) {
        guard retryCount <= failurePresentationRetryLimit else {
            return
        }

        guard Self.canPresentFailureUI() else {
            pendingFailureAction = { [weak self] in
                self?.presentEnablementFailureScreen(error: error, showsErrorDetails: showsErrorDetails)
            }
            return
        }

        guard let presenter = Self.topViewControllerForPresentation() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
                self.presentEnablementFailureScreen(error: error, showsErrorDetails: showsErrorDetails, retryCount: retryCount + 1)
            }
            return
        }

        let description = error.localizedDescription.isEmpty ? "Unknown error." : error.localizedDescription
        let viewController = JITFailureViewController(
            errorCode: error.code,
            errorDescription: description,
            showsErrorDetails: showsErrorDetails,
            titleText: "Failed to enable JIT",
            messageText: "Make sure this build is installed through TrollStore and that the bundled ptrace_jit helper is present.",
            actionButtonTitle: "Activate JIT-Less Mode",
            onPrimaryAction: { [weak self] in
                self?.activateJITLessMode()
            }
        )
        viewController.modalPresentationStyle = .pageSheet
        viewController.modalTransitionStyle = .coverVertical
        presenter.present(viewController, animated: true)
    }

    private func activateJITLessMode() {
        guard !isJITLessModeActive else {
            return
        }

        isJITLessModeActive = true
        attachQueue.async {
            self.cancelAllPreflightWatchdogs()
            self.attachedPIDs.removeAll()
            JITEnabler.shared.detachAllJITSessions()
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "me.minh-ton.reynard.jitless-mode-activated"), object: nil)
        }
    }

    private static func topViewControllerForPresentation() -> UIViewController? {
        let foregroundScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        guard let scene = foregroundScenes.first else {
            return nil
        }

        let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        ?? scene.windows.first(where: { !$0.isHidden })?.rootViewController

        guard let root else {
            return nil
        }

        return topPresentedViewController(from: root)
    }

    private static func topPresentedViewController(from root: UIViewController) -> UIViewController {
        var current = root
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }

    private static func canPresentFailureUI() -> Bool {
        guard UIApplication.shared.applicationState == .active else {
            return false
        }

        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.activationState == .foregroundActive }
    }

    @objc private func handleApplicationDidBecomeActive() {
        let action = pendingFailureAction
        pendingFailureAction = nil
        action?()
    }

    @objc private func handleChildProcessNotification(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let pidNumber = userInfo["pid"] as? NSNumber,
            let processType = userInfo["processType"] as? String
        else {
            return
        }

        childProcessDidStart(pid: pidNumber.int32Value, processType: processType)
    }
}
