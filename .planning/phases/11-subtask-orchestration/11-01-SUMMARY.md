---
phase: 11-subtask-orchestration
plan: "01"
subsystem: testing
tags: [xctest, xcodebuild, xcodeproj, pbxproj, swift, test-infrastructure]

requires:
  - phase: 10-cli-service-manipulation
    provides: "Stable app target (Exmen) with ENABLE_TESTABILITY=YES in Debug build settings"

provides:
  - "ExmenTests XCTest target added to Exmen.xcodeproj (com.apple.product-type.bundle.unit-test)"
  - "Shared Exmen.xcscheme with TestAction referencing ExmenTests"
  - "9 red test suites covering ORCH-01..06 under Tests/ExmenTests/"
  - "xcodebuild test -scheme Exmen automated feedback loop for all downstream plans"

affects:
  - 11-02-subtask-config-model
  - 11-03-wave-scheduler
  - 11-04-subtask-runner
  - 11-05-orchestrator
  - 11-06-progress-window

tech-stack:
  added: []
  patterns:
    - "XCTest with @testable import Exmen for host-app unit tests"
    - "Red-first test authoring: tests reference future production symbols by name so they fail to link until implementation lands"
    - "Xcode 26 product type com.apple.product-type.bundle.unit-test (renamed from unit-test-bundle)"
    - "EXCLUDED_SOURCE_FILE_NAMES=*.metal workaround for missing Metal toolchain on this dev machine"

key-files:
  created:
    - Exmen.xcodeproj/xcshareddata/xcschemes/Exmen.xcscheme
    - Tests/ExmenTests/SubtaskConfigTests.swift
    - Tests/ExmenTests/WaveSchedulerTests.swift
    - Tests/ExmenTests/SubtaskStateTests.swift
    - Tests/ExmenTests/DynamicSpawnTests.swift
    - Tests/ExmenTests/SummaryTests.swift
    - Tests/ExmenTests/CascadeSkipTests.swift
    - Tests/ExmenTests/ConcurrencyCapTests.swift
    - Tests/ExmenTests/TimeoutTests.swift
    - Tests/ExmenTests/ProgressModelTests.swift
  modified:
    - Exmen.xcodeproj/project.pbxproj

key-decisions:
  - "Used com.apple.product-type.bundle.unit-test (Xcode 26 identifier) not the legacy unit-test-bundle"
  - "Tests/ExmenTests group nested under a Tests parent PBXGroup so file refs resolve to Tests/ExmenTests/*.swift not ExmenTests/*.swift"
  - "EXCLUDED_SOURCE_FILE_NAMES=*.metal passed on command line to skip SwiftTerm Metal compile on machines without Metal toolchain"
  - "9 test suites authored red-first: all fail with cannot-find-type errors for SubtaskConfig/SubtaskState/SubtaskStatus/SubtaskOrchestrator/OrchestrationSummary/HookParser.parseLine/OrchestratorError"

patterns-established:
  - "Red test suites: write tests against future API names so the suite fails to link, confirming tests exercise real future production code not mocks"
  - "PBXGroup hierarchy Tests > ExmenTests must match filesystem path Tests/ExmenTests/"

requirements-completed: [ORCH-01, ORCH-02, ORCH-03, ORCH-04, ORCH-05, ORCH-06]

duration: 45min
completed: 2026-06-05
---

# Phase 11 Plan 01: Test Infrastructure Summary

**ExmenTests XCTest target + shared Exmen scheme + 9 red test suites covering all ORCH requirements, establishing the automated feedback loop for subtask-orchestration implementation waves**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-06-05T09:50:00Z
- **Completed:** 2026-06-05T10:05:00Z
- **Tasks:** 2 (Task 3 was a human-verify checkpoint — approved)
- **Files modified:** 12 (1 pbxproj, 1 xcscheme, 9 test files, 1 Package.resolved update)

## Accomplishments

- Added `ExmenTests` XCTest target to `Exmen.xcodeproj` with correct Xcode 26 product type, `TEST_HOST`/`BUNDLE_LOADER` pointing at `Exmen.app`, and a `PBXTargetDependency` on the app target
- Created shared `Exmen.xcscheme` with a `TestAction` referencing `ExmenTests`, making `xcodebuild test -scheme Exmen` discover and run the test bundle
- Authored 9 red test suites (one per requirement area in the VALIDATION contract) that reference future production symbols (`SubtaskConfig`, `SubtaskState`, `SubtaskStatus`, `SubtaskOrchestrator`, `OrchestrationSummary`, `HookParser.parseLine`, `OrchestratorError`) — all fail at compile/link time with "cannot find type in scope" confirming correct red state
- Verified: `xcodebuild -list -project Exmen.xcodeproj` shows ExmenTests target; test run fails for the right reason (missing symbols, not misconfiguration)

## Task Commits

1. **Task 1: Add ExmenTests XCTest target and shared Exmen scheme** — `58db37a` (feat)
2. **Task 2: Author red XCTest suites for every ORCH requirement** — `8dda63f` (test)

## Files Created/Modified

- `Exmen.xcodeproj/project.pbxproj` — Added ExmenTests PBXNativeTarget, PBXContainerItemProxy, PBXTargetDependency, PBXSourcesBuildPhase, PBXFileReference entries for 9 test files, PBXGroup Tests/ExmenTests hierarchy, XCBuildConfiguration Debug/Release for ExmenTests, XCConfigurationList
- `Exmen.xcodeproj/xcshareddata/xcschemes/Exmen.xcscheme` — New shared scheme with BuildAction (Exmen + ExmenTests) and TestAction referencing ExmenTests
- `Tests/ExmenTests/SubtaskConfigTests.swift` — ORCH-01: [[subtasks]] decode, resolvedName/Timeout defaults, decodeInlineTable (8 tests)
- `Tests/ExmenTests/WaveSchedulerTests.swift` — ORCH-02: topo-sort, diamond graph, cycle detection, unknownDependency (9 tests)
- `Tests/ExmenTests/SubtaskStateTests.swift` — ORCH-03: SubtaskStatus dotColor/isTerminal, SubtaskState.elapsed, progressPercent (13 tests)
- `Tests/ExmenTests/DynamicSpawnTests.swift` — ORCH-04: decodeInlineTable, HookParser.parseLine subtask/progress/clamp, D-07/D-08 (11 tests)
- `Tests/ExmenTests/SummaryTests.swift` — ORCH-05: OrchestrationSummary counts, isFailure verdict, description (8 tests)
- `Tests/ExmenTests/CascadeSkipTests.swift` — ORCH-05: shouldSkip cascade transitivity, independent branches D-13/D-14 (8 tests)
- `Tests/ExmenTests/ConcurrencyCapTests.swift` — ORCH-06: cap honored at runtime, maxSubtaskCountExceeded, defaultConcurrencyLimit (4 tests)
- `Tests/ExmenTests/TimeoutTests.swift` — ORCH-06: timeout to failed state, process death check, fast task succeeds (5 tests)
- `Tests/ExmenTests/ProgressModelTests.swift` — ORCH-03: @Published model emits updates, isRunning transitions, overallProgressPercent (6 tests)

## Decisions Made

- **Xcode 26 product type rename:** `com.apple.product-type.bundle.unit-test` is the correct identifier in Xcode 26 (confirmed via XCBSpecifications.ideplugin DarwinProductTypes.xcspec). The legacy `com.apple.product-type.unit-test-bundle` identifier is absent from Xcode 26 specs.
- **Tests group hierarchy:** Added a `Tests` parent PBXGroup (path=Tests) wrapping the `ExmenTests` child group so `sourceTree = "<group>"` with `path = SubtaskConfigTests.swift` resolves to `Tests/ExmenTests/SubtaskConfigTests.swift` not `ExmenTests/SubtaskConfigTests.swift`.
- **Metal toolchain workaround:** SwiftTerm has a `.metal` file that fails when the Metal toolchain is not installed. The fix is `EXCLUDED_SOURCE_FILE_NAMES="*.metal"` on the xcodebuild command line — this propagates to all targets including SPM packages, which a project-level build setting does not.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Xcode 26 renamed unit-test product type identifier**
- **Found during:** Task 1 (target wiring)
- **Issue:** `com.apple.product-type.unit-test-bundle` does not exist in Xcode 26 — causes "unable to resolve product type" build error
- **Fix:** Changed pbxproj `productType` to `com.apple.product-type.bundle.unit-test` (verified in XCBSpecifications.ideplugin/ProductTypes.xcspec)
- **Files modified:** `Exmen.xcodeproj/project.pbxproj`
- **Committed in:** `8dda63f`

**2. [Rule 1 - Bug] PBXGroup path mismatch caused "Build input files cannot be found"**
- **Found during:** Task 2 verification
- **Issue:** ExmenTests PBXGroup placed directly under root group with `path = ExmenTests` resolved to `<worktree>/ExmenTests/*.swift` instead of `<worktree>/Tests/ExmenTests/*.swift`
- **Fix:** Added a `Tests` parent PBXGroup (path=Tests, id=A100001A233456780000001) wrapping ExmenTests group, matching filesystem layout
- **Files modified:** `Exmen.xcodeproj/project.pbxproj`
- **Committed in:** `8dda63f`

**3. [Rule 1 - Bug] Pre-existing Metal toolchain missing blocks SwiftTerm compilation**
- **Found during:** Task 2 verification (build-for-testing)
- **Issue:** SwiftTerm SPM package has `Sources/SwiftTerm/Apple/Metal/Shaders.metal`; Metal compiler not installed on dev machine; blocks all builds that touch SwiftTerm
- **Fix:** Added `AdditionalOptions` to scheme TestAction with `EXCLUDED_SOURCE_FILE_NAMES=*.metal`; documented command-line invocation in verification instructions
- **Files modified:** `Exmen.xcodeproj/xcshareddata/xcschemes/Exmen.xcscheme`
- **Committed in:** `8dda63f`

---

**Total deviations:** 3 auto-fixed (all Rule 1 bugs — 2 pbxproj structural, 1 environment)
**Impact on plan:** All fixes necessary for the build to reach the intended red state. No scope creep.

## Issues Encountered

- Xcode 26 (26.5, build 17F42) changed the unit-test bundle product type identifier — not documented in release notes, discovered by inspecting XCBSpecifications.ideplugin
- Metal toolchain not installed on this machine — `xcodebuild -downloadComponent MetalToolchain` would resolve permanently; the `EXCLUDED_SOURCE_FILE_NAMES` flag is a per-invocation workaround

## Known Stubs

None — this plan creates test infrastructure only. No production symbols are stubbed; they simply do not exist yet (intentional red state).

## Threat Flags

None — test infrastructure only; no new network endpoints, auth paths, file access patterns, or schema changes.

## Self-Check: PASSED

Verified:
- `58db37a` exists: feat(11-01) — ExmenTests target + scheme
- `8dda63f` exists: test(11-01) — 9 red XCTest suites
- All 9 test files present under `Tests/ExmenTests/`
- `xcodebuild -list` confirms ExmenTests target and Exmen scheme
- Build fails with `Cannot find type 'SubtaskConfig' in scope` (correct red state)

## Next Phase Readiness

- `xcodebuild test -scheme Exmen -destination 'platform=macOS' EXCLUDED_SOURCE_FILE_NAMES="*.metal" -only-testing:ExmenTests/<Suite>` is ready for each downstream plan
- Plan 11-02 (SubtaskConfig model) will make `SubtaskConfigTests` and parts of `DynamicSpawnTests` go green
- Plans 11-03..06 each have a mapped test suite that will turn green as they land
- **Note:** Metal toolchain not installed — recommend `xcodebuild -downloadComponent MetalToolchain` before running tests without the flag

---
*Phase: 11-subtask-orchestration*
*Completed: 2026-06-05*
