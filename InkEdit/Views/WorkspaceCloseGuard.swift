import AppKit
import SwiftUI

struct WorkspaceCloseGuard: NSViewRepresentable {
    let model: BookWorkspaceModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ view: WindowObserverView, context: Context) {}

    static func dismantleNSView(_ view: WindowObserverView, coordinator: Coordinator) {
        view.onWindowChanged = nil
        coordinator.attach(to: nil)
    }

    final class WindowObserverView: NSView {
        var onWindowChanged: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChanged?(window)
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var model: BookWorkspaceModel?
        private weak var window: NSWindow?
        private weak var originalDelegate: (any NSWindowDelegate)?
        private var registration: UUID?

        @MainActor init(model: BookWorkspaceModel) { self.model = model }

        @MainActor func attach(to window: NSWindow?) {
            guard self.window !== window else { return }
            if let registration { WorkspaceSaveRegistry.shared.unregister(registration) }
            registration = nil
            if self.window?.delegate === self { self.window?.delegate = originalDelegate }
            self.window = window
            originalDelegate = window?.delegate
            guard let window else { return }
            window.delegate = self
            registration = WorkspaceSaveRegistry.shared.register { [weak self] in
                self?.prepareToClose() ?? true
            }
        }

        @MainActor func prepareToClose() -> Bool {
            guard window?.makeFirstResponder(nil) != false else { return false }
            guard model?.flushCurrentChapter() != false else {
                window?.makeKeyAndOrderFront(nil)
                return false
            }
            return true
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard prepareToClose() else { return false }
            return originalDelegate?.windowShouldClose?(sender) ?? true
        }

        // Preserve SwiftUI's existing delegate behavior (restoration, sizing, close cleanup).
        override nonisolated func responds(to selector: Selector!) -> Bool {
            if super.responds(to: selector) { return true }
            return originalDelegate?.responds(to: selector) ?? false
        }

        override nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
            originalDelegate
        }
    }
}
