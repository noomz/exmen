import Foundation

struct Action: Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let description: String
    let scriptConfig: ScriptConfig?
    let outputConfig: OutputConfig
    let hookConfig: HookConfig?
    let hideOnClick: Bool
    let serviceConfig: ServiceConfig?
    let isService: Bool
    /// Optional orchestrated subtasks (Phase 11, D-01). Non-empty → executeAction
    /// branches onto SubtaskOrchestrator instead of ScriptRunner.
    let subtasks: [SubtaskConfig]?
    /// Visibility conditions from `[when]`. Nil means always shown.
    let when: WhenConfig?
    /// True when `[when]` is present and at least one check failed.
    let isHidden: Bool
    /// Human-readable reason the item is hidden (shown when revealing hidden items).
    let hiddenReason: String?

    // Dynamic state (can be updated by hooks)
    var dynamicTitle: String?
    var dynamicStatus: String?
    var dynamicBadge: String?
    var dynamicIcon: String?

    /// Display title (dynamic or static)
    var displayTitle: String {
        dynamicTitle ?? name
    }

    /// Display icon (dynamic or static)
    var displayIcon: String {
        dynamicIcon ?? icon
    }

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "terminal",
        description: String = "",
        scriptConfig: ScriptConfig? = nil,
        outputConfig: OutputConfig = OutputConfig(handler: .clipboard),
        hookConfig: HookConfig? = nil,
        hideOnClick: Bool = true,
        serviceConfig: ServiceConfig? = nil,
        isService: Bool = false,
        subtasks: [SubtaskConfig]? = nil,
        when: WhenConfig? = nil,
        isHidden: Bool = false,
        hiddenReason: String? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.scriptConfig = scriptConfig
        self.outputConfig = outputConfig
        self.hookConfig = hookConfig
        self.hideOnClick = hideOnClick
        self.serviceConfig = serviceConfig
        self.isService = isService
        self.subtasks = subtasks
        self.when = when
        self.isHidden = isHidden
        self.hiddenReason = hiddenReason
    }

    /// Initialize from ActionConfig (loaded from TOML)
    init(from config: ActionConfig) {
        self.id = UUID()
        self.name = config.name
        self.icon = config.icon ?? "terminal"
        self.description = config.description ?? ""
        self.scriptConfig = config.script
        self.outputConfig = config.resolvedOutput
        self.hookConfig = config.hook
        self.hideOnClick = config.resolvedHideOnClick
        self.serviceConfig = config.service
        self.isService = config.isService
        self.subtasks = config.subtasks
        self.when = config.when
        let evaluation = config.when?.evaluate() ?? .satisfied
        self.isHidden = !evaluation.isSatisfied
        self.hiddenReason = evaluation.reasons.isEmpty ? nil : evaluation.reasonCaption
    }

    /// Apply hook updates to this action
    mutating func applyHookUpdate(_ update: HookUpdate) {
        if let title = update.title { dynamicTitle = title }
        if let status = update.status { dynamicStatus = status }
        if let badge = update.badge { dynamicBadge = badge }
        if let icon = update.icon { dynamicIcon = icon }
    }
}

// Static sample actions for development/fallback
extension Action {
    static let samples: [Action] = [
        Action(name: "Generate Phone Number", icon: "phone", description: "Generate random phone number"),
        Action(name: "Update Homebrew", icon: "arrow.clockwise", description: "Run brew update && upgrade"),
        Action(name: "Check Disk Space", icon: "internaldrive", description: "Show available disk space")
    ]
}
