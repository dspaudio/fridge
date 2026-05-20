import Foundation

public struct SnapshotRecord: Codable, Sendable {
    public let id: String
    public let createdAt: Date
    public let repositoryPath: String
    public let patchPath: String
}

public final class SnapshotController: @unchecked Sendable {
    private let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            self.rootDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".fridge/snapshots")
        }
    }

    public func createSnapshot(repositoryPath: String = FileManager.default.currentDirectoryPath) throws -> SnapshotRecord {
        let repo = URL(fileURLWithPath: repositoryPath).standardizedFileURL
        let id = Self.timestampID()
        let snapshotDirectory = rootDirectory.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)

        let patchURL = snapshotDirectory.appendingPathComponent("working-tree.patch")
        let diff = try runGit(["diff", "--binary"], in: repo)
        try diff.write(to: patchURL, atomically: true, encoding: .utf8)

        let record = SnapshotRecord(
            id: id,
            createdAt: Date(),
            repositoryPath: repo.path,
            patchPath: patchURL.path
        )
        let data = try JSONEncoder.fridge.encode(record)
        try data.write(to: snapshotDirectory.appendingPathComponent("metadata.json"), options: [.atomic])
        return record
    }

    public func listSnapshots() throws -> [SnapshotRecord] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else { return [] }
        let directories = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        )

        return directories.compactMap { directory in
            let metadata = directory.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadata) else { return nil }
            return try? JSONDecoder.fridge.decode(SnapshotRecord.self, from: data)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    public func rollback(snapshotID: String, repositoryPath: String? = nil) throws {
        let snapshotDirectory = rootDirectory.appendingPathComponent(snapshotID)
        let metadataURL = snapshotDirectory.appendingPathComponent("metadata.json")
        let data = try Data(contentsOf: metadataURL)
        let record = try JSONDecoder.fridge.decode(SnapshotRecord.self, from: data)
        let repoPath = repositoryPath ?? record.repositoryPath
        let repo = URL(fileURLWithPath: repoPath).standardizedFileURL

        _ = try runGit(["apply", "--reverse", record.patchPath], in: repo)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let message = String(data: errorData, encoding: .utf8) ?? "git failed"
            throw NSError(domain: "Fridge.Git", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }

    private static func timestampID() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
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
