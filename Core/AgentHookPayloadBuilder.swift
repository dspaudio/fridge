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
    public let fridgeState: String
    public let frozenPIDs: [Int32]
    public let detectedProcesses: [AgentHookProcessPayload]
    public let freezeContext: FreezeContextRecord?
    public let message: String
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

        return AgentHookFridgePayload(
            source: source,
            event: event,
            receivedPayload: receivedPayload,
            createdAt: Date(),
            fridgeState: status.state.rawValue,
            frozenPIDs: status.frozenPIDs,
            detectedProcesses: status.detected.map(Self.processPayload),
            freezeContext: context,
            message: message(status: status, context: context)
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

    private func message(status: FridgeStatus, context: FreezeContextRecord?) -> String {
        guard status.state == .frozen else {
            return "Fridge state is \(status.state.rawValue); no active freeze context is available."
        }

        if let context {
            return "Fridge froze \(context.frozenPIDs.count) process(es) because: \(context.reason). Resume with `\(context.resumeCommand)`; \(context.resumesAt)"
        }

        return "Fridge sees frozen process(es), but no freeze context file is available. Resume with `fridge resume`; stopped processes continue from their suspended instruction."
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
