import Foundation
import FridgeModels

public struct ActivitySample: Codable, Sendable {
    public let sampledAt: Date
    public let state: FridgeState
    public let processCount: Int
    public let frozenCount: Int
    public let processes: [String]
}

public final class ActivityMonitor: @unchecked Sendable {
    private let logURL: URL

    public init(logURL: URL? = nil) {
        if let logURL {
            self.logURL = logURL
        } else {
            self.logURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".fridge/activity.jsonl")
        }
    }

    public func record(status: FridgeStatus) throws -> ActivitySample {
        let sample = ActivitySample(
            sampledAt: Date(),
            state: status.state,
            processCount: status.detected.reduce(0) { $0 + $1.allProcesses.count },
            frozenCount: status.frozenPIDs.count,
            processes: status.detected.map { "\($0.displayName):\($0.root.pid)" }
        )
        try append(sample)
        return sample
    }

    public func recent(limit: Int = 20) throws -> [ActivitySample] {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return [] }
        let text = try String(contentsOf: logURL, encoding: .utf8)
        return text.split(separator: "\n").suffix(limit).compactMap { line in
            try? JSONDecoder.fridge.decode(ActivitySample.self, from: Data(line.utf8))
        }
    }

    private func append(_ sample: ActivitySample) throws {
        let directory = logURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.fridge.encode(sample)
        let line = data + Data([0x0A])

        if FileManager.default.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            try line.write(to: logURL, options: [.atomic])
        }
    }
}

private extension JSONEncoder {
    static var fridge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var fridge: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
