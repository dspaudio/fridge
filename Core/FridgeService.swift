import Foundation
import FridgeFreezeController
import FridgeModels
import FridgeProcessWatcher

public final class FridgeService: @unchecked Sendable {
    private let watcher: ProcessWatcher
    private let controller: FreezeController
    private let freezeContextStore: FreezeContextStore
    private let terminalNoticeWriter: TerminalNoticeWriter

    public init(
        watcher: ProcessWatcher = ProcessWatcher(),
        controller: FreezeController = FreezeController(),
        freezeContextStore: FreezeContextStore = FreezeContextStore(),
        terminalNoticeWriter: TerminalNoticeWriter = TerminalNoticeWriter()
    ) {
        self.watcher = watcher
        self.controller = controller
        self.freezeContextStore = freezeContextStore
        self.terminalNoticeWriter = terminalNoticeWriter
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
    public func freezeAll(
        reason: String = "manual freeze request",
        source: String = "fridge",
        resumeHint: String = "fridge resume"
    ) throws -> FridgeStatus {
        let detected = try watcher.detectAIProcesses()
        try controller.freeze(detected)
        let frozenStatus = try status()
        let context = makeFreezeContext(
            status: frozenStatus,
            reason: reason,
            source: source
        )
        try freezeContextStore.save(context)
        terminalNoticeWriter.writeFreezeNotice(record: context, status: frozenStatus, resumeHint: resumeHint)
        return frozenStatus
    }

    @discardableResult
    public func resumeAll() throws -> FridgeStatus {
        let context = freezeContextStore.load()
        try controller.resume()
        try freezeContextStore.clear()
        let resumedStatus = try status()
        terminalNoticeWriter.writeResumeNotice(record: context, status: resumedStatus)
        return resumedStatus
    }

    @discardableResult
    public func toggle() throws -> FridgeStatus {
        let current = try status()
        if current.state == .frozen {
            return try resumeAll()
        }
        return try freezeAll(
            reason: "toggle requested while agents were running",
            source: "fridge",
            resumeHint: "Pause again"
        )
    }

    private func makeFreezeContext(status: FridgeStatus, reason: String, source: String) -> FreezeContextRecord {
        let frozen = Set(status.frozenPIDs)
        let processes = status.detected.flatMap { group in
            group.allProcesses
                .filter { frozen.contains($0.pid) || $0.isStopped }
                .map { process in
                    FrozenProcessContext(
                        name: process.displayName,
                        pid: process.pid,
                        parentPID: process.parentPID,
                        terminal: process.terminal,
                        command: process.command,
                        arguments: process.arguments,
                        matchedBy: group.matchedBy
                    )
                }
        }

        let pidList = status.frozenPIDs.map(String.init).joined(separator: ",")
        let resumesAt = if pidList.isEmpty {
            "fridge resume sends SIGCONT to the stored frozen processes and they continue from their suspended instruction."
        } else {
            "fridge resume sends SIGCONT to pid(s) \(pidList); each process continues from the same suspended instruction with its existing terminal/session context."
        }

        return FreezeContextRecord(
            id: UUID().uuidString,
            createdAt: Date(),
            source: source,
            reason: reason,
            lastTool: nil,
            cwd: FileManager.default.currentDirectoryPath,
            activeChildPID: status.frozenPIDs.first,
            pendingPromptSummary: reason,
            frozenPIDs: status.frozenPIDs,
            processes: processes,
            resumeCommand: "fridge resume",
            resumesAt: resumesAt
        )
    }

    private func processExists(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
