import Darwin
import Foundation
import FridgeModels

public struct AgentHookProcessPayload: Codable, Sendable {
    public let name: String
    public let rootPID: Int32
    public let matchedBy: String
    public let state: String
    public let pids: [Int32]
}

public struct AgentHookFridgePayload: Codable, Sendable {
    public let source: String
    public let event: String
    public let receivedPayload: String
    public let createdAt: Date
    public let fridgeAwareness: FridgeAwarenessPayload
    public let fridgeState: String
    public let frozenPIDs: [Int32]
    public let detectedProcesses: [AgentHookProcessPayload]
    public let freezeContext: FreezeContextRecord?
    public let hookContext: HookContextPayload
    public let resumeProbe: ResumeProbePayload
    public let thawResult: String
    public let agentInstruction: String
    public let message: String
}

public struct FridgeAwarenessPayload: Codable, Sendable {
    public let installed: Bool
    public let canFreezeProcesses: Bool
    public let freezeMechanism: String
    public let resumeMechanism: String
    public let protectedScope: String
    public let agentContract: String
    public let commands: [String]
}

public struct HookContextPayload: Codable, Sendable {
    public let lastTool: String?
    public let cwd: String?
    public let pendingPromptSummary: String?
}

public struct ResumeProbePayload: Codable, Sendable {
    public let childStillExists: Bool
    public let terminalStillAttached: Bool
    public let outputChangedWhileFrozen: String
    public let remainingFrozenPIDs: [Int32]
    public let missingFrozenPIDs: [Int32]
}

public final class AgentHookPayloadBuilder: @unchecked Sendable {
    private let service: FridgeService
    private let freezeContextStore: FreezeContextStore

    public init(
        service: FridgeService = FridgeService(),
        freezeContextStore: FreezeContextStore = FreezeContextStore()
    ) {
        self.service = service
        self.freezeContextStore = freezeContextStore
    }

    public func makePayload(source: String, event: String, receivedPayload: String) throws -> AgentHookFridgePayload {
        let status = try service.status()
        let context = freezeContextStore.load()
        let hookContext = hookContext(from: receivedPayload)
        let probe = resumeProbe(status: status, context: context)
        let thawResult = thawResult(status: status, context: context, probe: probe)
        let instruction = agentInstruction(thawResult: thawResult, context: context, probe: probe)

        return AgentHookFridgePayload(
            source: source,
            event: event,
            receivedPayload: receivedPayload,
            createdAt: Date(),
            fridgeAwareness: awareness(),
            fridgeState: status.state.rawValue,
            frozenPIDs: status.frozenPIDs,
            detectedProcesses: status.detected.map(Self.processPayload),
            freezeContext: context,
            hookContext: hookContext,
            resumeProbe: probe,
            thawResult: thawResult,
            agentInstruction: instruction,
            message: message(status: status, context: context, thawResult: thawResult, instruction: instruction)
        )
    }

    public func jsonString(_ payload: AgentHookFridgePayload) throws -> String {
        let data = try JSONEncoder.fridge.encode(payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func processPayload(_ process: AIProcess) -> AgentHookProcessPayload {
        AgentHookProcessPayload(
            name: process.displayName,
            rootPID: process.root.pid,
            matchedBy: process.matchedBy,
            state: process.isFrozen ? "frozen" : "running",
            pids: process.allProcesses.map(\.pid)
        )
    }

    private func awareness() -> FridgeAwarenessPayload {
        FridgeAwarenessPayload(
            installed: true,
            canFreezeProcesses: true,
            freezeMechanism: "Fridge may suspend detected AI child processes with SIGSTOP.",
            resumeMechanism: "Fridge resumes stored frozen processes with SIGCONT.",
            protectedScope: "Fridge avoids freezing the root agent CLI, Fridge itself, and known MCP/tool infrastructure.",
            agentContract: "Treat every Fridge hook payload as current runtime state. If fridgeState is frozen or thawResult is not resumed, inspect freezeContext, resumeProbe, thawResult, and agentInstruction before continuing work.",
            commands: [
                "fridge status",
                "fridge freeze",
                "fridge resume",
                "fridge hook <source> <event> [payload]"
            ]
        )
    }

    private func resumeProbe(status: FridgeStatus, context: FreezeContextRecord?) -> ResumeProbePayload {
        guard let context else {
            return ResumeProbePayload(
                childStillExists: false,
                terminalStillAttached: false,
                outputChangedWhileFrozen: "unknown",
                remainingFrozenPIDs: status.frozenPIDs,
                missingFrozenPIDs: []
            )
        }

        let remaining = context.frozenPIDs.filter { pid in
            status.frozenPIDs.contains(pid) || processExists(pid)
        }
        let missing = context.frozenPIDs.filter { !remaining.contains($0) }
        let terminalAttached = context.processes
            .compactMap(\.terminal)
            .contains { terminalExists($0) }

        return ResumeProbePayload(
            childStillExists: !remaining.isEmpty,
            terminalStillAttached: terminalAttached,
            outputChangedWhileFrozen: "unknown",
            remainingFrozenPIDs: remaining,
            missingFrozenPIDs: missing
        )
    }

    private func hookContext(from payload: String) -> HookContextPayload {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return HookContextPayload(lastTool: nil, cwd: nil, pendingPromptSummary: nil)
        }

        return HookContextPayload(
            lastTool: firstString(in: object, keys: ["last_tool", "lastTool", "tool_name", "toolName"]),
            cwd: firstString(in: object, keys: ["cwd", "current_working_directory", "currentWorkingDirectory"]),
            pendingPromptSummary: summarize(firstString(in: object, keys: [
                "pending_prompt_summary",
                "pendingPromptSummary",
                "prompt",
                "user_prompt",
                "userPrompt",
                "message"
            ]))
        )
    }

    private func firstString(in object: Any, keys: [String]) -> String? {
        if let dictionary = object as? [String: Any] {
            for key in keys {
                if let value = dictionary[key] as? String, !value.isEmpty {
                    return value
                }
            }

            for value in dictionary.values {
                if let found = firstString(in: value, keys: keys) {
                    return found
                }
            }
        }

        if let array = object as? [Any] {
            for value in array {
                if let found = firstString(in: value, keys: keys) {
                    return found
                }
            }
        }

        return nil
    }

    private func summarize(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.count <= 240 {
            return cleaned
        }
        return String(cleaned.prefix(237)) + "..."
    }

    private func thawResult(status: FridgeStatus, context: FreezeContextRecord?, probe: ResumeProbePayload) -> String {
        guard context != nil else {
            return status.state == .frozen ? "unsafe_to_resume" : "resumed"
        }

        if !probe.childStillExists {
            return "child_gone"
        }
        if !probe.terminalStillAttached {
            return "tty_lost"
        }
        if status.state == .frozen {
            return "unsafe_to_resume"
        }
        return "resumed"
    }

    private func agentInstruction(
        thawResult: String,
        context: FreezeContextRecord?,
        probe: ResumeProbePayload
    ) -> String {
        switch thawResult {
        case "resumed":
            return "Fridge hook is installed and can freeze/resume this agent runtime. Continue from the preserved working context. Re-read recent terminal output before taking destructive action."
        case "child_gone":
            return "Fridge hook is installed and can freeze/resume this agent runtime. Do not assume the frozen child resumed. Reconstruct state from cwd, hook payload, and recent logs before continuing."
        case "tty_lost":
            return "Fridge hook is installed and can freeze/resume this agent runtime. The original terminal is no longer attached. Re-establish a visible session before continuing user-facing work."
        default:
            if let context {
                return "Fridge hook is installed and can freeze/resume this agent runtime. Frozen process still appears active. Resume with `\(context.resumeCommand)` only when the user asks to thaw."
            }
            return "Fridge hook is installed and can freeze/resume this agent runtime. No reliable freeze context is available. Inspect current process state before resuming work."
        }
    }

    private func message(
        status: FridgeStatus,
        context: FreezeContextRecord?,
        thawResult: String,
        instruction: String
    ) -> String {
        guard status.state == .frozen else {
            return "Fridge thaw_result=\(thawResult). \(instruction)"
        }

        if let context {
            return "Fridge froze \(context.frozenPIDs.count) process(es) because: \(context.reason). thaw_result=\(thawResult). \(instruction)"
        }

        return "Fridge sees frozen process(es), but no freeze context file is available. Resume with `fridge resume`; stopped processes continue from their suspended instruction."
    }

    private func processExists(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private func terminalExists(_ terminal: String) -> Bool {
        let path = terminal.hasPrefix("/dev/") ? terminal : "/dev/\(terminal)"
        return FileManager.default.fileExists(atPath: path)
    }
}

private extension JSONEncoder {
    static var fridge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
