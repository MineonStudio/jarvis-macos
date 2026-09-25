import CoreGraphics
import Observation

@MainActor
@Observable
final class JarvisHomePointerTracker {
    var location: CGPoint?
}
