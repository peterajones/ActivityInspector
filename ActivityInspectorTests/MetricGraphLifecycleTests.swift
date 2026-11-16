import Testing
import AppKit
import SwiftUI
@testable import ActivityInspector

/// Counts animation frames reported by `MetricGraph.onFrame`.
@MainActor
private final class FrameCounter {
    var count = 0
}

/// Every graph glides at `graphFrameRate` (30 fps, 15 on battery), which costs real CPU
/// (~18% of a core for a 12-core CPU panel). It is only acceptable while the graph is on
/// screen. Navigating away from a panel removes its graphs from the view hierarchy, so these
/// tests host one in a real window, count frames, remove it, and check the frames stop.
@MainActor
@Suite(.serialized)
struct MetricGraphLifecycleTests {
    private func makeGraph(counter: FrameCounter, animated: Bool) -> some View {
        MetricGraph(values: [10, 40, 25, 60],
                    capacity: 60,
                    range: 0...100,
                    lineColor: .green, fillColor: .green, gridColor: .gray,
                    timeAxis: animated
                        ? CompressedTimeAxis(samplesSeen: 4, gridInterval: 30,
                                             lastSample: Date(), sampleInterval: 1)
                        : nil,
                    onFrame: { counter.count += 1 })
            .frame(width: 200, height: 100)
    }

    private func makeWindow(hosting view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        return window
    }

    @Test func animatesWhileOnScreenAndStopsWhenRemoved() async throws {
        let counter = FrameCounter()
        let hosting = NSHostingView(rootView: makeGraph(counter: counter, animated: true))
        let window = makeWindow(hosting: hosting)
        defer { window.close() }

        try await Task.sleep(for: .milliseconds(600))
        let whileShown = counter.count
        // 30 fps for 0.6 s is ~18 frames; 4 leaves room for a slow CI machine. A 1 Hz redraw
        // (the animation silently gone) would give 1 or 2.
        #expect(whileShown >= 4, "graph drew \(whileShown) frames in 0.6 s while on screen")

        // Navigating away from a panel removes its graphs from the hierarchy.
        window.contentView = NSView()
        try await Task.sleep(for: .milliseconds(100))   // let an in-flight frame land
        let atRemoval = counter.count

        try await Task.sleep(for: .milliseconds(600))
        #expect(counter.count == atRemoval,
                "graph drew \(counter.count - atRemoval) frames after it left the screen")
    }

    @Test func graphWithoutTimeAxisNeverAnimates() async throws {
        let counter = FrameCounter()
        let hosting = NSHostingView(rootView: makeGraph(counter: counter, animated: false))
        let window = makeWindow(hosting: hosting)
        defer { window.close() }

        try await Task.sleep(for: .milliseconds(600))
        #expect(counter.count == 0)
    }

    /// A window that can't be seen (minimised, covered, another Space) pauses its graphs:
    /// measured 2026-11-14, a minimised window kept animating at ~36% of a core.
    @Test func pausedGraphDrawsNoAnimationFrames() async throws {
        let counter = FrameCounter()
        let hosting = NSHostingView(rootView: makeGraph(counter: counter, animated: true)
            .environment(\.graphsAnimate, false))
        let window = makeWindow(hosting: hosting)
        defer { window.close() }

        try await Task.sleep(for: .milliseconds(600))
        // The first render may draw once; an animation would draw ~18 times.
        #expect(counter.count <= 1, "a paused graph drew \(counter.count) frames in 0.6 s")
    }

    /// The reader reports its window's visibility, and follows it on and off screen.
    @Test func visibilityReaderFollowsItsWindow() async throws {
        final class Box { var visible: Bool? }
        let box = Box()
        let hosting = NSHostingView(rootView: Color.clear
            .frame(width: 200, height: 100)
            .background(WindowVisibilityReader { box.visible = $0 }))
        let window = makeWindow(hosting: hosting)
        defer { window.close() }

        #expect(try await waitUntil { box.visible == true }, "never reported visible")

        window.orderOut(nil)
        #expect(try await waitUntil { box.visible == false }, "never reported hidden")

        window.orderFrontRegardless()
        #expect(try await waitUntil { box.visible == true }, "never reported visible again")
    }

    /// AppKit reports occlusion changes asynchronously, and in a full parallel run that can take
    /// longer than a fixed 300 ms (it failed once that way): check every 20 ms, for up to 3 s.
    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline { return false }
            try await Task.sleep(for: .milliseconds(20))
        }
        return true
    }
}
