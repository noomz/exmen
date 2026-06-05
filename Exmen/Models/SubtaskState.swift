import SwiftUI

/// Lifecycle/result state of a single subtask during orchestration.
///
/// Mirrors the Phase 8 `ServiceState` dot-color convention (D-10):
///   pending / skipped → gray, running / succeeded → green, failed → red.
enum SubtaskStatus: Equatable {
    case pending
    case running
    case succeeded
    case failed(exitCode: Int32)
    case skipped

    /// Status dot color following Phase 8 convention (D-10).
    var dotColor: Color {
        switch self {
        case .pending:   return .gray
        case .running:   return .green
        case .succeeded: return .green
        case .failed:    return .red
        case .skipped:   return .gray
        }
    }

    /// Whether this status represents a completed (non-running) state.
    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .skipped: return true
        case .pending, .running:            return false
        }
    }
}

/// Per-subtask runtime state tracked by the orchestrator and observed by the progress window.
///
/// Conforms to `Identifiable` using `id` (the subtask's config id) so SwiftUI List
/// and ForEach can track rows without an extra wrapper.
struct SubtaskState: Identifiable {
    let id: String              // subtask config id — Identifiable.id
    let name: String            // display name (resolvedName from SubtaskConfig)
    var status: SubtaskStatus = .pending
    var startedAt: Date?
    var endedAt: Date?
    /// Opt-in per-subtask progress percentage (0–100). `nil` = no `EXMEN:progress=` emitted (D-12).
    var progressPercent: Int? = nil

    // MARK: - Computed

    /// Elapsed time in seconds. Returns 0 before the subtask starts.
    /// Freezes at `endedAt` once the subtask reaches a terminal state.
    var elapsed: TimeInterval {
        guard let start = startedAt else { return 0 }
        return (endedAt ?? Date()).timeIntervalSince(start)
    }

    /// Human-readable elapsed string using the Phase 8 `DateComponentsFormatter` pattern.
    /// Examples: "2s", "1m 4s", "1h 2m".
    static func elapsedString(_ elapsed: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: elapsed) ?? "—"
    }
}
