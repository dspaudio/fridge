import AppKit
import FridgeCore
import FridgeModels

@MainActor
public final class StatusMenuController: NSObject {
    private let statusItem: NSStatusItem
    private let service: FridgeService
    private let cliInstaller: CLIHelperInstaller
    private let hookInstaller: AgentHookInstaller
    private let controlPanel: ControlPanelWindowController
    private let permissionOnboarding: PermissionOnboardingWindowController
    private var hotKeyController: GlobalHotKeyController?
    private var fnDoubleTapController: FnDoubleTapController?
    private var timer: Timer?
    private var latestStatus = FridgeStatus(state: .idle, detected: [], frozenPIDs: [])

    public init(service: FridgeService = FridgeService()) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.service = service
        self.cliInstaller = CLIHelperInstaller()
        self.hookInstaller = AgentHookInstaller()
        self.controlPanel = ControlPanelWindowController()
        self.permissionOnboarding = PermissionOnboardingWindowController()
        super.init()
        configure()
    }

    public func start() {
        hotKeyController = GlobalHotKeyController { [weak self] in
            self?.toggleFromHotKey()
        }
        hotKeyController?.registerPauseKey()

        fnDoubleTapController = FnDoubleTapController { [weak self] in
            self?.toggleFromFnDoubleTap()
        }
        fnDoubleTapController?.start()

        refresh()
        permissionOnboarding.showIfNeeded()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func configure() {
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Fridge: Idle"
        statusItem.menu = NSMenu()
    }

    @objc private func freezeAll() {
        do {
            _ = try service.freezeAll(
                reason: "menu bar Freeze All AI action",
                source: "menu",
                resumeHint: "Pause again"
            )
            refresh()
        } catch {
            showError(error)
        }
    }

    @objc private func resumeAll() {
        do {
            _ = try service.resumeAll()
            refresh()
        } catch {
            showError(error)
        }
    }

    @objc private func refreshAction() {
        refresh()
    }

    @objc private func toggleFreeze() {
        toggleFromHotKey()
    }

    @objc private func showFrozenProcesses() {
        let pids = latestStatus.frozenPIDs.map(String.init).joined(separator: ", ")
        let message = pids.isEmpty ? "No frozen processes." : "Frozen PIDs: \(pids)"
        let alert = NSAlert()
        alert.messageText = "Fridge"
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func showSettings() {
        controlPanel.show()
    }

    @objc private func showPermissions() {
        permissionOnboarding.show()
    }

    @objc private func installCLIHelper() {
        do {
            let status = try cliInstaller.install()
            showMessage("CLI Helper Installed", "`fridge` is available at \(status.shimPath).")
        } catch {
            showError(error)
        }
    }

    @objc private func uninstallCLIHelper() {
        do {
            let status = try cliInstaller.uninstall()
            showMessage("CLI Helper Removed", "Removed \(status.shimPath).")
        } catch {
            showError(error)
        }
    }

    @objc private func installAgentHooks() {
        do {
            let status = try hookInstaller.installAll()
            showMessage("Agent Hooks Installed", "Bridge: \(status.bridgePath)")
        } catch {
            showError(error)
        }
    }

    @objc private func uninstallAgentHooks() {
        do {
            _ = try hookInstaller.uninstallAll()
            showMessage("Agent Hooks Removed", "Fridge hook bridge entries were removed.")
        } catch {
            showError(error)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refresh() {
        do {
            latestStatus = try service.status()
            applyStatusIcon(latestStatus.state)
            rebuildMenu()
        } catch {
            applyStatusIcon(.idle)
            showError(error)
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu(title: "Fridge")
        menu.addItem(header("Fridge"))
        menu.addItem(disabled("App              Running"))
        menu.addItem(disabled("PID              \(ProcessInfo.processInfo.processIdentifier)"))
        menu.addItem(.separator())

        if latestStatus.detected.isEmpty {
            menu.addItem(disabled("No AI processes detected"))
        } else {
            for process in latestStatus.detected {
                let state = process.isFrozen ? "Frozen" : "Running"
                menu.addItem(disabled("\(process.displayName)       \(state)"))
            }
        }

        menu.addItem(.separator())
        menu.addItem(action("Freeze All AI", #selector(freezeAll)))
        menu.addItem(action("Resume All", #selector(resumeAll)))
        menu.addItem(action("Toggle Freeze (Pause)", #selector(toggleFreeze)))
        menu.addItem(action("Show Frozen Processes", #selector(showFrozenProcesses)))
        menu.addItem(.separator())
        let cliStatus = cliInstaller.status()
        let hookStatus = hookInstaller.status()
        menu.addItem(disabled("CLI Helper       \(cliStatus.installed ? "Installed" : "Not Installed")"))
        menu.addItem(disabled("Agent Hooks      \(hookStatus.bridgeInstalled ? "Installed" : "Not Installed")"))
        menu.addItem(action("Install CLI Helper", #selector(installCLIHelper)))
        menu.addItem(action("Uninstall CLI Helper", #selector(uninstallCLIHelper)))
        menu.addItem(action("Install Agent Hooks", #selector(installAgentHooks)))
        menu.addItem(action("Uninstall Agent Hooks", #selector(uninstallAgentHooks)))
        menu.addItem(.separator())
        menu.addItem(action("Open Control Panel", #selector(showSettings)))
        menu.addItem(action("Open Permissions", #selector(showPermissions)))
        menu.addItem(action("Refresh", #selector(refreshAction)))
        menu.addItem(action("Quit Fridge", #selector(quit)))
        statusItem.menu = menu
    }

    private func title(for state: FridgeState) -> String {
        switch state {
        case .idle: "⚪ Fridge"
        case .running: "🟢 Fridge"
        case .frozen: "🧊 Fridge"
        }
    }

    private func applyStatusIcon(_ state: FridgeState) {
        let symbolName: String
        let description: String

        switch state {
        case .idle:
            symbolName = "circle"
            description = "Idle"
        case .running:
            symbolName = "play.circle.fill"
            description = "Running"
        case .frozen:
            symbolName = "snowflake"
            description = "Frozen"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Fridge \(description)")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "Fridge: \(description)"
    }

    private func toggleFromHotKey() {
        toggleFreezeWithReason(
            reason: "manual pause hotkey",
            source: "pause-key",
            resumeHint: "Pause again"
        )
    }

    private func toggleFromFnDoubleTap() {
        toggleFreezeWithReason(
            reason: "manual Fn double-tap",
            source: "fn-double-tap",
            resumeHint: "Fn twice or Pause again"
        )
    }

    private func toggleFreezeWithReason(reason: String, source: String, resumeHint: String) {
        do {
            if latestStatus.state == .frozen {
                _ = try service.resumeAll()
            } else {
                _ = try service.freezeAll(
                    reason: reason,
                    source: source,
                    resumeHint: resumeHint
                )
            }
            refresh()
        } catch {
            showError(error)
        }
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = disabled(title)
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
        )
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Fridge Error"
        alert.informativeText = String(describing: error)
        alert.runModal()
    }

    private func showMessage(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
