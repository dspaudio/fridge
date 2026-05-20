import Foundation

public struct AgentHookInstallStatus: Codable, Sendable {
    public let bridgePath: String
    public let codexHooksPath: String
    public let claudeSettingsPath: String
    public let bridgeInstalled: Bool
    public let codexInstalled: Bool
    public let claudeInstalled: Bool
    public let cursorInstructionsPath: String
    public let cursorInstructionsInstalled: Bool
}

public final class AgentHookInstaller: @unchecked Sendable {
    private let fileManager: FileManager
    private let home: URL
    private let marker = "FRIDGE_AGENT_HOOK"

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.home = fileManager.homeDirectoryForCurrentUser
    }

    public func status() -> AgentHookInstallStatus {
        AgentHookInstallStatus(
            bridgePath: bridgeURL().path,
            codexHooksPath: codexHooksURL().path,
            claudeSettingsPath: claudeSettingsURL().path,
            bridgeInstalled: fileManager.isExecutableFile(atPath: bridgeURL().path),
            codexInstalled: fileContainsMarker(codexHooksURL()),
            claudeInstalled: fileContainsMarker(claudeSettingsURL()),
            cursorInstructionsPath: cursorInstructionsURL().path,
            cursorInstructionsInstalled: fileManager.fileExists(atPath: cursorInstructionsURL().path)
        )
    }

    @discardableResult
    public func installAll() throws -> AgentHookInstallStatus {
        try installBridge()
        try installCodexHooks()
        try installClaudeHooks()
        try installCursorInstructions()
        return status()
    }

    @discardableResult
    public func uninstallAll() throws -> AgentHookInstallStatus {
        try uninstallCodexHooks()
        try uninstallClaudeHooks()
        try removeIfExists(cursorInstructionsURL())
        try removeIfExists(bridgeURL())
        return status()
    }

    private func installBridge() throws {
        let directory = bridgeURL().deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let script = """
        #!/bin/sh
        # \(marker): bridge AI agent lifecycle hooks into Fridge.
        AGENT="${FRIDGE_AGENT:-${1:-unknown}}"
        EVENT="${FRIDGE_EVENT:-${2:-hook}}"
        if command -v fridge >/dev/null 2>&1; then
          exec fridge hook "$AGENT" "$EVENT" "$@"
        fi
        if [ -x "$HOME/.local/bin/fridge" ]; then
          exec "$HOME/.local/bin/fridge" hook "$AGENT" "$EVENT" "$@"
        fi
        exit 0
        """

        try script.write(to: bridgeURL(), atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bridgeURL().path)
    }

    private func installCodexHooks() throws {
        let command = "FRIDGE_AGENT=codex FRIDGE_EVENT=$CODEX_HOOK_EVENT \"\(bridgeURL().path)\" # \(marker)"
        try mergeHooksJSON(
            at: codexHooksURL(),
            events: ["SessionStart", "Stop", "SessionEnd"],
            command: command,
            timeout: 5
        )
    }

    private func uninstallCodexHooks() throws {
        try removeMarkedHookCommands(from: codexHooksURL())
    }

    private func installClaudeHooks() throws {
        let command = "FRIDGE_AGENT=claude FRIDGE_EVENT=$CLAUDE_HOOK_EVENT \"\(bridgeURL().path)\" # \(marker)"
        try mergeHooksJSON(
            at: claudeSettingsURL(),
            events: ["SessionStart", "Stop", "SessionEnd"],
            command: command,
            timeout: 5
        )
    }

    private func uninstallClaudeHooks() throws {
        try removeMarkedHookCommands(from: claudeSettingsURL())
    }

    private func installCursorInstructions() throws {
        let directory = cursorInstructionsURL().deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = """
        # Fridge Agent Hook Bridge

        Cursor does not expose a single stable local hook file across all distributions. Use this bridge command from Cursor Agent automation or task hooks:

        FRIDGE_AGENT=cursor FRIDGE_EVENT=Stop "\(bridgeURL().path)"
        """
        try text.write(to: cursorInstructionsURL(), atomically: true, encoding: .utf8)
    }

    private func mergeHooksJSON(at url: URL, events: [String], command: String, timeout: Int) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var root = try readJSONObject(at: url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for event in events {
            var eventEntries = hooks[event] as? [[String: Any]] ?? []
            guard !eventEntries.contains(where: { entryContainsMarker($0) }) else { continue }
            eventEntries.append([
                "hooks": [[
                    "type": "command",
                    "command": command,
                    "timeout": timeout
                ]]
            ])
            hooks[event] = eventEntries
        }

        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    private func removeMarkedHookCommands(from url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        var root = try readJSONObject(at: url)
        guard var hooks = root["hooks"] as? [String: Any] else { return }

        for key in Array(hooks.keys) {
            let entries = hooks[key] as? [[String: Any]] ?? []
            let filtered = entries.filter { !entryContainsMarker($0) }
            hooks[key] = filtered
        }

        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    private func entryContainsMarker(_ entry: [String: Any]) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { hook in
            (hook["command"] as? String)?.contains(marker) == true
        }
    }

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: [.atomic])
    }

    private func fileContainsMarker(_ url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains(marker)
    }

    private func removeIfExists(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func bridgeURL() -> URL {
        home.appendingPathComponent(".fridge/hooks/fridge-agent-hook.sh")
    }

    private func codexHooksURL() -> URL {
        home.appendingPathComponent(".codex/hooks.json")
    }

    private func claudeSettingsURL() -> URL {
        home.appendingPathComponent(".claude/settings.json")
    }

    private func cursorInstructionsURL() -> URL {
        home.appendingPathComponent(".fridge/agents/cursor-hook-bridge.md")
    }
}
