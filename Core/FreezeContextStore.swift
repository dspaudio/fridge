import Foundation
import FridgeModels

public struct FrozenProcessContext: Codable, Sendable {
    public let name: String
    public let pid: Int32
    public let parentPID: Int32
    public let command: String
    public let arguments: String
    public let matchedBy: String
}

public struct FreezeContextRecord: Codable, Sendable {
    public let id: String
    public let createdAt: Date
    public let source: String
    public let reason: String
    public let frozenPIDs: [Int32]
    public let processes: [FrozenProcessContext]
    public let resumeCommand: String
    public let resumesAt: String
}

public final class FreezeContextStore: @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".fridge/freeze-context.json")
        }
    }

    public func load() -> FreezeContextRecord? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder.fridge.decode(FreezeContextRecord.self, from: data)
    }

    public func save(_ record: FreezeContextRecord) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.fridge.encode(record)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
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

private extension JSONDecoder {
    static var fridge: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
