import Carbon
import Foundation

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

private func fourCharCode(_ text: String) -> OSType {
    text.utf8.reduce(0) { result, byte in
        (result << 8) + OSType(byte)
    }
}
