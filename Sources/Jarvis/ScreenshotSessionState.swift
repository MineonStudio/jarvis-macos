import Foundation

enum ScreenshotSessionPhase: Equatable {
    case idle
    case capturing
    case selecting
    case editing
    case pinning
}
