import Foundation
import FridgeFreezeController
import FridgeModels
import FridgeProcessWatcher

public final class FridgeService: @unchecked Sendable {
    private let watcher: ProcessWatcher
    private let controller: FreezeController

    public init(
        watcher: ProcessWatcher = ProcessWatcher(),
        controller: FreezeController = FreezeController()
    ) {
        self.watcher = watcher
        self.controller = controller
    }

    public func status() throws -> FridgeStatus {
        let detected = try watcher.detectAIProcesses()
        let frozen = controller.frozenPIDs()
        let liveFrozen = frozen.filter { pid in
            detected.flatMap(\.allProcesses).contains { $0.pid == pid } || processExists(pid)
        }

        let state: FridgeState
        if !liveFrozen.isEmpty || detected.contains(where: \.isFrozen) {
            state = .frozen
        } else if detected.isEmpty {
            state = .idle
        } else {
            state = .running
        }

        return FridgeStatus(state: state, detected: detected, frozenPIDs: Array(liveFrozen).sorted())
    }

    @discardableResult
    public func freezeAll() throws -> FridgeStatus {
        let detected = try watcher.detectAIProcesses()
        try controller.freeze(detected)
        return try status()
    }

    @discardableResult
    public func resumeAll() throws -> FridgeStatus {
        try controller.resume()
        return try status()
    }

    @discardableResult
    public func toggle() throws -> FridgeStatus {
        let current = try status()
        if current.state == .frozen {
            return try resumeAll()
        }
        return try freezeAll()
    }

    private func processExists(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
