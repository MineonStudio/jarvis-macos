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

    func testInterruptedLaunchRecoveryMarksInFlightRecordsRetryable() {
        var recording = MeetingRecord(
            title: "录音中",
            audioFileName: "meeting-\(UUID().uuidString).m4a",
            status: .recording
        )
        recording.applyInterruptedLaunchRecovery()
        XCTAssertEqual(recording.status, .failed)
        XCTAssertTrue(recording.canRetryProcessing)
        XCTAssertEqual(
            recording.errorMessage,
            "应用上次退出时录音未正常结束；已保留已写入的原始录音，可重新处理"
        )

        var transcribing = MeetingRecord(
            title: "转写中",
            audioFileName: "meeting-\(UUID().uuidString).m4a",
            status: .transcribing
        )
        transcribing.applyInterruptedLaunchRecovery()
        XCTAssertEqual(transcribing.status, .failed)
        XCTAssertTrue(transcribing.canRetryProcessing)

        var summarizing = MeetingRecord(
            title: "总结中",
            audioFileName: "meeting-\(UUID().uuidString).m4a",
            status: .summarizing,
            transcript: [
                MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: "你好")
            ]
        )
        summarizing.applyInterruptedLaunchRecovery()
        XCTAssertEqual(summarizing.status, .transcribed)
        XCTAssertNil(summarizing.errorMessage)
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
        XCTAssertEqual(loaded.records, [record])
        XCTAssertFalse(loaded.isReadOnly)
        XCTAssertEqual(sourceURL.lastPathComponent, record.audioFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory
                    .appendingPathComponent("Meetings/Records/\(record.id.uuidString).json")
                    .path
            )
        )
    }

    func testRepositoryStoresTranscriptSeparatelyAndKeepsListMetadataLight() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-meeting-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = MeetingRepository(directoryURL: directory)
        let record = MeetingRecord(
            title: "需求评审",
            audioFileName: "meeting-\(UUID().uuidString).m4a",
            speakers: [MeetingSpeaker(id: "S1", name: "主持人", colorIndex: 0)],
            transcript: [
                MeetingTranscriptSegment(startTime: 0, endTime: 2, speakerID: "S1", text: "先确认范围。")
            ],
            summary: MeetingSummary(
                overview: "确认范围",
                keyPoints: ["范围已对齐"],
                decisions: [],
                actionItems: [],
                openQuestions: []
            )
        )
        try repository.save(record)

        let loaded = repository.load()
        XCTAssertEqual(loaded.records.first?.id, record.id)
        XCTAssertEqual(loaded.records.first?.title, "需求评审")
        XCTAssertEqual(loaded.records.first?.transcript, [])
        XCTAssertNil(loaded.records.first?.summary)

        let detail = try XCTUnwrap(repository.loadDetail(for: record.id))
        XCTAssertEqual(detail.transcript.first?.text, "先确认范围。")
        XCTAssertEqual(detail.summary?.overview, "确认范围")

        var titleOnly = loaded.records[0]
        titleOnly.title = "改名后的评审"
        try repository.save(titleOnly)
        XCTAssertEqual(repository.loadDetail(for: record.id)?.transcript.first?.text, "先确认范围。")
    }

    func testMeetingMarkdownIncludesSummaryAndTranscript() {
        let record = MeetingRecord(
            title: "周会",
            audioFileName: "meeting-\(UUID().uuidString).m4a",
            speakers: [MeetingSpeaker(id: "S1", name: "小王", colorIndex: 0)],
            transcript: [
                MeetingTranscriptSegment(startTime: 65, endTime: 70, speakerID: "S1", text: "周五前给方案。")
            ],
            summary: MeetingSummary(
                overview: "本周给出方案",
                keyPoints: ["需要接口清单"],
                decisions: ["先做录音"],
                actionItems: [MeetingActionItem(task: "整理接口", owner: "小王", dueDate: "周五")],
                openQuestions: ["是否采集系统音频"]
            )
        )
        let markdown = record.markdownDocument()
        XCTAssertTrue(markdown.contains("# 周会"))
        XCTAssertTrue(markdown.contains("## 会议总结"))
        XCTAssertTrue(markdown.contains("本周给出方案"))
        XCTAssertTrue(markdown.contains("整理接口"))
        XCTAssertTrue(markdown.contains("**小王** 01:05"))
        XCTAssertTrue(markdown.contains("周五前给方案。"))
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

        for url in [urls.mixed, urls.microphone, urls.system, urls.systemCompressed] {
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data([0x01])))
        }
        XCTAssertEqual(try repository.microphoneAudioURL(for: record), urls.microphone)
        XCTAssertEqual(try repository.systemAudioURL(for: record), urls.system)

        try repository.delete(record)

        XCTAssertFalse(FileManager.default.fileExists(atPath: urls.mixed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls.microphone.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls.system.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls.systemCompressed.path))
        XCTAssertTrue(repository.load().records.isEmpty)
    }

    func testRepositoryMigratesLegacyIndexAndRefusesToOverwriteCorruption() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-meeting-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let meetingsDirectory = directory.appendingPathComponent("Meetings", isDirectory: true)
        try FileManager.default.createDirectory(at: meetingsDirectory, withIntermediateDirectories: true)
        let record = MeetingRecord(
            title: "旧索引",
            audioFileName: "meeting-\(UUID().uuidString).m4a"
        )
        let legacyData = try JSONEncoder().encode([record])
        try legacyData.write(to: meetingsDirectory.appendingPathComponent("meetings.json"))

        let repository = MeetingRepository(directoryURL: directory)
        let migrated = repository.load()
        XCTAssertEqual(migrated.records.map(\.id), [record.id])
        XCTAssertFalse(migrated.isReadOnly)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: meetingsDirectory
                    .appendingPathComponent("Records/\(record.id.uuidString).json")
                    .path
            )
        )

        let corruptDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-meeting-corrupt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: corruptDirectory) }
        let corruptMeetings = corruptDirectory.appendingPathComponent("Meetings", isDirectory: true)
        try FileManager.default.createDirectory(at: corruptMeetings, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: corruptMeetings.appendingPathComponent("meetings.json"))

        let corruptRepository = MeetingRepository(directoryURL: corruptDirectory)
        let corruptLoad = corruptRepository.load()
        XCTAssertTrue(corruptLoad.isReadOnly)
        XCTAssertEqual(corruptLoad.records, [])
        XCTAssertThrowsError(try corruptRepository.save(record)) { error in
            XCTAssertEqual(error as? MeetingRepositoryError, .writesDisabled)
        }
    }

    func testSystemAudioMixDelayUsesLaterCaptureStart() {
        let microphoneStartedAt = Date(timeIntervalSince1970: 100)
        let systemAudioStartedAt = Date(timeIntervalSince1970: 101.25)
        XCTAssertEqual(
            MeetingAudioMixer.systemAudioInsertionDelay(
                microphoneStartedAt: microphoneStartedAt,
                systemAudioStartedAt: systemAudioStartedAt
            ),
            1.25,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            MeetingAudioMixer.systemAudioInsertionDelay(
                microphoneStartedAt: microphoneStartedAt,
                systemAudioStartedAt: nil
            ),
            0
        )
    }

    func testRecordingStyleFormatsHourLongDurations() {
        XCTAssertEqual(MeetingRecordingStyle.formatDuration(59), "00:59")
        XCTAssertEqual(MeetingRecordingStyle.formatDuration(3661), "1:01:01")
        XCTAssertEqual(MeetingRecordingStyle.formatTimestamp(3661), "1:01:01")
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

    func testSummaryServiceExtractsJSONEmbeddedInMarkdown() {
        let raw = """
        这是说明
        ```json
        {"overview":"已提取","keyPoints":[],"decisions":[],"actionItems":[],"openQuestions":[]}
        ```
        """
        XCTAssertEqual(
            MeetingSummaryService.extractJSONObject(raw),
            #"{"overview":"已提取","keyPoints":[],"decisions":[],"actionItems":[],"openQuestions":[]}"#
        )
    }

    func testSummaryServiceForwardsConfiguredAPIEndpointModelAndKey() async throws {
        let api = RecordingMeetingAPI()
        let service = MeetingSummaryService(api: api)
        let record = MeetingRecord(
            title: "配置验证",
            audioFileName: "meeting-\(UUID().uuidString).m4a",
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

    func testMeetingSearchMatchesSingleChineseCharacterAndLatinLetter() {
        let record = MeetingRecord(
            title: "产品评审会",
            audioFileName: "meeting-\(UUID().uuidString).m4a",
            transcript: [
                MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: "先对齐接口")
            ]
        )

        XCTAssertTrue(record.matchesSearch("评"))
        XCTAssertTrue(record.matchesSearch("会"))
        XCTAssertTrue(record.matchesSearch("接"))
        XCTAssertFalse(record.matchesSearch("A"))
        XCTAssertTrue(MeetingRecord(title: "API 评审", audioFileName: "meeting-\(UUID().uuidString).m4a").matchesSearch("A"))
        XCTAssertTrue(MeetingRecord(title: "Q3 规划", audioFileName: "meeting-\(UUID().uuidString).m4a").matchesSearch("3"))
        XCTAssertFalse(record.matchesSearch("无"))
        XCTAssertTrue(record.matchesSearch(" 评 "))
        XCTAssertTrue(record.matchesSearch(""))
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
