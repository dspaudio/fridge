import AppKit
import ApplicationServices
import Foundation

public struct PermissionStatus: Codable, Sendable {
    public let accessibilityTrusted: Bool
    public let inputMonitoringGuidanceRequired: Bool
    public let relaunchRecommended: Bool
    public let bundleIdentifier: String
    public let bundlePath: String
    public let signingSummary: String

    public var readyForGlobalHotKeys: Bool {
        accessibilityTrusted
    }
}

@MainActor
public final class PermissionController {
    public init() {}

    public func status() -> PermissionStatus {
        PermissionStatus(
            accessibilityTrusted: AXIsProcessTrusted(),
            inputMonitoringGuidanceRequired: true,
            relaunchRecommended: !AXIsProcessTrusted(),
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            bundlePath: Bundle.main.bundleURL.path,
            signingSummary: signingSummary()
        )
    }

    public func requestAccessibilityPrompt() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func openAccessibilitySettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    public func openInputMonitoringSettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    public func relaunchApp() {
        let targetURL = Bundle.main.bundleURL.pathExtension == "app"
            ? Bundle.main.bundleURL
            : (Bundle.main.executableURL ?? Bundle.main.bundleURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [targetURL.path]
        try? process.run()
        NSApplication.shared.terminate(nil)
    }

    private func openSettingsPane(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func signingSummary() -> String {
        guard let executable = Bundle.main.executableURL else { return "unknown" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=2", executable.path]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            let signature = text
                .split(separator: "\n")
                .first(where: { $0.contains("Signature=") })
                .map(String.init) ?? "Signature=unknown"
            let team = text
                .split(separator: "\n")
                .first(where: { $0.contains("TeamIdentifier=") })
                .map(String.init) ?? "TeamIdentifier=not set"
            return "\(signature), \(team)"
        } catch {
            return "codesign unavailable"
        }
    }
}
