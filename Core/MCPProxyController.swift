import Foundation

public final class MCPProxyController: @unchecked Sendable {
    private let service: FridgeService
    private let snapshots: SnapshotController
    private let activity: ActivityMonitor

    public init(
        service: FridgeService = FridgeService(),
        snapshots: SnapshotController = SnapshotController(),
        activity: ActivityMonitor = ActivityMonitor()
    ) {
        self.service = service
        self.snapshots = snapshots
        self.activity = activity
    }

    public func manifestJSON() throws -> String {
        try jsonString([
            "name": "fridge",
            "version": "0.3.0",
            "tools": toolDescriptors()
        ])
    }

    public func handle(requestJSON: String) throws -> String {
        let data = Data(requestJSON.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let request = object as? [String: Any] else {
            return try errorResponse(id: nil, code: -32600, message: "Invalid request")
        }

        let id = request["id"]
        let method = request["method"] as? String

        switch method {
        case "tools/list":
            return try successResponse(id: id, result: ["tools": toolDescriptors()])
        case "tools/call":
            guard let params = request["params"] as? [String: Any],
                  let name = params["name"] as? String else {
                return try errorResponse(id: id, code: -32602, message: "Missing tool name")
            }
            return try successResponse(id: id, result: callTool(name))
        default:
            return try errorResponse(id: id, code: -32601, message: "Unsupported method")
        }
    }

    private func callTool(_ name: String) throws -> [String: Any] {
        switch name {
        case "fridge_status":
            let status = try service.status()
            _ = try activity.record(status: status)
            return [
                "state": status.state.rawValue,
                "processes": status.detected.map { process in
                    [
                        "name": process.displayName,
                        "pid": Int(process.root.pid),
                        "children": process.children.map { Int($0.pid) }
                    ]
                }
            ]
        case "fridge_freeze":
            let status = try service.freezeAll(
                reason: "MCP fridge_freeze tool call",
                source: "mcp",
                resumeHint: "fridge_resume"
            )
            _ = try activity.record(status: status)
            return ["state": status.state.rawValue, "frozenPIDs": status.frozenPIDs.map(Int.init)]
        case "fridge_resume":
            let status = try service.resumeAll()
            _ = try activity.record(status: status)
            return ["state": status.state.rawValue]
        case "fridge_snapshot":
            let record = try snapshots.createSnapshot()
            return ["id": record.id, "patchPath": record.patchPath]
        default:
            return ["error": "Unknown tool \(name)"]
        }
    }

    private func toolDescriptors() -> [[String: Any]] {
        [
            ["name": "fridge_status", "description": "Show detected AI process state"],
            ["name": "fridge_freeze", "description": "Freeze AI process trees with SIGSTOP"],
            ["name": "fridge_resume", "description": "Resume frozen processes with SIGCONT"],
            ["name": "fridge_snapshot", "description": "Create a git diff snapshot"]
        ]
    }

    private func successResponse(id: Any?, result: [String: Any]) throws -> String {
        try jsonString(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    private func errorResponse(id: Any?, code: Int, message: String) throws -> String {
        try jsonString([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": ["code": code, "message": message]
        ])
    }

    private func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
