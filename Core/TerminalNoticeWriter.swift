import Foundation
import FridgeModels

public final class TerminalNoticeWriter: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func writeFreezeNotice(record: FreezeContextRecord, status: FridgeStatus, resumeHint: String) {
        let target = targetSummary(record: record)
        let reason = record.reason.replacingOccurrences(of: "\n", with: " ")
        let line = "FREEZED: \(target) reason=\(reason), resume=\(resumeHint)"
        write(line: line, to: terminals(from: status, record: record))
    }

    public func writeResumeNotice(record: FreezeContextRecord?, status: FridgeStatus) {
        let pids = record?.frozenPIDs ?? status.frozenPIDs
        let pidText = pids.map(String.init).joined(separator: ",")
        let line = pidText.isEmpty ? "RESUMED: no stored frozen processes" : "RESUMED: pid=\(pidText)"
        write(line: line, to: terminals(from: status, record: record))
    }

    private func targetSummary(record: FreezeContextRecord) -> String {
        guard let process = record.processes.first else {
            return "process pid=\(record.frozenPIDs.map(String.init).joined(separator: ","))"
        }

        return "\(process.name) pid=\(process.pid)"
    }

    private func terminals(from status: FridgeStatus, record: FreezeContextRecord?) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for terminal in status.detected.flatMap(\.allProcesses).compactMap(\.terminal) {
            append(terminal, seen: &seen, result: &result)
        }

        for terminal in record?.processes.compactMap(\.terminal) ?? [] {
            append(terminal, seen: &seen, result: &result)
        }

        return result
    }

    private func append(_ terminal: String, seen: inout Set<String>, result: inout [String]) {
        guard !terminal.isEmpty, terminal != "??", seen.insert(terminal).inserted else { return }
        result.append(terminal)
    }

    private func write(line: String, to terminals: [String]) {
        let data = Data(("\r\n\(line)\r\n").utf8)

        for terminal in terminals {
            let path = terminal.hasPrefix("/dev/") ? terminal : "/dev/\(terminal)"
            guard fileManager.fileExists(atPath: path),
                  let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) else {
                continue
            }

            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    }
}
