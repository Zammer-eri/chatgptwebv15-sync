//
//  GeckoRuntime.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import Foundation
import UIKit

class GeckoRuntimeImpl: NSObject, SwiftGeckoViewRuntime {
    func runtimeDispatcher() -> any SwiftEventDispatcher {
        return GeckoEventDispatcherWrapper.runtimeInstance
    }
    
    func dispatcher(byName name: UnsafePointer<CChar>!) -> any SwiftEventDispatcher {
        return GeckoEventDispatcherWrapper.lookup(byName: String(cString: name))
    }
    
    @objc(childProcessDidStartWithPID:processType:)
    func childProcessDidStart(withPID pid: Int32, processType: String) {
        GeckoDiagnostics.log("childProcessDidStart pid=\(pid) type=\(processType)")

        // Update jetsam limit for the child process
        updateJetsamControl(pid)

        NotificationCenter.default.post(
            name: Notification.Name("GeckoRuntimeChildProcessDidStart"),
            object: nil,
            userInfo: [
                "pid": NSNumber(value: pid),
                "processType": processType
            ]
        )
    }
}

private enum GeckoDiagnostics {
    private static let queue = DispatchQueue(label: "com.codex.chatgpt.gecko-diagnostics")
    private static let maxLogBytes: UInt64 = 1_000_000

    static func log(_ message: String) {
        let line = "[CHATGPT_SHELL_DIAG] \(timestamp()) \(message)"
        NSLog("%@", line)
        writeToFile(line)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func writeToFile(_ line: String) {
        queue.async {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
                  let data = (line + "\n").data(using: .utf8) else {
                return
            }

            let fileURL = documentsURL.appendingPathComponent("ChatGPTShellDiagnostics.log", isDirectory: false)
            rotateLogIfNeeded(at: fileURL)

            if FileManager.default.fileExists(atPath: fileURL.path),
               let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                return
            }

            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func rotateLogIfNeeded(at fileURL: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? UInt64,
              fileSize > maxLogBytes else {
            return
        }

        let rotatedURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("ChatGPTShellDiagnostics.previous.log", isDirectory: false)
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: fileURL, to: rotatedURL)
    }
}

public class GeckoRuntime {
    static let runtime = GeckoRuntimeImpl()
    
    public static func main(
        argc: Int32,
        argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>
    ) {
        MainProcessInit(argc, argv, runtime)
    }
    
    public static func childMain(
        xpcConnection: xpc_connection_t,
        process: GeckoProcessExtension
    ) {
        ChildProcessInit(xpcConnection, process, runtime)
    }
}
