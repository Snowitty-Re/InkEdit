import Foundation
import Testing

@testable import InkEdit

@MainActor
final class ManualAutosaveClock: AutosaveClock {
    private(set) var now = ContinuousClock.now
    private var sleepers: [UUID: (ContinuousClock.Instant, CheckedContinuation<Void, Error>)] = [:]

    func sleep(until deadline: ContinuousClock.Instant) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if deadline <= now { return }
            try await withCheckedThrowingContinuation { continuation in
                sleepers[id] = (deadline, continuation)
            }
        } onCancel: {
            Task { @MainActor in
                self.sleepers.removeValue(forKey: id)?.1.resume(throwing: CancellationError())
            }
        }
    }

    func advance(by duration: Duration) async {
        now += duration
        for (id, sleeper) in sleepers where sleeper.0 <= now {
            sleepers.removeValue(forKey: id)?.1.resume()
        }
        // Give newly-created and cancelled tasks an opportunity to register/clean up.
        await Task.yield()
    }

    func waitForAutosave(_ model: BookWorkspaceModel) async throws {
        await advance(by: .seconds(1))
        let deadline = ContinuousClock.now + .seconds(15)
        while ContinuousClock.now < deadline {
            if case .saved = model.saveState { return }
            if case .failed = model.saveState { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Autosave did not complete: \(model.saveState)")
    }
}
