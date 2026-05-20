import Foundation

public struct CLIHelperInstallStatus: Codable, Sendable {
    public let shimPath: String
    public let targetPath: String?
    public let installed: Bool
}

public final class CLIHelperInstaller: @unchecked Sendable {
    private let fileManager: FileManager
    private let home: URL

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.home = fileManager.homeDirectoryForCurrentUser
    }

    public func status() -> CLIHelperInstallStatus {
        let shim = shimURL()
        let target = installedTargetPath(at: shim)
        return CLIHelperInstallStatus(
            shimPath: shim.path,
            targetPath: target,
            installed: fileManager.isExecutableFile(atPath: shim.path)
        )
    }

    @discardableResult
    public func install() throws -> CLIHelperInstallStatus {
        let source = try resolveCLIExecutable()
        let directory = shimURL().deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let script = """
        #!/bin/sh
        # FRIDGE_CLI_HELPER
        exec "\(source.path)" "$@"
        """
        try script.write(to: shimURL(), atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shimURL().path)
        return status()
    }

    @discardableResult
    public func uninstall() throws -> CLIHelperInstallStatus {
        if fileManager.fileExists(atPath: shimURL().path) {
            try fileManager.removeItem(at: shimURL())
        }
        return status()
    }

    private func resolveCLIExecutable() throws -> URL {
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let candidates = [
            executableDirectory?.appendingPathComponent("fridge-cli"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(".build/debug/fridge"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(".build/release/fridge")
        ].compactMap { $0 }

        if let candidate = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return candidate
        }

        throw NSError(domain: "Fridge.CLIHelper", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Could not find a built fridge CLI executable. Run `swift build` first."
        ])
    }

    private func installedTargetPath(at shim: URL) -> String? {
        guard let text = try? String(contentsOf: shim, encoding: .utf8) else { return nil }
        let marker = "exec \""
        guard let start = text.range(of: marker)?.upperBound,
              let end = text[start...].firstIndex(of: "\"") else {
            return nil
        }
        return String(text[start..<end])
    }

    private func shimURL() -> URL {
        home.appendingPathComponent(".local/bin/fridge")
    }
}
