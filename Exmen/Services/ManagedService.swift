import Foundation
import SwiftUI

/// Manages the lifecycle of a single long-running CLI service.
/// This skeleton establishes the type contract for Plan 02 (which adds
/// SwiftTerm PTY integration, start/stop/restart logic, and output window).
@MainActor
class ManagedService: ObservableObject, Identifiable {
    let id: UUID
    let action: Action

    @Published var state: ServiceState = .stopped
    @Published var pid: Int32?
    @Published var startedAt: Date?

    var restartCount = 0

    init(action: Action) {
        self.id = action.id
        self.action = action
    }
}
