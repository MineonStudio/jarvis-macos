import AppKit
import CoreFoundation
import Foundation
import OSLog
import SwiftUI

enum JarvisPerformance {
    static let signposter = OSSignposter(
        subsystem: JarvisAppIdentity.bundleIdentifier,
        category: .pointsOfInterest
    )

    static let logger = Logger(
        subsystem: JarvisAppIdentity.bundleIdentifier,
        category: "performance"
    )

    static func emit(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}

@MainActor
final class MainThreadHealthMonitor {
    private var observer: CFRunLoopObserver?
    private var activeSince: UInt64?
    private let thresholdNanoseconds: UInt64

    init(thresholdMilliseconds: UInt64 = 16) {
        thresholdNanoseconds = thresholdMilliseconds * 1_000_000
    }

    func start() {
        guard observer == nil else { return }

        let activities: CFRunLoopActivity = [.afterWaiting, .beforeWaiting]
        observer = CFRunLoopObserverCreateWithHandler(
            nil,
            activities.rawValue,
            true,
            0
        ) { [weak self] _, activity in
            guard let self else { return }
            let now = DispatchTime.now().uptimeNanoseconds

            switch activity {
            case .afterWaiting:
                activeSince = now
            case .beforeWaiting:
                guard let activeSince else { return }
                self.activeSince = nil
                let elapsed = now - activeSince
                guard elapsed >= self.thresholdNanoseconds else { return }

                let milliseconds = Double(elapsed) / 1_000_000
                print(
                    "\u{001B}[31m[MAIN THREAD HITCH] "
                        + String(format: "%.2f ms", milliseconds)
                        + "\u{001B}[0m"
                )
                JarvisPerformance.logger.warning(
                    "主线程连续占用超过阈值：\(milliseconds, privacy: .public) ms"
                )
            default:
                break
            }
        }

        if let observer {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }

    func stop() {
        guard let observer else { return }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = nil
        activeSince = nil
    }
}

final class JarvisMemoryPressureMonitor {
    private let source: DispatchSourceMemoryPressure

    init(purge: @escaping @Sendable () -> Void) {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler(handler: purge)
        source.resume()
    }

    deinit {
        source.cancel()
    }
}

struct JarvisFirstFrameProbe: NSViewRepresentable {
    func makeNSView(context _: Context) -> FirstFrameView {
        FirstFrameView()
    }

    func updateNSView(_ nsView: FirstFrameView, context _: Context) {
        nsView.markIfNeeded()
    }

    final class FirstFrameView: NSView {
        private var didMark = false

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            markIfNeeded()
        }

        func markIfNeeded() {
            guard !didMark else { return }
            didMark = true
            JarvisPerformance.emit("first SwiftUI frame")
        }
    }
}
