import Darwin
import Foundation
import FridgeModels
import FridgeProcessWatcher

public enum FreezeError: Error, CustomStringConvertible {
    case signalFailed(pid: Int32, signal: Int32, errno: Int32)
    case noSafeTargets

    public var description: String {
        switch self {
        case let .signalFailed(pid, signalValue, code):
            "Failed to send signal \(signalValue) to pid \(pid): errno \(code)"
        case .noSafeTargets:
            "No safe freeze targets. Refusing to freeze the process tree that launched Fridge."
        }
    }
}

public final class FreezeController: @unchecked Sendable {
    private let store: FrozenProcessStore
    private let watcher: ProcessWatcher

    public init(
        store: FrozenProcessStore = FrozenProcessStore(),
        watcher: ProcessWatcher = ProcessWatcher()
    ) {
        self.store = store
        self.watcher = watcher
    }

    public convenience init(store: FrozenProcessStore = FrozenProcessStore()) {
        self.init(store: store, watcher: ProcessWatcher())
    }

    @discardableResult
    public func freeze(_ groups: [AIProcess]) throws -> Set<Int32> {
        let protected = try protectedInvocationPIDs()
        let safeGroups = groups.filter { group in
            protected.isDisjoint(with: Set(group.allProcesses.map(\.pid)))
        }
        let processes = freezableProcesses(from: safeGroups)
        guard !processes.isEmpty else {
            throw FreezeError.noSafeTargets
        }
        var frozen = store.load()

        for process in processes.sorted(by: { $0.parentPID > $1.parentPID }) {
            try send(SIGSTOP, to: process.pid)
            frozen.insert(process.pid)
        }

        try store.save(frozen)
        return frozen
    }

    @discardableResult
    public func resume(pids: Set<Int32>? = nil) throws -> Set<Int32> {
        let stored = pids ?? store.load()

        for pid in stored.sorted() {
            try send(SIGCONT, to: pid)
        }

        if pids == nil {
            try store.clear()
            return []
        }
        return stored
    }

    public func frozenPIDs() -> Set<Int32> {
        store.load()
    }

    private func freezableProcesses(from groups: [AIProcess]) -> [SystemProcess] {
        var seen = Set<Int32>()
        var result: [SystemProcess] = []

        for process in groups.flatMap(\.children)
            where seen.insert(process.pid).inserted && !isProtectedInfrastructure(process) {
            result.append(process)
        }

        return result
    }

    private func isProtectedInfrastructure(_ process: SystemProcess) -> Bool {
        let text = "\(process.displayName) \(process.command) \(process.arguments)".lowercased()
        return [
            "/dist/mcp/",
            "mcp-server",
            "wiki-server",
            "memory-server",
            "state-server",
            "trace-server",
            "code-intel-server",
            "oh-my-codex/dist/mcp"
        ].contains { text.contains($0) }
    }

    private func protectedInvocationPIDs() throws -> Set<Int32> {
        let processes = try watcher.listProcesses()
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        let byParent = Dictionary(grouping: processes, by: \.parentPID)
        let currentPID = Int32(ProcessInfo.processInfo.processIdentifier)

        var protected = Set<Int32>()
        var pid = currentPID

        while let process = byPID[pid], protected.insert(process.pid).inserted {
            pid = process.parentPID
        }

        var stack = byParent[currentPID] ?? []
        while let process = stack.popLast() {
            if protected.insert(process.pid).inserted {
                stack.append(contentsOf: byParent[process.pid] ?? [])
            }
        }

        return protected
    }

    private func send(_ signalValue: Int32, to pid: Int32) throws {
        guard pid > 1 else { return }
        if kill(pid, signalValue) != 0 {
            let code = errno
            if code == ESRCH {
                return
            }
            throw FreezeError.signalFailed(pid: pid, signal: signalValue, errno: code)
        }
    }
}
