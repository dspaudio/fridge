import AppKit
import FridgeCore
import SwiftUI

@MainActor
public final class PermissionOnboardingWindowController {
    private var window: NSWindow?
    private let permissions = PermissionController()

    public init() {}

    public func showIfNeeded() {
        guard !permissions.status().readyForGlobalHotKeys else { return }
        show()
    }

    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let view = PermissionOnboardingView()
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Fridge Permissions"
        window.setContentSize(NSSize(width: 500, height: 300))
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct PermissionOnboardingView: View {
    @StateObject private var model = PermissionOnboardingModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fridge Permissions")
                .font(.title2.bold())

            Text("Fridge needs macOS privacy approval for global Pause key handling. Process freeze and resume use normal same-user process signaling, but hot key capture depends on system privacy settings.")
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Text("Accessibility")
                Spacer()
                Text(model.accessibilityStatus)
            }

            HStack {
                Button("Request Accessibility") { model.requestAccessibility() }
                Button("Open Accessibility Settings") { model.openAccessibility() }
            }

            HStack {
                Text("Input Monitoring")
                Spacer()
                Text("Optional")
            }

            HStack {
                Button("Open Input Monitoring Settings") { model.openInputMonitoring() }
                Button("Refresh") { model.refresh() }
                Button("Relaunch Fridge") { model.relaunch() }
            }

            if !model.message.isEmpty {
                Text(model.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Bundle ID: \(model.bundleIdentifier)")
                Text("App Path: \(model.bundlePath)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Signing: \(model.signingSummary)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 300)
        .onAppear { model.refresh() }
    }
}

@MainActor
private final class PermissionOnboardingModel: ObservableObject {
    @Published var accessibilityStatus = "Unknown"
    @Published var bundleIdentifier = "unknown"
    @Published var bundlePath = "unknown"
    @Published var signingSummary = "unknown"
    @Published var message = ""

    private let permissions = PermissionController()

    func refresh() {
        let status = permissions.status()
        accessibilityStatus = status.accessibilityTrusted ? "Granted" : "Not Granted"
        bundleIdentifier = status.bundleIdentifier
        bundlePath = status.bundlePath
        signingSummary = status.signingSummary
        message = status.accessibilityTrusted
            ? "Global Pause key support is ready. Relaunch Fridge if the hot key was registered before approval."
            : "Grant Accessibility, then relaunch Fridge so macOS applies the new privacy grant to this process."
    }

    func requestAccessibility() {
        permissions.requestAccessibilityPrompt()
        refresh()
    }

    func openAccessibility() {
        permissions.openAccessibilitySettings()
    }

    func openInputMonitoring() {
        permissions.openInputMonitoringSettings()
    }

    func relaunch() {
        permissions.relaunchApp()
    }
}
