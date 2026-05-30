//
//  GeckoEventDispatcher.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import Foundation

struct GeckoHandlerError: Error {
    let value: Any?

    init(_ value: Any?) {
        self.value = value
    }
}

protocol GeckoEventListenerInternal {
    @MainActor
    func handleMessage(type: String, message: [String: Any?]?) async throws -> Any?
}

extension GeckoEventListenerInternal {
    func handleMessage(type: String, message: [String: Any?]?, callback: EventCallback?) {
        Task { @MainActor in
            do {
                let result = try await self.handleMessage(type: type, message: message)
                callback?.sendSuccess(result)
            } catch let error as GeckoHandlerError {
                callback?.sendError(error.value)
            } catch {
                callback?.sendError("\(error)")
            }
        }
    }
}

public class GeckoEventDispatcherWrapper: NSObject, SwiftEventDispatcher {
    static var runtimeInstance = GeckoEventDispatcherWrapper()
    static var dispatchers: [String: GeckoEventDispatcherWrapper] = [:]

    struct QueuedMessage {
        let type: String
        let message: [String: Any]?
        let callback: EventCallback?
    }

    var gecko: (any GeckoEventDispatcher)?
    var queue: [QueuedMessage]? = []
    var listeners: [String: [GeckoEventListenerInternal]] = [:]
    var name: String?
    private var pendingQueryCallbacks: [UUID: AnyObject] = [:]
    private let pendingQueryCallbacksLock = NSLock()

    override init() {}

    init(name: String) {
        self.name = name
    }

    public static func lookup(byName: String) -> GeckoEventDispatcherWrapper {
        if let dispatcher = dispatchers[byName] {
            return dispatcher
        }
        let newDispatcher = GeckoEventDispatcherWrapper(name: byName)
        dispatchers[byName] = newDispatcher
        return newDispatcher
    }

    func addListener(type: String, listener: GeckoEventListenerInternal) {
        listeners[type, default: []] += [listener]
    }

    public func dispatch(
        type: String, message: [String: Any]? = nil, callback: EventCallback? = nil
    ) {
        if let eventListeners = listeners[type] {
            for listener in eventListeners {
                listener.handleMessage(type: type, message: optionalMessage(message), callback: callback)
            }
        } else if queue != nil {
            queue!.append(QueuedMessage(type: type, message: message, callback: callback))
        } else {
            gecko?.dispatch(toGecko: type, message: message, callback: callback)
        }
    }

    public func query(type: String, message: [String: Any]? = nil) async throws -> Any? {
        final class CallbackBox {
            var cancel: (() -> Void)?
        }

        class AsyncCallback: NSObject, EventCallback {
            private let lock = NSLock()
            var continuation: CheckedContinuation<Any?, Error>?
            var release: (() -> Void)?

            init(_ continuation: CheckedContinuation<Any?, Error>, release: @escaping () -> Void) {
                self.continuation = continuation
                self.release = release
            }

            func sendSuccess(_ response: Any?) {
                complete(.success(response))
            }

            func sendError(_ response: Any?) {
                complete(.failure(GeckoHandlerError(response)))
            }

            deinit {
                complete(.failure(GeckoHandlerError("callback never invoked")))
            }

            private func complete(_ result: Result<Any?, Error>) {
                lock.lock()
                let continuation = continuation
                let release = release
                self.continuation = nil
                self.release = nil
                lock.unlock()

                guard let continuation else {
                    return
                }

                release?()
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        let callbackID = UUID()
        let callbackBox = CallbackBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let callback = AsyncCallback(continuation) { [weak self] in
                    self?.releaseQueryCallback(id: callbackID)
                }
                callbackBox.cancel = {
                    callback.sendError("query cancelled")
                }
                retainQueryCallback(callback, id: callbackID)
                dispatch(type: type, message: message, callback: callback)
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    callback.sendError("query timed out")
                }
            }
        } onCancel: {
            callbackBox.cancel?()
        }
    }

    public func attach(_ dispatcher: (any GeckoEventDispatcher)?) {
        gecko = dispatcher
    }

    public func dispatch(toSwift type: String!, message: Any!, callback: EventCallback?) {
        let message = optionalMessage(message as? [String: Any])
        if let eventListeners = listeners[type] {
            for listener in eventListeners {
                listener.handleMessage(type: type, message: message, callback: callback)
            }
        }
    }

    public func activate() {
        if let queue = self.queue {
            self.queue = nil
            for event in queue {
                gecko?.dispatch(toGecko: event.type, message: event.message, callback: event.callback)
            }
        }
    }

    public func hasListener(_ type: String!) -> Bool {
        listeners.keys.contains(type)
    }

    private func optionalMessage(_ message: [String: Any]?) -> [String: Any?]? {
        message?.mapValues { value in
            value is NSNull ? nil : value
        }
    }

    private func retainQueryCallback(_ callback: AnyObject, id: UUID) {
        pendingQueryCallbacksLock.lock()
        pendingQueryCallbacks[id] = callback
        pendingQueryCallbacksLock.unlock()
    }

    private func releaseQueryCallback(id: UUID) {
        pendingQueryCallbacksLock.lock()
        pendingQueryCallbacks[id] = nil
        pendingQueryCallbacksLock.unlock()
    }
}
