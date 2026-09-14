import Foundation
@testable import Jarvis
import XCTest

final class MeetingTests: XCTestCase {
    func testMeetingDefaultTitleAndLegacyTitleDetection() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)
        components.year = 2026
        components.month = 9
        components.day = 14
        components.hour = 15
        components.minute = 0
        let createdAt = try XCTUnwrap(components.date)

        XCTAssertEqual(MeetingRecord.defaultTitle, "未命名会议")
        XCTAssertTrue(
            MeetingRecord.isLegacyGeneratedTitle(
                "会议 · 9月14日 15:00",
                createdAt: createdAt
            )
        )
        XCTAssertFalse(
            MeetingRecord.isLegacyGeneratedTitle(
                "产品评审",
                createdAt: createdAt
            )
        )
    }

    func testRepositoryPersistsMeetingAndAudioURLIsSandboxed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-meeting-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = MeetingRepository(directoryURL: directory)
        let record = MeetingRecord(
            title: "产品评审",
            audioFileName: "meeting-\(UUID().uuidString).m4a"
        )

        try repository.save(record)

        let sourceURL = try repository.audioURL(for: record)
        XCTAssertTrue(FileManager.default.createFile(atPath: sourceURL.path, contents: Data([0x01, 0x02])))

        let loaded = repository.load()
        XCTAssertEqual(loaded, [record])
        XCTAssertEqual(sourceURL.lastPathComponent, record.audioFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testRepositoryRejectsPathTraversalAudioName() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-meeting-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = MeetingRepository(directoryURL: directory)
        let invalidRecord = MeetingRecord(title: "无效", audioFileName: "../outside.m4a")

        XCTAssertThrowsError(try repository.audioURL(for: invalidRecord)) { error in
            XCTAssertEqual(error as? MeetingRepositoryError, .invalidAudioFileName)
        }
    }

    func testRepositoryResolvesAndDeletesAllMeetingAudioTracks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-meeting-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = MeetingRepository(directoryURL: directory)
        let id = UUID()
        let urls = repository.recordingURLs(for: id)
        let record = MeetingRecord(
            id: id,
            title: "双轨录音",
            audioFileName: urls.mixed.lastPathComponent,
            microphoneAudioFileName: urls.microphone.lastPathComponent,
            systemAudioFileName: urls.system.lastPathComponent
        )
        try repository.save(record)

        for url in [urls.mixed, urls.microphone, urls.system] {
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data([0x01])))
        }
        XCTAssertEqual(try repository.microphoneAudioURL(for: record), urls.microphone)
        XCTAssertEqual(try repository.systemAudioURL(for: record), urls.system)

        try repository.delete(record)

        XCTAssertFalse(FileManager.default.fileExists(atPath: urls.mixed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls.microphone.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls.system.path))
    }

    func testSummaryServiceDecodesStructuredChineseSummary() async throws {
        let response = #"{"overview":"确定在本周完成首版","keyPoints":["用户需要本地记录"],"decisions":["先做录音和总结"],"actionItems":[{"task":"整理接口清单","owner":"小王","dueDate":"周五"}],"openQuestions":["是否需要系统音频"]}"#
        let service = MeetingSummaryService(api: StubMeetingAPI(response: response))
        let record = MeetingRecord(
            title: "规划会",
            audioFileName: "meeting-\(UUID().uuidString).m4a",
            speakers: [MeetingSpeaker(id: "S1", name: "主持人", colorIndex: 0)],
            transcript: [
                MeetingTranscriptSegment(
                    startTime: 0,
                    endTime: 2,
                    speakerID: "S1",
                    text: "我们本周完成首版。"
                )
            ]
        )
        let configuration = AIAPIConfiguration(
            endpoint: "https://example.com/v1/chat/completions",
            model: "test",
            apiKey: "test-key"
        )

        let summary = try await service.summarize(record: record, configuration: configuration)

        XCTAssertEqual(summary.overview, "确定在本周完成首版")
        XCTAssertEqual(summary.decisions, ["先做录音和总结"])
        XCTAssertEqual(summary.actionItems.first?.owner, "小王")
        XCTAssertEqual(summary.openQuestions, ["是否需要系统音频"])
    }

    func testSummaryServiceForwardsConfiguredAPIEndpointModelAndKey() async throws {
        let api = RecordingMeetingAPI()
        let service = MeetingSummaryService(api: api)
        let record = MeetingRecord(
            title: "配置验证",
            audioFileName: "meeting-(UUID().uuidString).m4a",
            speakers: [MeetingSpeaker(id: "S1", name: "主持人", colorIndex: 0)],
            transcript: [
                MeetingTranscriptSegment(
                    startTime: 0,
                    endTime: 1,
                    speakerID: "S1",
                    text: "请使用设置里的接口生成总结。"
                )
            ]
        )
        let configuration = AIAPIConfiguration(
            endpoint: "https://configured.example/v1/chat/completions",
            model: "configured-model",
            apiKey: "configured-secret"
        )

        _ = try await service.summarize(record: record, configuration: configuration)

        let received = await api.receivedConfiguration
        XCTAssertEqual(received, configuration)
    }

    func testSummaryServiceChunksLongTranscriptBeforeMerging() async throws {
        let response = #"{"overview":"已合并长会议摘要","keyPoints":["重点"],"decisions":[],"actionItems":[],"openQuestions":[]}"#
        let service = MeetingSummaryService(api: StubMeetingAPI(response: response))
        let record = MeetingRecord(
            title: "长会",
            audioFileName: "meeting-\(UUID().uuidString).m4a",
            speakers: [MeetingSpeaker(id: "S1", name: "说话人 1", colorIndex: 0)],
            transcript: [
                MeetingTranscriptSegment(
                    startTime: 0,
                    endTime: 1,
                    speakerID: "S1",
                    text: String(repeating: "这是一段需要被分段处理的会议内容。", count: 900)
                )
            ]
        )
        let configuration = AIAPIConfiguration(
            endpoint: "https://example.com/v1/chat/completions",
            model: "test",
            apiKey: "test-key"
        )

        let summary = try await service.summarize(record: record, configuration: configuration)

        XCTAssertEqual(summary.overview, "已合并长会议摘要")
    }

    func testMeetingSkillIsAvailableInNavigation() {
        XCTAssertTrue(SkillID.allCases.contains(.meetingNotes))
        XCTAssertEqual(SkillID.meetingNotes.navigationTitle, "会议记录")
    }
}

private struct StubMeetingAPI: AITextCompletionAPI {
    let response: String

    func complete(
        systemPrompt _: String,
        userPrompt _: String,
        configuration _: AIAPIConfiguration
    ) async throws -> String {
        response
    }
}

private actor RecordingMeetingAPI: AITextCompletionAPI {
    private(set) var receivedConfiguration: AIAPIConfiguration?

    func complete(
        systemPrompt _: String,
        userPrompt _: String,
        configuration: AIAPIConfiguration
    ) async throws -> String {
        receivedConfiguration = configuration
        return #"{"overview":"配置生效","keyPoints":[],"decisions":[],"actionItems":[],"openQuestions":[]}"#
    }
}
