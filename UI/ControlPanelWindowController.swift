import AppKit
import FridgeCore
import SwiftUI

@MainActor
public final class ControlPanelWindowController {
    private var window: NSWindow?

    public init() {}

    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let view = ControlPanelView()
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Fridge Control Panel"
        window.setContentSize(NSSize(width: 700, height: 640))
        window.minSize = NSSize(width: 640, height: 560)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct ControlPanelView: View {
    @StateObject private var model = ControlPanelModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fridge")
                            .font(.largeTitle.bold())
                        Text("AI 작업 프로세스를 종료하지 않고 잠시 멈춥니다.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusBadge(model.appState)
                }

                section("권한") {
                    statusRow("Accessibility", model.accessibilityStatus)
                    statusRow("Input Monitoring", "Optional")
                    buttonRow {
                        controlButton("Request Accessibility") { model.requestAccessibility() }
                        controlButton("Open Accessibility") { model.openAccessibility() }
                        controlButton("Open Input Monitoring") { model.openInputMonitoring() }
                        controlButton("Relaunch") { model.relaunch() }
                    }
                }

                section("CLI Helper") {
                    statusRow("~/.local/bin/fridge", model.cliStatus)
                    buttonRow {
                        controlButton("Install CLI Helper") { model.installCLI() }
                        controlButton("Uninstall CLI Helper") { model.uninstallCLI() }
                    }
                }

                section("Agent Hooks") {
                    statusRow("Codex Hooks", model.codexStatus)
                    statusRow("Claude Hooks", model.claudeStatus)
                    statusRow("Cursor Instructions", model.cursorStatus)
                    buttonRow {
                        controlButton("Install Agent Hooks") { model.installHooks() }
                        controlButton("Uninstall Agent Hooks") { model.uninstallHooks() }
                    }
                }

                section("Freeze Controls") {
                    buttonRow {
                        controlButton("Freeze All AI") { model.freezeAll() }
                        controlButton("Resume All") { model.resumeAll() }
                        controlButton("Refresh") { model.refresh() }
                        controlButton("Relaunch Fridge") { model.relaunch() }
                        controlButton("Quit Fridge") { model.quit() }
                    }
                }

                if !model.message.isEmpty {
                    Text(model.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 18)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(minWidth: 640, minHeight: 560)
        .onAppear { model.refresh() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(value == "Installed" || value == "Running" || value == "Frozen" ? .primary : .secondary)
                .fontWeight(value == "Installed" || value == "Granted" ? .semibold : .regular)
        }
        .font(.title3)
    }

    private func buttonRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
        }
    }

    private func controlButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func statusBadge(_ value: String) -> some View {
        Text(value)
            .font(.headline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
    }
}

@MainActor
private final class ControlPanelModel: ObservableObject {
    @Published var appState = "Idle"
    @Published var cliStatus = "Not Installed"
    @Published var codexStatus = "Not Installed"
    @Published var claudeStatus = "Not Installed"
    @Published var cursorStatus = "Not Installed"
    @Published var accessibilityStatus = "Unknown"
    @Published var message = ""

    private let service = FridgeService()
    private let cliInstaller = CLIHelperInstaller()
    private let hookInstaller = AgentHookInstaller()
    private let permissions = PermissionController()

    func refresh() {
        do {
            let status = try service.status()
            appState = status.state.rawValue.capitalized
        } catch {
            appState = "Unknown"
            message = String(describing: error)
        }

        let cli = cliInstaller.status()
        let hooks = hookInstaller.status()
        cliStatus = cli.installed ? "Installed" : "Not Installed"
        codexStatus = hooks.codexInstalled ? "Installed" : "Not Installed"
        claudeStatus = hooks.claudeInstalled ? "Installed" : "Not Installed"
        cursorStatus = hooks.cursorInstructionsInstalled ? "Installed" : "Not Installed"
        accessibilityStatus = permissions.status().accessibilityTrusted ? "Granted" : "Not Granted"
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

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func installCLI() {
        do {
            let status = try cliInstaller.install()
            message = "Installed CLI helper at \(status.shimPath)."
            refresh()
        } catch {
            message = String(describing: error)
        }
    }

    func uninstallCLI() {
        do {
            let status = try cliInstaller.uninstall()
            message = "Removed CLI helper at \(status.shimPath)."
            refresh()
        } catch {
            message = String(describing: error)
        }
    }

    func installHooks() {
        do {
            let status = try hookInstaller.installAll()
            message = "Installed agent hook bridge at \(status.bridgePath)."
            refresh()
        } catch {
            message = String(describing: error)
        }
    }

    func uninstallHooks() {
        do {
            let status = try hookInstaller.uninstallAll()
            message = "Removed agent hook bridge at \(status.bridgePath)."
            refresh()
        } catch {
            message = String(describing: error)
        }
    }

    func freezeAll() {
        do {
            _ = try service.freezeAll()
            message = "Frozen detected AI process trees."
            refresh()
        } catch {
            message = String(describing: error)
        }
    }

    func resumeAll() {
        do {
            _ = try service.resumeAll()
            message = "Resumed frozen AI processes."
            refresh()
        } catch {
            message = String(describing: error)
        }
    }
}
