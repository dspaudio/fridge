import Foundation
import FridgeModels

public final class ProcessWatcher: @unchecked Sendable {
    private let excludedNames = ["FridgeApp", "fridge"]

    public init() {}

    public func detectAIProcesses() throws -> [AIProcess] {
        let processes = try listProcesses()
        let byParent = Dictionary(grouping: processes, by: \.parentPID)
        let currentPID = Int32(ProcessInfo.processInfo.processIdentifier)

        var results: [AIProcess] = []
        var seenRoots = Set<Int32>()

        for process in processes where process.pid != currentPID {
            guard !shouldExclude(process), let match = matchPattern(process) else { continue }
            guard !hasMatchedAncestor(process, processes: processes) else { continue }
            guard seenRoots.insert(process.pid).inserted else { continue }

            let children = descendants(of: process.pid, byParent: byParent)
                .filter { $0.pid != currentPID && !shouldExclude($0) }
            results.append(AIProcess(root: process, children: children, matchedBy: match))
        }

        return results.sorted { lhs, rhs in
            if lhs.displayName == rhs.displayName {
                return lhs.root.pid < rhs.root.pid
            }
            return lhs.displayName < rhs.displayName
        }
    }

    public func listProcesses() throws -> [SystemProcess] {
        let output = try runPS()
        return output.split(separator: "\n").compactMap(parseLine)
    }

    private func runPS() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,stat=,tt=,comm=,args="]

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parseLine(_ line: Substring) -> SystemProcess? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
        guard parts.count >= 6,
              let pid = Int32(parts[0]),
              let parentPID = Int32(parts[1]) else {
            return nil
        }

        let terminal = String(parts[3])
        return SystemProcess(
            pid: pid,
            parentPID: parentPID,
            state: String(parts[2]),
            terminal: terminal == "??" ? nil : terminal,
            command: String(parts[4]),
            arguments: String(parts[5])
        )
    }

    private func matchPattern(_ process: SystemProcess) -> String? {
        let name = process.displayName.lowercased()
        let haystack = "\(process.displayName) \(process.command) \(process.arguments)".lowercased()

        if name == "node" {
            return matchAIIdentifier(in: haystack)
        }

        if name.contains("claude") || haystack.contains("/claude") {
            return "claude"
        }
        if name.contains("codex") || haystack.contains("/codex") {
            return "codex"
        }
        if name.contains("cursor") || haystack.contains("/cursor") {
            return "cursor"
        }
        if name == "agent" || containsAgentPhrase(haystack) {
            return "agent"
        }

        return nil
    }

    private func matchAIIdentifier(in text: String) -> String? {
        if text.contains("claude") {
            return "claude"
        }
        if text.contains("codex") {
            return "codex"
        }
        if text.contains("cursor") {
            return "cursor"
        }
        if containsAgentPhrase(text) {
            return "agent"
        }
        return nil
    }

    private func containsAgentPhrase(_ text: String) -> Bool {
        [
            "cursor agent",
            "cursor-agent",
            "claude agent",
            "claude-agent",
            "codex agent",
            "codex-agent"
        ].contains { text.contains($0) }
    }

    private func shouldExclude(_ process: SystemProcess) -> Bool {
        let name = process.displayName
        return excludedNames.contains(name) || process.arguments.contains(".build/")
    }

    private func hasMatchedAncestor(_ process: SystemProcess, processes: [SystemProcess]) -> Bool {
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        var parentPID = process.parentPID
        var visited = Set<Int32>()

        while let parent = byPID[parentPID], visited.insert(parent.pid).inserted {
            if matchPattern(parent) != nil {
                return true
            }
            parentPID = parent.parentPID
        }

        return false
    }

    private func descendants(of pid: Int32, byParent: [Int32: [SystemProcess]]) -> [SystemProcess] {
        var result: [SystemProcess] = []
        var stack = byParent[pid] ?? []

        while let next = stack.popLast() {
            result.append(next)
            stack.append(contentsOf: byParent[next.pid] ?? [])
        }

        return result.sorted { $0.pid < $1.pid }
    }
}
