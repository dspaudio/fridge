import Foundation

public enum FridgeState: String, Codable, Sendable {
    case idle
    case running
    case frozen
}

public struct SystemProcess: Codable, Hashable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let state: String
    public let command: String
    public let arguments: String

    public init(pid: Int32, parentPID: Int32, state: String, command: String, arguments: String) {
        self.pid = pid
        self.parentPID = parentPID
        self.state = state
        self.command = command
        self.arguments = arguments
    }

    public var isStopped: Bool {
        state.contains("T")
    }

    public var displayName: String {
        let last = URL(fileURLWithPath: command).lastPathComponent
        return last.isEmpty ? command : last
    }
}

public struct AIProcess: Codable, Hashable, Sendable {
    public let root: SystemProcess
    public let children: [SystemProcess]
    public let matchedBy: String

    public init(root: SystemProcess, children: [SystemProcess], matchedBy: String) {
        self.root = root
        self.children = children
        self.matchedBy = matchedBy
    }

    public var allProcesses: [SystemProcess] {
        [root] + children
    }

    public var isFrozen: Bool {
        allProcesses.contains { $0.isStopped }
    }

    public var displayName: String {
        switch matchedBy {
        case "claude": "Claude Code"
        case "codex": "Codex"
        case "cursor": "Cursor"
        case "agent": "Agent"
        default: root.displayName
        }
    }
}

public struct FridgeStatus: Codable, Sendable {
    public let state: FridgeState
    public let detected: [AIProcess]
    public let frozenPIDs: [Int32]

    public init(state: FridgeState, detected: [AIProcess], frozenPIDs: [Int32]) {
        self.state = state
        self.detected = detected
        self.frozenPIDs = frozenPIDs
    }
}
