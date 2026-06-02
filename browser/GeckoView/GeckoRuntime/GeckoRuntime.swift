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

public class GeckoRuntime {
    static let runtime = GeckoRuntimeImpl()

    public enum ClearDataFlags {
        public static let networkCache = 1 << 1
        public static let imageCache = 1 << 2
        public static let domStorages = 1 << 4
    }
    
    public static var version: String {
        return GeckoRuntimeBridge.version()
    }
    
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

    public static func clearBaseDomainData(_ baseDomain: String, flags: Int) async throws {
        _ = try await GeckoEventDispatcherWrapper.runtimeInstance.query(
            type: "GeckoView:ClearBaseDomainData",
            message: [
                "baseDomain": baseDomain,
                "flags": flags,
            ]
        )
    }
}
