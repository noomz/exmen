# Codebase Map

Generated: 2026-08-06T03:37:23Z | Files: 60 | Described: 0/60
<!-- gsd:codebase-meta {"generatedAt":"2026-08-06T03:37:23Z","fingerprint":"2253454a8217d023d46fea0eab8a176ff0c6a923","fileCount":60,"truncated":false} -->

### (root)/
- `.gitignore`
- `CLAUDE.md`
- `Exmen-v1.1.0.zip`
- `LICENSE.md`
- `Package.swift`
- `README.md`

### .config/exmen/
- `.config/exmen/config.toml`

### .config/exmen/actions/
- `.config/exmen/actions/check-disk-space.toml`
- `.config/exmen/actions/system-status.toml`
- `.config/exmen/actions/update-homebrew.toml`

### .config/sketchybar/plugins/
- `.config/sketchybar/plugins/exmen.sh`

### Exmen/
- `Exmen/ExmenApp.swift`
- `Exmen/Info.plist`
- `Exmen/TOMLDecoderReexport.swift`

### Exmen.xcodeproj/
- `Exmen.xcodeproj/project.pbxproj`

### Exmen.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/
- `Exmen.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

### Exmen.xcodeproj/xcshareddata/xcschemes/
- `Exmen.xcodeproj/xcshareddata/xcschemes/Exmen.xcscheme`

### Exmen/Assets.xcassets/
- `Exmen/Assets.xcassets/Contents.json`

### Exmen/Assets.xcassets/AppIcon.appiconset/
- `Exmen/Assets.xcassets/AppIcon.appiconset/Contents.json`

### Exmen/Assets.xcassets/MenuBarIcon.imageset/
- `Exmen/Assets.xcassets/MenuBarIcon.imageset/Contents.json`

### Exmen/Models/
- `Exmen/Models/Action.swift`
- `Exmen/Models/ActionConfig.swift`
- `Exmen/Models/GlobalConfig.swift`
- `Exmen/Models/HookUpdate.swift`
- `Exmen/Models/ScriptResult.swift`
- `Exmen/Models/ServiceConfig.swift`
- `Exmen/Models/ServiceState.swift`
- `Exmen/Models/SubtaskConfig.swift`
- `Exmen/Models/SubtaskState.swift`

### Exmen/Services/
- `Exmen/Services/ActionService.swift`
- `Exmen/Services/CommandHandler.swift`
- `Exmen/Services/ConfigLoader.swift`
- `Exmen/Services/DirectoryWatcher.swift`
- `Exmen/Services/HookLineEvent.swift`
- `Exmen/Services/HookParser.swift`
- `Exmen/Services/ManagedService.swift`
- `Exmen/Services/OutputHandler.swift`
- `Exmen/Services/ScriptRunner.swift`
- `Exmen/Services/ServiceManager.swift`
- `Exmen/Services/SocketServer.swift`
- `Exmen/Services/StatusPoller.swift`
- `Exmen/Services/SubtaskOrchestrator.swift`
- `Exmen/Services/SubtaskRunner.swift`

### Exmen/Views/
- `Exmen/Views/ActionRowView.swift`
- `Exmen/Views/MenuContentView.swift`
- `Exmen/Views/PopupResultView.swift`
- `Exmen/Views/ServiceOutputWindow.swift`
- `Exmen/Views/ServiceRowView.swift`
- `Exmen/Views/SubtaskProgressWindow.swift`

### Tests/ExmenTests/
- `Tests/ExmenTests/CascadeSkipTests.swift`
- `Tests/ExmenTests/ConcurrencyCapTests.swift`
- `Tests/ExmenTests/DynamicSpawnTests.swift`
- `Tests/ExmenTests/ProgressModelTests.swift`
- `Tests/ExmenTests/ServiceLifecycleTests.swift`
- `Tests/ExmenTests/SubtaskConfigTests.swift`
- `Tests/ExmenTests/SubtaskStateTests.swift`
- `Tests/ExmenTests/SummaryTests.swift`
- `Tests/ExmenTests/TimeoutTests.swift`
- `Tests/ExmenTests/WaveSchedulerTests.swift`

### exmen-cli/
- `exmen-cli/main.swift`
