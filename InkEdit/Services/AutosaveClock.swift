import Foundation

/// Use a monotonic clock in production and explicitly advance time in idle-save tests.
@MainActor
protocol AutosaveClock {
    var now: ContinuousClock.Instant { get }
    func sleep(until deadline: ContinuousClock.Instant) async throws
}

struct ContinuousAutosaveClock: AutosaveClock {
    var now: ContinuousClock.Instant { ContinuousClock.now }

    func sleep(until deadline: ContinuousClock.Instant) async throws {
        try await Task.sleep(until: deadline, clock: .continuous)
    }
}
