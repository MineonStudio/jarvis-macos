import Foundation

struct ScreenshotTranslationLine: Equatable, Sendable {
    let text: String
    let bounds: CGRect
    let lineHeight: CGFloat

    init(text: String, bounds: CGRect, lineHeight: CGFloat? = nil) {
        self.text = text
        self.bounds = bounds
        self.lineHeight = max(0.001, lineHeight ?? bounds.height)
    }
}

enum ScreenshotTranslationState: Equatable {
    case idle
    case recognizing
    case translating(completed: Int, total: Int)
    case completed(count: Int)
    case partiallyCompleted(completed: Int, total: Int)
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .recognizing, .translating: true
        default: false
        }
    }

    var statusMessage: String? {
        switch self {
        case .idle:
            nil
        case .recognizing:
            "正在识别文字…"
        case let .translating(completed, total):
            "正在翻译 \(completed)/\(total)"
        case let .completed(count):
            "翻译完成：\(count) 项"
        case let .partiallyCompleted(completed, total):
            "部分完成：成功 \(completed)/\(total)，失败 \(max(0, total - completed))"
        case let .failed(message):
            message
        }
    }

    var isFailure: Bool {
        switch self {
        case .failed, .partiallyCompleted:
            true
        default:
            false
        }
    }
}

struct ScreenshotTranslationProgress: Equatable, Sendable {
    let expectedIDs: Set<UUID>
    private(set) var succeededIDs: Set<UUID> = []
    private(set) var invalidResponseCount = 0

    @discardableResult
    mutating func recordResponse(
        blockID: UUID?,
        translatedText: String?
    ) -> Bool {
        guard let blockID,
              expectedIDs.contains(blockID),
              let translatedText,
              !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            invalidResponseCount += 1
            return false
        }
        succeededIDs.insert(blockID)
        return true
    }

    var successCount: Int {
        succeededIDs.count
    }

    var failureCount: Int {
        max(0, expectedIDs.count - successCount)
    }

    var isComplete: Bool {
        !expectedIDs.isEmpty && successCount == expectedIDs.count
    }
}
