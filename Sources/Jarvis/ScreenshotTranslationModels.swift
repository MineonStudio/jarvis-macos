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

    /// 二级栏里的状态文字。
    ///
    /// 只保留「正在做什么」和失败原因，不再报「完成了几项」：译文就画在图上，
    /// 数量和进度是多余的。失败仍然要说话，否则用户只看到没翻出来。
    var statusMessage: String? {
        switch self {
        case .idle, .completed:
            nil
        case .recognizing:
            "正在识别文字…"
        case .translating:
            "正在翻译…"
        case .partiallyCompleted:
            "部分翻译失败"
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
