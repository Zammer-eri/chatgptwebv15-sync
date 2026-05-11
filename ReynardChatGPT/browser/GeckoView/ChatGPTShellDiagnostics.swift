//
//  ChatGPTShellDiagnostics.swift
//  GeckoView
//

import Foundation
import UIKit

public enum ChatGPTShellDiagnostics {
    private static let fileName = "chatgpt-shell-diagnostics.log"
    private static let maxFileSize = 1024 * 1024
    private static let maxStringLength = 360
    private static let queue = DispatchQueue(label: "chatgpt.shell.diagnostics")

    public static var logFileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return (documents ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent(fileName)
    }

    public static func start(fields: [String: Any?] = [:]) {
        var merged = fields
        merged["path"] = logFileURL.path
        merged["bundle"] = Bundle.main.bundleIdentifier
        merged["version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        merged["build"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
        log("diagnostics.start", fields: merged)
    }

    public static func log(_ event: String, fields: [String: Any?] = [:]) {
        var merged = fields
        merged["mainThread"] = Thread.isMainThread

        let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
        let payload = formatFields(merged)
        let line = payload.isEmpty ? "\(timestamp) \(event)\n" : "\(timestamp) \(event) \(payload)\n"
        NSLog("%@", line.trimmingCharacters(in: .newlines))

        queue.async {
            write(line)
        }
    }

    public static func describeResponder(_ responder: UIResponder?) -> String {
        guard let responder else {
            return "nil"
        }

        var parts = ["class=\(String(describing: type(of: responder)))"]
        parts.append("first=\(responder.isFirstResponder)")

        if let view = responder as? UIView {
            parts.append("window=\(view.window != nil)")
            parts.append("frame=\(formatRect(view.frame))")
            parts.append("hidden=\(view.isHidden)")
            parts.append("alpha=\(String(format: "%.2f", Double(view.alpha)))")
        }

        if responder is UITextInput {
            parts.append("textInput=true")
        }

        return parts.joined(separator: ",")
    }

    public static func currentFirstResponder() -> UIResponder? {
        ChatGPTShellFirstResponderCapture.responder = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.chatGPTShellCaptureFirstResponder(_:)),
            to: nil,
            from: nil,
            for: nil
        )
        let responder = ChatGPTShellFirstResponderCapture.responder
        ChatGPTShellFirstResponderCapture.responder = nil
        return responder
    }

    public static func describeRect(_ rect: CGRect) -> String {
        formatRect(rect)
    }

    private static func write(_ line: String) {
        let fileManager = FileManager.default
        let url = logFileURL
        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber,
           size.intValue > maxFileSize {
            try? fileManager.removeItem(at: url)
        }

        if !fileManager.fileExists(atPath: url.path) {
            _ = fileManager.createFile(atPath: url.path, contents: nil)
        }

        guard let data = line.data(using: .utf8),
              let handle = FileHandle(forWritingAtPath: url.path) else {
            return
        }

        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    }

    private static func formatFields(_ fields: [String: Any?]) -> String {
        fields.keys.sorted().map { key in
            let value: Any?
            switch fields[key] {
            case .some(let wrapped):
                value = wrapped
            case .none:
                value = nil
            }
            return "\(key)=\(formatValue(value))"
        }.joined(separator: " ")
    }

    private static func formatValue(_ value: Any?) -> String {
        guard let value else {
            return "nil"
        }

        if value is NSNull {
            return "null"
        }

        if let string = value as? String {
            return quoted(string)
        }

        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        return quoted(String(describing: value))
    }

    private static func quoted(_ value: String) -> String {
        var normalized = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\"", with: "'")

        if normalized.count > maxStringLength {
            normalized = String(normalized.prefix(maxStringLength)) + "..."
        }

        return "\"\(normalized)\""
    }

    private static func formatRect(_ rect: CGRect) -> String {
        String(
            format: "%.1f,%.1f,%.1f,%.1f",
            Double(rect.origin.x),
            Double(rect.origin.y),
            Double(rect.size.width),
            Double(rect.size.height)
        )
    }
}

private final class ChatGPTShellFirstResponderCapture {
    static var responder: UIResponder?
}

extension UIResponder {
    @objc func chatGPTShellCaptureFirstResponder(_ sender: Any?) {
        ChatGPTShellFirstResponderCapture.responder = self
    }
}
