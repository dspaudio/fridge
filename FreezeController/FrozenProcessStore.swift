import Foundation

public final class FrozenProcessStore: @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = home.appendingPathComponent(".fridge/frozen-pids.json")
        }
    }

    public func load() -> Set<Int32> {
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? JSONDecoder().decode([Int32].self, from: data) else {
            return []
        }
        return Set(values)
    }

    public func save(_ pids: Set<Int32>) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Array(pids).sorted())
        try data.write(to: fileURL, options: [.atomic])
    }

    public func clear() throws {
        try save([])
    }
}
