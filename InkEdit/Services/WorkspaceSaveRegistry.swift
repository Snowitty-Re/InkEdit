import AppKit

/// Window close and application quit use the same save contract as in-app navigation.
@MainActor
final class WorkspaceSaveRegistry {
    static let shared = WorkspaceSaveRegistry()
    private var handlers: [UUID: () -> Bool] = [:]

    func register(_ save: @escaping () -> Bool) -> UUID {
        let id = UUID()
        handlers[id] = save
        return id
    }

    func unregister(_ id: UUID) {
        handlers.removeValue(forKey: id)
    }

    func prepareForTermination() -> Bool {
        // Try every window even when an earlier save fails; keep all windows open on failure.
        let results = Array(handlers.values).map { $0() }
        return results.allSatisfy { $0 }
    }
}

@MainActor
final class InkEditApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        WorkspaceSaveRegistry.shared.prepareForTermination() ? .terminateNow : .terminateCancel
    }
}
