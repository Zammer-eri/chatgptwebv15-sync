//
//  ChatGPTShellDiagnostics.swift
//  GeckoView
//

import CoreGraphics
import Foundation

public enum ChatGPTShellDiagnostics {
    private static let fileName = "chatgpt-shell-diagnostics.log"
    private static let maxFileSize = 1024 * 1024
    private static let maxValueLength = 360
    private static let queue = DispatchQueue(label: "chatgpt.shell.diagnostics")

    public static var logFilePath: String {
        let directories = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let directory = directories.first ?? NSTemporaryDirectory()
        return (directory as NSString).appendingPathComponent(fileName)
    }

    public static func start(fields: [String: Any] = [:]) {
        var values = fields
        values["path"] = logFilePath
        values["bundle"] = Bundle.main.bundleIdentifier ?? "nil"
        values["version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "nil"
        values["build"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "nil"
        log("diagnostics.start", fields: values)
    }

    public static func log(_ event: String, fields: [String: Any] = [:]) {
        var values = fields
        values["mainThread"] = Thread.isMainThread

        let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
        let body = formatFields(values)
        let line = body.isEmpty ? "\(timestamp) \(event)\n" : "\(timestamp) \(event) \(body)\n"
        NSLog("%@", line.trimmingCharacters(in: .newlines))

        queue.async {
            append(line)
        }
    }

    public static func describeObject(_ value: Any?) -> String {
        guard let value = value else {
            return "nil"
        }
        return String(describing: type(of: value))
    }

    public static func describeRect(_ rect: CGRect) -> String {
        return String(
            format: "%.1f,%.1f,%.1f,%.1f",
            Double(rect.origin.x),
            Double(rect.origin.y),
            Double(rect.size.width),
            Double(rect.size.height)
        )
    }

    private static func append(_ line: String) {
        let path = logFilePath
        let manager = FileManager.default
        let directory = (path as NSString).deletingLastPathComponent

        if !manager.fileExists(atPath: directory) {
            try? manager.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
        }

        if let attributes = try? manager.attributesOfItem(atPath: path),
           let size = attributes[.size] as? NSNumber,
           size.intValue > maxFileSize {
            try? manager.removeItem(atPath: path)
        }

        if !manager.fileExists(atPath: path) {
            _ = manager.createFile(atPath: path, contents: nil, attributes: nil)
        }

        guard let data = line.data(using: .utf8),
              let handle = FileHandle(forWritingAtPath: path) else {
            return
        }

        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    }

    private static func formatFields(_ fields: [String: Any]) -> String {
        return fields.keys.sorted().map { key in
            return "\(key)=\(formatValue(fields[key] ?? "nil"))"
        }.joined(separator: " ")
    }

    private static func formatValue(_ value: Any) -> String {
        if value is NSNull {
            return "null"
        }

        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        return quote(String(describing: value))
    }

    private static func quote(_ value: String) -> String {
        var output = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\"", with: "'")

        if output.count > maxValueLength {
            output = String(output.prefix(maxValueLength)) + "..."
        }

        return "\"\(output)\""
    }
}
