import Foundation

public struct HookEvent: Codable, Sendable {
    public let id: String
    public let createdAt: Date
    public let source: String
    public let event: String
    public let payload: String
}

public final class HookController: @unchecked Sendable {
    private let logURL: URL

    public init(logURL: URL? = nil) {
        if let logURL {
            self.logURL = logURL
        } else {
            self.logURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".fridge/hooks.jsonl")
        }
    }

    public func record(source: String, event: String, payload: String) throws -> HookEvent {
        let hookEvent = HookEvent(
            id: UUID().uuidString,
            createdAt: Date(),
            source: source,
            event: event,
            payload: payload
        )
        try append(hookEvent)
        return hookEvent
    }

    public func recent(limit: Int = 20) throws -> [HookEvent] {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return [] }
        let text = try String(contentsOf: logURL, encoding: .utf8)
        return text.split(separator: "\n").suffix(limit).compactMap { line in
            try? JSONDecoder.fridge.decode(HookEvent.self, from: Data(line.utf8))
        }
    }

    private func append(_ event: HookEvent) throws {
        let directory = logURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.fridge.encode(event)
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
