import Foundation
import FridgeCore
import FridgeModels

let service = FridgeService()
let snapshots = SnapshotController()
let activity = ActivityMonitor()
let hooks = HookController()
let hookPayloads = AgentHookPayloadBuilder()
let network = NetworkFreezeController()
let mcp = MCPProxyController()
let cliInstaller = CLIHelperInstaller()
let hookInstaller = AgentHookInstaller()
let command = CommandLine.arguments.dropFirst().first ?? "status"
let arguments = Array(CommandLine.arguments.dropFirst())

do {
    switch command {
    case "freeze":
        let status = try service.freezeAll(reason: "CLI freeze command", source: "cli")
        _ = try activity.record(status: status)
        print("Frozen \(status.frozenPIDs.count) process(es).")
        printStatus(status)
    case "resume":
        let status = try service.resumeAll()
        _ = try activity.record(status: status)
        print("Resumed all frozen processes.")
        printStatus(status)
    case "toggle":
        let status = try service.toggle()
        _ = try activity.record(status: status)
        printStatus(status)
    case "status":
        let status = try service.status()
        _ = try activity.record(status: status)
        printStatus(status)
    case "snapshot":
        let record = try snapshots.createSnapshot()
        print("Snapshot: \(record.id)")
        print("Patch: \(record.patchPath)")
    case "snapshots":
        let records = try snapshots.listSnapshots()
        if records.isEmpty {
            print("No snapshots.")
        } else {
            for record in records {
                print("\(record.id) \(record.repositoryPath) \(record.patchPath)")
            }
        }
    case "rollback":
        guard arguments.count >= 2 else {
            fputs("Usage: fridge rollback <snapshot-id>\n", stderr)
            exit(2)
        }
        try snapshots.rollback(snapshotID: arguments[1])
        print("Rolled back snapshot \(arguments[1]).")
    case "activity":
        let samples = try activity.recent()
        if samples.isEmpty {
            print("No activity samples.")
        } else {
            for sample in samples {
                print("\(sample.sampledAt) state=\(sample.state.rawValue) processes=\(sample.processCount) frozen=\(sample.frozenCount)")
            }
        }
    case "hook":
        guard arguments.count >= 3 else {
            fputs("Usage: fridge hook <source> <event> [payload]\n", stderr)
            exit(2)
        }
        let receivedPayload = arguments.dropFirst(3).joined(separator: " ")
        let payload = try hookPayloads.makePayload(
            source: arguments[1],
            event: arguments[2],
            receivedPayload: receivedPayload
        )
        let json = try hookPayloads.jsonString(payload)
        _ = try hooks.record(source: arguments[1], event: arguments[2], payload: json)
        print(json)
    case "hooks":
        let events = try hooks.recent()
        if events.isEmpty {
            print("No hook events.")
        } else {
            for event in events {
                print("\(event.createdAt) \(event.source):\(event.event) \(event.payload)")
            }
        }
    case "install-cli":
        let status = try cliInstaller.install()
        print("Installed CLI helper: \(status.shimPath)")
        if let target = status.targetPath {
            print("Target: \(target)")
        }
    case "uninstall-cli":
        let status = try cliInstaller.uninstall()
        print("Removed CLI helper: \(status.shimPath)")
    case "install-hooks":
        let status = try hookInstaller.installAll()
        print("Installed agent hook bridge: \(status.bridgePath)")
        print("Codex hooks: \(status.codexHooksPath)")
        print("Claude settings: \(status.claudeSettingsPath)")
        print("Cursor instructions: \(status.cursorInstructionsPath)")
    case "uninstall-hooks":
        let status = try hookInstaller.uninstallAll()
        print("Removed agent hook bridge: \(status.bridgePath)")
    case "install-status":
        let cli = cliInstaller.status()
        let agent = hookInstaller.status()
        print("CLI helper: \(cli.installed ? "installed" : "not installed") \(cli.shimPath)")
        if let target = cli.targetPath {
            print("CLI target: \(target)")
        }
        print("Agent bridge: \(agent.bridgeInstalled ? "installed" : "not installed") \(agent.bridgePath)")
        print("Codex hooks: \(agent.codexInstalled ? "installed" : "not installed") \(agent.codexHooksPath)")
        print("Claude hooks: \(agent.claudeInstalled ? "installed" : "not installed") \(agent.claudeSettingsPath)")
        print("Cursor instructions: \(agent.cursorInstructionsInstalled ? "installed" : "not installed") \(agent.cursorInstructionsPath)")
    case "network-freeze":
        let plan = network.planFreeze()
        print(network.explanation())
        print("Mode: \(plan.mode)")
        print("Requires root: \(plan.requiresRoot)")
        for command in plan.commands {
            print("- \(command)")
        }
    case "mcp-proxy":
        let subcommand = arguments.dropFirst().first ?? "manifest"
        switch subcommand {
        case "manifest":
            print(try mcp.manifestJSON())
        case "handle":
            let payload = arguments.dropFirst(2).joined(separator: " ")
            guard !payload.isEmpty else {
                fputs("Usage: fridge mcp-proxy handle '<json-rpc-request>'\n", stderr)
                exit(2)
            }
            print(try mcp.handle(requestJSON: payload))
        default:
            fputs("Usage: fridge mcp-proxy [manifest|handle]\n", stderr)
            exit(2)
        }
    case "help", "--help", "-h":
        printHelp()
    default:
        fputs("Unknown command: \(command)\n", stderr)
        printHelp()
        exit(2)
    }
} catch {
    if String(describing: error).contains("No safe freeze targets") {
        fputs("fridge: \(error)\n", stderr)
        fputs("Tip: use the Fridge menu bar app to freeze the AI session that launched this CLI, or run `fridge freeze` from a separate terminal.\n", stderr)
        exit(1)
    }
    fputs("fridge: \(error)\n", stderr)
    exit(1)
}

private func printStatus(_ status: FridgeStatus) {
    print("State: \(status.state.rawValue)")

    if status.detected.isEmpty {
        print("AI processes: none")
    } else {
        for process in status.detected {
            let state = process.isFrozen ? "Frozen" : "Running"
            let pids = process.allProcesses.map { String($0.pid) }.joined(separator: ",")
            print("\(process.displayName): \(state) root=\(process.root.pid) pids=\(pids)")
        }
    }

    if !status.frozenPIDs.isEmpty {
        print("Frozen PIDs: \(status.frozenPIDs.map(String.init).joined(separator: ","))")
    }
}

private func printHelp() {
    print("""
    Usage: fridge <command>

    Commands:
      freeze   Freeze detected AI process trees with SIGSTOP
      resume   Resume frozen processes with SIGCONT
      toggle   Freeze when running, resume when frozen
      status   Show detected AI process state
      snapshot Create a git diff snapshot of the current repository
      snapshots
               List stored snapshots
      rollback <snapshot-id>
               Reverse-apply a stored git diff snapshot
      activity Show recent AI activity samples
      hook <source> <event> [payload]
               Record a hook event and print Fridge context JSON
      hooks    Show recent hook events
      install-cli
               Install ~/.local/bin/fridge helper
      uninstall-cli
               Remove ~/.local/bin/fridge helper
      install-hooks
               Install Fridge hook bridge into supported agents
      uninstall-hooks
               Remove Fridge hook bridge entries
      install-status
               Show CLI helper and agent hook install state
      network-freeze
               Show guarded network-freeze plan
      mcp-proxy
               Show MCP proxy manifest or handle a JSON-RPC request
      help     Show this help
    """)
}
