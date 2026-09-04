@testable import Jarvis
import XCTest

final class HermesComposerTests: XCTestCase {
    func testPasteClassifierAttachesFilesAndSkipsFinderText() {
        let files = [
            URL(fileURLWithPath: "/tmp/notes.md"),
            URL(fileURLWithPath: "/tmp/shot.png")
        ]
        let result = HermesPasteClassifier.classify(
            fileURLs: files,
            hasImage: true,
            text: "/tmp/notes.md"
        )
        XCTAssertEqual(result.objects, [.file(files[0]), .file(files[1])])
        XCTAssertNil(result.insertText)
    }

    func testPasteClassifierRecognizesImageURLAndPlainTextCaption() {
        let imageOnly = HermesPasteClassifier.classify(
            fileURLs: [],
            hasImage: true,
            text: nil
        )
        XCTAssertEqual(imageOnly.objects, [.image])
        XCTAssertNil(imageOnly.insertText)

        let mixed = HermesPasteClassifier.classify(
            fileURLs: [],
            hasImage: true,
            text: "看看这张图"
        )
        XCTAssertEqual(mixed.objects, [.image])
        XCTAssertEqual(mixed.insertText, "看看这张图")

        let imageAndLink = HermesPasteClassifier.classify(
            fileURLs: [],
            hasImage: true,
            text: "https://example.com/a"
        )
        XCTAssertEqual(imageAndLink.objects, [.image, .url("https://example.com/a")])
        XCTAssertNil(imageAndLink.insertText)
    }

    func testPasteClassifierRecognizesLinksAndExistingPaths() {
        let link = HermesPasteClassifier.classify(
            fileURLs: [],
            hasImage: false,
            text: "https://example.com/docs"
        )
        XCTAssertEqual(link.objects, [.url("https://example.com/docs")])

        let paths = HermesPasteClassifier.classify(
            fileURLs: [],
            hasImage: false,
            text: "/tmp/a.md\n~/Documents/b",
            fileExists: { $0 == "/tmp/a.md" || $0.hasSuffix("/Documents/b") }
        )
        XCTAssertEqual(paths.objects.count, 2)
        XCTAssertEqual(paths.objects.first, .file(URL(fileURLWithPath: "/tmp/a.md")))

        let prose = HermesPasteClassifier.classify(
            fileURLs: [],
            hasImage: false,
            text: "帮我看看这段代码"
        )
        XCTAssertFalse(prose.hasObjects)
        XCTAssertNil(prose.insertText)
    }

    func testHistoryBrowsesNewestUserMessagesFirstAndRestoresDraft() {
        let messages = [
            HermesChatMessage(role: .user, text: "第一条"),
            HermesChatMessage(role: .assistant, text: "收到"),
            HermesChatMessage(role: .user, text: "第二条"),
            HermesChatMessage(role: .user, text: "   ")
        ]
        let history = HermesComposerHistory.userEntries(from: messages)
        XCTAssertEqual(history, ["第二条", "第一条"])

        var state = HermesComposerHistoryState()
        XCTAssertEqual(state.browseBackward(currentDraft: "未发送草稿", history: history), "第二条")
        XCTAssertEqual(state.browseBackward(currentDraft: "", history: history), "第一条")
        XCTAssertNil(state.browseBackward(currentDraft: "", history: history))
        XCTAssertEqual(state.browseForward(history: history), "第二条")
        XCTAssertEqual(state.browseForward(history: history), "未发送草稿")
        XCTAssertFalse(state.isBrowsing)
        XCTAssertNil(state.browseForward(history: history))
    }

    func testHistoryDoesNotStartWhenThereAreNoUserMessages() {
        var state = HermesComposerHistoryState()
        XCTAssertNil(
            state.browseBackward(
                currentDraft: "",
                history: HermesComposerHistory.userEntries(from: [
                    HermesChatMessage(role: .assistant, text: "你好")
                ])
            )
        )
        XCTAssertFalse(state.isBrowsing)
    }
}
