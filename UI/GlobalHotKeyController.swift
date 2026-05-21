import Carbon
import Foundation

import AppKit

@MainActor
public final class GlobalHotKeyController {
    public enum RegistrationState: Equatable {
        case notRegistered
        case registered
        case failed(OSStatus)
    }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void

    public private(set) var state: RegistrationState = .notRegistered

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public func registerPauseKey() {
        guard hotKeyRef == nil else { return }

        let eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        var handler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<GlobalHotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                Task { @MainActor in
                    controller.action()
                }

                return noErr
            },
            1,
            [eventType],
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )

        guard installStatus == noErr else {
            state = .failed(installStatus)
            return
        }

        eventHandler = handler

        var hotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharCode("FRDG"), id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_F15),
            0,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )

        if registerStatus == noErr {
            hotKeyRef = hotKey
            state = .registered
        } else {
            state = .failed(registerStatus)
        }
    }
}

@MainActor
final class FnDoubleTapController {
    private let doubleTapWindow: TimeInterval
    private let action: () -> Void
    private var monitor: Any?
    private var wasFunctionPressed = false
    private var lastFunctionTapAt: Date?

    init(doubleTapWindow: TimeInterval = 0.45, action: @escaping () -> Void) {
        self.doubleTapWindow = doubleTapWindow
        self.action = action
    }

    func start() {
        guard monitor == nil else { return }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        wasFunctionPressed = false
        lastFunctionTapAt = nil
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == UInt16(kVK_Function) else {
            wasFunctionPressed = event.modifierFlags.contains(.function)
            return
        }

        let isFunctionPressed = event.modifierFlags.contains(.function)
        defer { wasFunctionPressed = isFunctionPressed }

        guard isFunctionPressed, !wasFunctionPressed else { return }

        let now = Date()
        if let lastFunctionTapAt,
           now.timeIntervalSince(lastFunctionTapAt) <= doubleTapWindow {
            self.lastFunctionTapAt = nil
            action()
            return
        }

        lastFunctionTapAt = now
    }
}

private func fourCharCode(_ text: String) -> OSType {
    text.utf8.reduce(0) { result, byte in
        (result << 8) + OSType(byte)
    }
}
