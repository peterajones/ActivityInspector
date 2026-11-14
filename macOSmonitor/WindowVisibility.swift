import SwiftUI
import AppKit

extension EnvironmentValues {
    /// False while the window can't be seen (minimised, fully covered, on another Space):
    /// `MetricGraph` pauses its glide then. Measured 2026-11-14, a minimised window kept
    /// animating at ~36% of a core.
    @Entry var graphsAnimate = true
}

/// Reports whether the window it sits in is visible on screen, now and whenever macOS says
/// that changes (the window's occlusion state). Put it in a `.background`.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) {
        view.onChange = onChange
    }

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observer: (any NSObjectProtocol)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            report(window)
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                MainActor.assumeIsolated { self?.report(window) }
            }
        }

        private func report(_ window: NSWindow) {
            onChange?(window.occlusionState.contains(.visible))
        }
    }
}
