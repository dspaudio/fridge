import Foundation

public struct NetworkFreezePlan: Codable, Sendable {
    public let mode: String
    public let requiresRoot: Bool
    public let commands: [String]
}

public final class NetworkFreezeController: Sendable {
    public init() {}

    public func planFreeze() -> NetworkFreezePlan {
        NetworkFreezePlan(
            mode: "pf-dry-run",
            requiresRoot: true,
            commands: [
                "Create an anchor such as com.fridge.ai",
                "Add pf rules that block outbound traffic for selected users or ports",
                "Run pfctl with root privileges to load the anchor"
            ]
        )
    }

    public func explanation() -> String {
        """
        Network freeze is exposed as a guarded plan only. macOS per-process network blocking requires root-level pf rules or a Network Extension entitlement. Fridge avoids silently changing firewall state; SIGSTOP already freezes process execution and therefore stops active network behavior while frozen.
        """
    }
}
