import AVFoundation
import Foundation
@testable import Jarvis
import XCTest

final class MeetingTests: XCTestCase {
    func testMeetingDefaultTitleAndLegacyTitleDetection() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = 2026
        components.month = 9
        components.day = 14
        components.hour = 15
        components.minute = 0
        let createdAt = try XCTUnwrap(components.date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日 HH:mm"

        XCTAssertEqual(MeetingRecord.defaultTitle, "未命名会议")
        XCTAssertTrue(
            MeetingRecord.isLegacyGeneratedTitle(
                "会议 · \(formatter.string(from: createdAt))",
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
        XCTAssertEqual(recording.interruptedRecording, true)
        XCTAssertEqual(
            recording.errorMessage,
            "录音未正常结束，已保留约 00:00。可以手动继续处理，不会自动开始转写。"
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
        XCTAssertEqual(summarizing.status, .summaryFailed)
        XCTAssertTrue(summarizing.canRetryProcessing)
        XCTAssertEqual(
            summarizing.errorMessage,
            "总结中断，已保留逐字稿，可重新生成纪要"
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
        XCTAssertTrue(repository.detailMatchesSearch(for: record.id, query: "先确认"))
        XCTAssertTrue(repository.detailMatchesSearch(for: record.id, query: "范围已对齐"))
        XCTAssertFalse(repository.detailMatchesSearch(for: record.id, query: "不存在的词"))

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
        XCTAssertTrue(markdown.contains("- 说话人：小王"))
        XCTAssertTrue(markdown.contains("## 概要"))
        XCTAssertTrue(markdown.contains("本周给出方案"))
        XCTAssertTrue(markdown.contains("## 讨论要点"))
        XCTAssertTrue(markdown.contains("先做录音"))
        XCTAssertTrue(markdown.contains("是否采集系统音频"))
        XCTAssertTrue(markdown.contains("需要接口清单"))
        XCTAssertTrue(markdown.contains("## 待办"))
        XCTAssertTrue(markdown.contains("整理接口"))
        XCTAssertTrue(markdown.contains("负责人：小王"))
        XCTAssertTrue(markdown.contains("期限：周五"))
        XCTAssertTrue(markdown.contains("**小王** 01:05"))
        XCTAssertTrue(markdown.contains("周五前给方案。"))

        let conciseMarkdown = record.markdownDocument(includeTranscript: false)
        XCTAssertTrue(conciseMarkdown.contains("## 概要"))
        XCTAssertTrue(conciseMarkdown.contains("## 待办"))
        XCTAssertFalse(conciseMarkdown.contains("## 逐字稿"))
        XCTAssertFalse(conciseMarkdown.contains("周五前给方案。"))
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

        let recordingsDirectory = urls.microphone.deletingLastPathComponent()
        let chunkURL = recordingsDirectory.appendingPathComponent(
            MeetingAudioChunkFile.microphoneName(meetingID: id, index: 0)
        )
        let strayURL = recordingsDirectory.appendingPathComponent("meeting-\(id.uuidString).notes.txt")
        for url in [urls.mixed, urls.microphone, urls.system, urls.systemCompressed, chunkURL, strayURL] {
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data([0x01])))
        }
        XCTAssertEqual(try repository.microphoneAudioURL(for: record), urls.microphone)
        XCTAssertEqual(try repository.systemAudioURL(for: record), urls.system)

        try repository.delete(record)

        XCTAssertFalse(FileManager.default.fileExists(atPath: urls.mixed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls.microphone.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls.system.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls.systemCompressed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: chunkURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: strayURL.path))
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

    func testMinutesKeepsExactQuotesAndDropsRewrittenOnes() async throws {
        let segment = MeetingTranscriptSegment(
            startTime: 1,
            endTime: 3,
            speakerID: "S1",
            text: "埋点由客户端上报。"
        )
        let summaryText = paddedSummary("埋点由客户端上报。")
        let response = try minutesJSON(
            summary: summaryText,
            points: [
                point("P1", "客户端上报", "埋点由客户端上报。", evidence(segment, quote: "埋点由客户端上报。")),
                point("P2", "编造", "这里不是原句", evidence(segment, quote: "这里不是原句"))
            ]
        )
        let summary = try await MeetingSummaryService(
            api: MeetingTestAPI(summaryResponse: response)
        ).summarize(
            record: meetingRecord(title: "埋点", segments: [segment]),
            configuration: testSummaryConfiguration
        )

        XCTAssertEqual(summary.points.map(\.id), ["P1"])
        XCTAssertEqual(summary.points.first?.evidence.first?.quote, "埋点由客户端上报。")
        XCTAssertEqual(summary.overview, summaryText)
    }

    func testMinutesClearsInventedOwnersAndSpokenDueDates() async throws {
        let segment = MeetingTranscriptSegment(
            startTime: 0,
            endTime: 2,
            speakerID: "S1",
            text: "文档我待会发你。"
        )
        let response = try minutesJSON(
            summary: paddedSummary("会后发送埋点文档。"),
            todos: [
                todo(
                    "T1",
                    "把埋点文档发给开发",
                    owner: "丁鹏华",
                    due: "待会",
                    evidence: evidence(segment, quote: "文档我待会发你。")
                ),
                todo(
                    "T2",
                    "由说话人 1 发送文档",
                    owner: "说话人 1",
                    due: "周五",
                    evidence: evidence(segment, quote: "文档我待会发你。")
                )
            ]
        )
        let summary = try await MeetingSummaryService(
            api: MeetingTestAPI(summaryResponse: response)
        ).summarize(
            record: meetingRecord(
                title: "待办",
                segments: [segment],
                speakers: [MeetingSpeaker(id: "S1", name: "说话人 1", colorIndex: 0)]
            ),
            configuration: testSummaryConfiguration
        )

        XCTAssertEqual(summary.actionItems.map(\.owner), ["", "说话人 1"])
        XCTAssertEqual(summary.actionItems.map(\.ownerMissing), ["未指定", nil])
        XCTAssertEqual(summary.actionItems.map(\.dueDate), ["", "周五"])
        XCTAssertEqual(summary.actionItems.map(\.dueMissing), ["未提及", nil])
        XCTAssertEqual(summary.actionItems.map(\.ownerLabel), ["未指定", "说话人 1"])
        XCTAssertEqual(summary.actionItems.map(\.dueLabel), ["未提及", "周五"])
    }

    func testRelativeDueDateKeepsSpokenWordsAndAddsMeetingDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "zh_CN")
        let meetingDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12)))
        let segment = MeetingTranscriptSegment(
            startTime: 0,
            endTime: 2,
            speakerID: "S1",
            text: "下周三前给设计图。"
        )
        let draft = MeetingMinutesAlgorithm.DraftMinutes(
            summary: paddedSummary("设计图下周三给。"),
            points: [],
            todos: [
                MeetingMinutesAlgorithm.DraftTodo(
                    id: "T1",
                    task: "提供设计图",
                    owner: nil,
                    due: "下周三",
                    evidence: [
                        MeetingMinutesAlgorithm.DraftEvidence(
                            segmentID: segment.id.uuidString,
                            startMs: 0,
                            endMs: 2000,
                            quote: "下周三前给设计图。"
                        )
                    ]
                )
            ]
        )
        let result = MeetingMinutesAlgorithm.validate(
            draft,
            transcript: [segment],
            speakers: [MeetingSpeaker(id: "S1", name: "说话人 1", colorIndex: 0)],
            meetingDate: meetingDate,
            generation: sampleGeneration,
            calendar: calendar
        )
        XCTAssertEqual(
            result.summary.actionItems.first?.dueDate,
            "下周三（由会议日期 2026-10-07 换算为 2026-10-14）"
        )
    }

    func testRegenerationKeepsEditedOverviewCompletedTodos() {
        let segmentID = UUID()
        let evidence = MeetingEvidence(segmentID: segmentID, startMs: 0, endMs: 1000, quote: "原文")
        let generated = MeetingSummary(
            overview: paddedSummary("新概要"),
            keyPoints: [],
            decisions: [],
            actionItems: [
                MeetingActionItem(task: "发送文档", owner: "说话人 1", dueDate: "", evidence: [evidence])
            ],
            openQuestions: [],
            points: [
                MeetingDiscussionPoint(id: "P1", title: "新要点", detail: "新说明", evidence: [evidence])
            ]
        )
        var previous = generated
        previous.overview = "我改过的概要"
        previous.overviewIsUserEdited = true
        previous.points[0].title = "我改过的要点"
        previous.points[0].isUserEdited = true
        previous.actionItems[0].isCompleted = true

        let merged = MeetingMinutesAlgorithm.merging(generated, preserving: previous)
        XCTAssertEqual(merged.overview, "我改过的概要")
        XCTAssertEqual(merged.points.first?.title, "我改过的要点")
        XCTAssertTrue(merged.actionItems.first?.isCompleted == true)
    }

    func testMinutesRetriesOnceAfterInvalidJSON() async throws {
        let segment = MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: "先做首版。")
        let valid = try minutesJSON(
            summary: paddedSummary("先做首版。"),
            points: [point("P1", "先做首版", "", evidence(segment, quote: "先做首版。"))]
        )
        let api = MeetingTestAPI(
            summaryResponse: valid,
            scriptedResponses: ["不是 JSON", valid]
        )
        let summary = try await MeetingSummaryService(api: api).summarize(
            record: meetingRecord(title: "重试", segments: [segment]),
            configuration: testSummaryConfiguration
        )
        XCTAssertEqual(summary.points.map(\.title), ["先做首版"])
        let count = await api.receivedOptions.count
        XCTAssertEqual(count, 2)
    }

    func testMinutesDoesNotPublishPartialResultAfterSecondFailure() async throws {
        let segment = MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: "先做首版。")
        let api = MeetingTestAPI(
            summaryResponse: "不会用到",
            scriptedResponses: ["不是 JSON", "还是不是"]
        )
        do {
            _ = try await MeetingSummaryService(api: api).summarize(
                record: meetingRecord(title: "失败", segments: [segment]),
                configuration: testSummaryConfiguration
            )
            XCTFail("第二次仍不合格时不应该返回纪要")
        } catch let error as MeetingMinutesError {
            XCTAssertEqual(error, .schemaRejected)
        }
        let count = await api.receivedOptions.count
        XCTAssertEqual(count, 2)
    }

    func testUncertainSpeakerWhenOverlapIsWeakOrSpeechOverlaps() {
        let turns = [
            MeetingMinutesAlgorithm.SpeakerTurn(speakerID: "A", startTime: 0, endTime: 5),
            MeetingMinutesAlgorithm.SpeakerTurn(speakerID: "B", startTime: 5, endTime: 10)
        ]
        XCTAssertEqual(
            MeetingMinutesAlgorithm.assignedSpeakerID(startTime: 0, endTime: 4, turns: turns),
            "A"
        )
        XCTAssertEqual(
            MeetingMinutesAlgorithm.assignedSpeakerID(startTime: 0, endTime: 0.5, turns: turns),
            MeetingMinutesAlgorithm.uncertainSpeakerID
        )
        XCTAssertEqual(
            MeetingMinutesAlgorithm.assignedSpeakerID(startTime: 4, endTime: 6, turns: turns),
            MeetingMinutesAlgorithm.uncertainSpeakerID
        )
        XCTAssertEqual(
            MeetingMinutesAlgorithm.assignedSpeakerID(
                startTime: 0,
                endTime: 2,
                turns: [MeetingMinutesAlgorithm.SpeakerTurn(speakerID: "A", startTime: 0, endTime: 0.4)]
            ),
            MeetingMinutesAlgorithm.uncertainSpeakerID
        )
        XCTAssertEqual(
            MeetingMinutesAlgorithm.assignedSpeakerID(
                startTime: 0,
                endTime: 2,
                turns: [
                    MeetingMinutesAlgorithm.SpeakerTurn(speakerID: "A", startTime: 0, endTime: 0.4),
                    MeetingMinutesAlgorithm.SpeakerTurn(speakerID: "A", startTime: 0.6, endTime: 1.0),
                    MeetingMinutesAlgorithm.SpeakerTurn(speakerID: "A", startTime: 1.2, endTime: 1.6)
                ]
            ),
            "A"
        )
        XCTAssertEqual(
            MeetingMinutesAlgorithm.assignedSpeakerID(
                startTime: 0,
                endTime: 2,
                turns: [
                    MeetingMinutesAlgorithm.SpeakerTurn(speakerID: "A", startTime: 0, endTime: 0.6),
                    MeetingMinutesAlgorithm.SpeakerTurn(speakerID: "A", startTime: 0.2, endTime: 0.8)
                ]
            ),
            MeetingMinutesAlgorithm.uncertainSpeakerID
        )
    }

    func testSystemCaptureStopSilencesTheMeterAndChangesTheFinishedNotice() {
        var level = MeetingSystemLevelState(power: -12)
        level.observe(-8)
        XCTAssertEqual(level.power, -8)
        XCTAssertFalse(MeetingSystemLevelState.shouldFreeze(stopRequested: true))
        XCTAssertTrue(MeetingSystemLevelState.shouldFreeze(stopRequested: false))
        level.freezeSilent()
        level.observe(-3)
        XCTAssertEqual(level.power, MeetingSystemLevelState.silentFloor)
        XCTAssertLessThan(MeetingSystemLevelState.silentFloor, -45)
        XCTAssertNil(
            MeetingSystemAudioStopNotice.message(wroteSystemAudio: false, failureMessage: "系统音频采集中断")
        )
        XCTAssertNil(
            MeetingSystemAudioStopNotice.message(wroteSystemAudio: true, failureMessage: nil)
        )
        XCTAssertEqual(
            MeetingSystemAudioStopNotice.message(
                wroteSystemAudio: true,
                failureMessage: "系统音频采集中断：断开"
            ),
            JarvisFeedbackCopy.systemAudioCaptureInterrupted
        )
        XCTAssertNotEqual(
            JarvisFeedbackCopy.systemAudioCaptureInterrupted,
            JarvisFeedbackCopy.recordingStartedWithoutSystemAudio
        )
    }

    func testDeviceChangeKeepsAShortMicrophoneSlice() {
        XCTAssertTrue(MeetingMicrophoneRotation.keepsOpenSlice(0.2))
        XCTAssertTrue(MeetingMicrophoneRotation.keepsOpenSlice(1))
        XCTAssertFalse(MeetingMicrophoneRotation.keepsOpenSlice(0.05))
        XCTAssertFalse(MeetingMicrophoneRotation.keepsOpenSlice(0))
    }

    func testMicrophoneGateKeepsCloseSpeechAndDropsSpeakerBleed() {
        let rate = 100.0
        var gated = MeetingMicrophoneSpeechGate(enabled: true)
        let closeSpeech = gateSamples(decibels: -20, count: 8)
        XCTAssertEqual(
            gated.consume(samples: closeSpeech, sampleRate: rate, systemPower: -10),
            closeSpeech
        )

        var playback = MeetingMicrophoneSpeechGate(enabled: true)
        let bleed = gateSamples(decibels: -34, count: 30)
        let dropped = playback.consume(samples: bleed, sampleRate: rate, systemPower: -10)
        XCTAssertEqual(dropped, [Float](repeating: 0, count: 10))

        var quietRoom = MeetingMicrophoneSpeechGate(enabled: true)
        let softSpeech = gateSamples(decibels: -38, count: 8)
        XCTAssertEqual(
            quietRoom.consume(samples: softSpeech, sampleRate: rate, systemPower: -60),
            softSpeech
        )

        var passthrough = MeetingMicrophoneSpeechGate(enabled: false)
        let quiet = gateSamples(decibels: -50, count: 30)
        XCTAssertEqual(
            passthrough.consume(samples: quiet, sampleRate: rate, systemPower: -10),
            quiet
        )
    }

    func testMicrophoneGateKeepsTheWordOnsetAndAShortTail() {
        let rate = 10.0
        var gate = MeetingMicrophoneSpeechGate(enabled: true)
        let quiet = gateSamples(decibels: -50, count: 1)
        XCTAssertEqual(gate.consume(samples: quiet, sampleRate: rate, systemPower: -10), [])
        XCTAssertEqual(gate.consume(samples: quiet, sampleRate: rate, systemPower: -10), [])

        let speech = gateSamples(decibels: -20, count: 1)
        XCTAssertEqual(
            gate.consume(samples: speech, sampleRate: rate, systemPower: -10),
            quiet + quiet + speech
        )

        XCTAssertEqual(gate.consume(samples: quiet, sampleRate: rate, systemPower: -10), quiet)
        XCTAssertEqual(gate.consume(samples: quiet, sampleRate: rate, systemPower: -10), quiet)
        XCTAssertEqual(gate.consume(samples: quiet, sampleRate: rate, systemPower: -10), quiet)
        XCTAssertEqual(gate.consume(samples: quiet, sampleRate: rate, systemPower: -10), quiet)
        XCTAssertEqual(gate.consume(samples: quiet, sampleRate: rate, systemPower: -10), [])

        var ending = MeetingMicrophoneSpeechGate(enabled: true)
        XCTAssertEqual(ending.consume(samples: quiet, sampleRate: rate, systemPower: -60), [])
        XCTAssertEqual(ending.flush(), [Float](repeating: 0, count: 1))
    }

    func testFailedTranscriptionDropsOnlyTheTurnsAddedForThatTrack() {
        let turns = [
            MeetingMinutesAlgorithm.SpeakerTurn(speakerID: "system:0", startTime: 0, endTime: 2),
            MeetingMinutesAlgorithm.SpeakerTurn(speakerID: "mic:1", startTime: 0, endTime: 2)
        ]
        let kept = MeetingTrackFailure.turnsAfterFailedTranscription(turns, appendedFrom: 1)
        XCTAssertEqual(kept.map(\.speakerID), ["system:0"])
        let unchanged = MeetingTrackFailure.turnsAfterFailedTranscription(turns, appendedFrom: turns.count)
        XCTAssertEqual(unchanged.map(\.speakerID), ["system:0", "mic:1"])
    }

    func testUtteranceSplitsWhenTheSpeakerChangesAndKeepsThePauseRule() {
        let sameSpeaker = [
            MeetingMinutesAlgorithm.SpeakerTurn(speakerID: "A", startTime: 0, endTime: 4)
        ]
        let handoff = [
            MeetingMinutesAlgorithm.SpeakerTurn(speakerID: "A", startTime: 0, endTime: 1.2),
            MeetingMinutesAlgorithm.SpeakerTurn(speakerID: "B", startTime: 1.5, endTime: 3)
        ]
        XCTAssertFalse(
            MeetingMinutesAlgorithm.shouldSplitUtterance(
                currentText: "我们先看范围",
                currentStart: 0,
                currentEnd: 1.2,
                nextStart: 1.5,
                nextEnd: 2.6,
                turns: sameSpeaker
            )
        )
        XCTAssertTrue(
            MeetingMinutesAlgorithm.shouldSplitUtterance(
                currentText: "我们先看范围",
                currentStart: 0,
                currentEnd: 1.2,
                nextStart: 1.5,
                nextEnd: 2.6,
                turns: handoff
            )
        )
        XCTAssertTrue(
            MeetingMinutesAlgorithm.shouldSplitUtterance(
                currentText: "我们先看范围",
                currentStart: 0,
                currentEnd: 1.2,
                nextStart: 3,
                nextEnd: 4,
                turns: sameSpeaker
            )
        )
        XCTAssertFalse(
            MeetingMinutesAlgorithm.shouldSplitUtterance(
                currentText: "我们先看范围",
                currentStart: 0,
                currentEnd: 1.2,
                nextStart: 1.5,
                nextEnd: 2.6,
                turns: []
            )
        )
        XCTAssertTrue(
            MeetingMinutesAlgorithm.shouldSplitUtterance(
                currentText: String(repeating: "字", count: 181),
                currentStart: 0,
                currentEnd: 1.2,
                nextStart: 1.3,
                nextEnd: 2,
                turns: sameSpeaker
            )
        )
    }

    func testSummaryServiceKeepsALongOverviewAfterOneRetry() async throws {
        let segment = MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: "请完整保留。")
        let longOverview = String(repeating: "完整结论。", count: 90)
        let response = try minutesJSON(summary: longOverview)
        let api = MeetingTestAPI(summaryResponse: response)
        let summary = try await MeetingSummaryService(api: api).summarize(
            record: meetingRecord(title: "完整输出", segments: [segment]),
            configuration: testSummaryConfiguration
        )
        XCTAssertEqual(summary.overview, longOverview)
        let count = await api.receivedOptions.count
        XCTAssertEqual(count, 2)
    }

    func testSummaryServiceChunksLongTranscriptBeforeMerging() async throws {
        let response = try minutesJSON(summary: paddedSummary("已合并长会议摘要"))
        let record = meetingRecord(
            title: "长会",
            segments: [
                MeetingTranscriptSegment(
                    startTime: 0,
                    endTime: 1,
                    speakerID: "S1",
                    text: String(repeating: "这是一段需要被分段处理的会议内容。", count: 900)
                )
            ]
        )
        let api = MeetingTestAPI(summaryResponse: response)
        let summary = try await MeetingSummaryService(api: api).summarize(
            record: record,
            configuration: testSummaryConfiguration
        )
        XCTAssertEqual(summary.overview, paddedSummary("已合并长会议摘要"))
        let tasks = await api.receivedOptions.map(\.task)
        XCTAssertGreaterThan(tasks.count, 1)
        XCTAssertTrue(tasks.allSatisfy { $0 == AICompletionOptions.meetingSummary.task })
    }

    func testSummaryServiceResumesFinishedCheckpointWithoutAnotherCall() async throws {
        let response = try minutesJSON(summary: paddedSummary("从检查点继续生成"))
        let segment = MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: "保留后继续。")
        let record = meetingRecord(title: "断点", segments: [segment])
        let firstAPI = MeetingTestAPI(summaryResponse: response)
        let checkpointBox = LockedCheckpointBox()
        _ = try await MeetingSummaryService(api: firstAPI).summarize(
            record: record,
            configuration: testSummaryConfiguration,
            onCheckpoint: { checkpointBox.set($0) }
        )
        let checkpoint = try XCTUnwrap(checkpointBox.value)
        let resumedAPI = MeetingTestAPI(summaryResponse: response)
        let resumed = try await MeetingSummaryService(api: resumedAPI).summarize(
            record: record,
            configuration: testSummaryConfiguration,
            checkpoint: checkpoint
        )
        XCTAssertEqual(resumed.overview, paddedSummary("从检查点继续生成"))
        let count = await resumedAPI.receivedOptions.count
        XCTAssertEqual(count, 0)
    }

    func testSummaryServiceForwardsConfiguredAPIEndpointModelAndKey() async throws {
        let segment = MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: "请使用设置里的接口。")
        let api = try MeetingTestAPI(
            summaryResponse: minutesJSON(summary: paddedSummary("配置生效"))
        )
        let configuration = AIAPIConfiguration(
            endpoint: "https://configured.example/v1/chat/completions",
            model: "configured-model",
            apiKey: "configured-secret"
        )
        _ = try await MeetingSummaryService(api: api).summarize(
            record: meetingRecord(title: "配置", segments: [segment]),
            configuration: configuration
        )
        let received = await api.receivedConfiguration
        XCTAssertEqual(received, configuration)
        let tasks = await api.receivedOptions.map(\.task)
        XCTAssertEqual(tasks, [AICompletionOptions.meetingSummary.task])
    }

    func testSummaryServiceExtractsJSONEmbeddedInMarkdown() {
        let raw = """
        这是说明
        ```json
        {"summary":"已提取","points":[],"todos":[]}
        ```
        """
        XCTAssertEqual(
            MeetingSummaryService.extractJSONObject(raw),
            #"{"summary":"已提取","points":[],"todos":[]}"#
        )
    }

    func testMarkdownExportIncludesEvidenceAndSpeakerNames() {
        let segment = MeetingTranscriptSegment(startTime: 12, endTime: 14, speakerID: "S1", text: "先做首版。")
        let record = MeetingRecord(
            title: "导出",
            audioFileName: "meeting.m4a",
            speakers: [MeetingSpeaker(id: "S1", name: "说话人 1", colorIndex: 0)],
            transcript: [segment],
            summary: MeetingSummary(
                overview: "先做首版。",
                keyPoints: [],
                decisions: [],
                actionItems: [
                    MeetingActionItem(
                        task: "完成首版",
                        evidence: [
                            MeetingEvidence(
                                segmentID: segment.id,
                                startMs: 12000,
                                endMs: 14000,
                                quote: "先做首版。"
                            )
                        ],
                        ownerMissing: "未指定",
                        dueMissing: "未提及"
                    )
                ],
                openQuestions: [],
                points: [
                    MeetingDiscussionPoint(
                        id: "P1",
                        title: "先做首版",
                        detail: "会上确认先做首版。",
                        evidence: [
                            MeetingEvidence(
                                segmentID: segment.id,
                                startMs: 12000,
                                endMs: 14000,
                                quote: "先做首版。"
                            )
                        ]
                    )
                ]
            )
        )
        let markdown = record.markdownDocument()
        XCTAssertTrue(markdown.contains("## 概要"))
        XCTAssertTrue(markdown.contains("## 讨论要点"))
        XCTAssertTrue(markdown.contains("## 待办"))
        XCTAssertTrue(markdown.contains("负责人：未指定"))
        XCTAssertTrue(markdown.contains("期限：未提及"))
        XCTAssertTrue(markdown.contains("出处"))
        XCTAssertTrue(markdown.contains("说话人 1"))
        XCTAssertTrue(record.plainTranscriptDocument().contains("先做首版。"))
        XCTAssertFalse(MeetingExport.pdfData(for: record).isEmpty)
    }

    @MainActor
    func testShortSummaryUsesAnIndeterminateProgressWhileTheRequestRuns() async throws {
        let segment = MeetingTranscriptSegment(
            startTime: 0,
            endTime: 1,
            speakerID: "S1",
            text: "今天确认了发布范围。"
        )
        let record = MeetingRecord(
            title: "短会",
            audioFileName: "meeting-\(UUID().uuidString).m4a",
            speakers: [MeetingSpeaker(id: "S1", name: "主持人", colorIndex: 0)],
            transcript: [segment]
        )
        var progressValues: [Double?] = []
        _ = try await MeetingSummaryService(
            api: MeetingTestAPI(
                summaryResponse: #"{"overview":"确认了发布范围","keyPoints":[],"decisions":[],"actionItems":[],"openQuestions":[]}"#
            )
        ).summarize(
            record: record,
            configuration: AIAPIConfiguration(
                endpoint: "https://example.com/v1/chat/completions",
                model: "test",
                apiKey: "test-key"
            ),
            onProgress: { progressValues.append($0) }
        )

        XCTAssertTrue(progressValues.contains(nil))
        XCTAssertFalse(progressValues.contains { $0 == 0.96 })
    }

    @MainActor
    func testLongSummaryProgressAdvancesAndDoesNotStickAtNinetySix() async throws {
        let segment = MeetingTranscriptSegment(
            startTime: 0,
            endTime: 1,
            speakerID: "S1",
            text: String(repeating: "这是一段需要被分段处理的会议内容。", count: 900)
        )
        let record = MeetingRecord(
            title: "长会进度",
            audioFileName: "meeting-\(UUID().uuidString).m4a",
            speakers: [MeetingSpeaker(id: "S1", name: "说话人 1", colorIndex: 0)],
            transcript: [segment]
        )
        var progressValues: [Double?] = []
        _ = try await MeetingSummaryService(
            api: MeetingTestAPI(
                summaryResponse: #"{"overview":"已合并长会议摘要","keyPoints":[],"decisions":[],"actionItems":[],"openQuestions":[]}"#
            )
        ).summarize(
            record: record,
            configuration: AIAPIConfiguration(
                endpoint: "https://example.com/v1/chat/completions",
                model: "test",
                apiKey: "test-key"
            ),
            onProgress: { progressValues.append($0) }
        )

        let numeric = progressValues.compactMap(\.self)
        XCTAssertGreaterThan(numeric.count, 1)
        XCTAssertFalse(numeric.contains { abs($0 - 0.96) < 0.0001 })
        XCTAssertLessThan(numeric.last ?? 1, 1)
        for pair in zip(numeric, numeric.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1 + 0.0001, pair.0)
        }
    }

    func testInsufficientBalanceIsQuotaAndBareBalanceIsNot() {
        let screenshot = AIAPIError.server(
            "Insufficient Balance (request_id: 6f26e052-8f08-47b0-a908-442d3ca847e4)"
        )
        XCTAssertEqual(MeetingMinutesError.classify(screenshot) as? MeetingMinutesError, .quota)
        XCTAssertEqual(
            MeetingMinutesError.classify(AIAPIError.server("余额不足")) as? MeetingMinutesError,
            .quota
        )
        XCTAssertEqual(
            MeetingMinutesError.classify(AIAPIError.server("HTTP 429")) as? MeetingMinutesError,
            .quota
        )
        let balance = AIAPIError.server("账户余额已更新")
        XCTAssertEqual(MeetingMinutesError.classify(balance) as? AIAPIError, balance)
        let englishBalance = AIAPIError.server("account balance updated")
        XCTAssertEqual(MeetingMinutesError.classify(englishBalance) as? AIAPIError, englishBalance)
    }

    func testCombiningWindowsJoinsPaidSummariesWithoutInventingText() {
        let segmentID = UUID()
        let firstEvidence = MeetingEvidence(segmentID: segmentID, startMs: 0, endMs: 1000, quote: "先做首版。")
        let secondEvidence = MeetingEvidence(segmentID: segmentID, startMs: 1000, endMs: 2000, quote: "下周三再看。")
        let todoID = UUID()
        let first = MeetingSummary(
            overview: "第一段概要",
            keyPoints: [],
            decisions: [],
            actionItems: [
                MeetingActionItem(id: todoID, task: "整理发布说明", evidence: [firstEvidence])
            ],
            openQuestions: [],
            points: [
                MeetingDiscussionPoint(
                    id: "P1",
                    title: "发布范围",
                    detail: "确认发布范围。",
                    evidence: [firstEvidence]
                )
            ]
        )
        let second = MeetingSummary(
            overview: "第二段概要",
            keyPoints: [],
            decisions: [],
            actionItems: [
                MeetingActionItem(task: "整理发布说明", evidence: [secondEvidence])
            ],
            openQuestions: [],
            points: [
                MeetingDiscussionPoint(
                    id: "P1",
                    title: "发布范围",
                    detail: "确认发布范围。",
                    evidence: [firstEvidence]
                ),
                MeetingDiscussionPoint(
                    id: "P2",
                    title: "回滚",
                    detail: "准备回滚。",
                    evidence: [secondEvidence]
                )
            ]
        )
        let blank = MeetingSummary(
            overview: "  ",
            keyPoints: [],
            decisions: [],
            actionItems: [],
            openQuestions: []
        )
        let repeated = MeetingSummary(
            overview: "第二段概要",
            keyPoints: [],
            decisions: [],
            actionItems: [],
            openQuestions: []
        )

        let combined = MeetingMinutesAlgorithm.combiningWindows([blank, first, second, repeated])

        XCTAssertEqual(combined?.overview, "第一段概要\n\n第二段概要")
        XCTAssertEqual(combined?.points.map(\.id), ["P1", "P2"])
        XCTAssertEqual(combined?.points.map(\.title), ["发布范围", "回滚"])
        XCTAssertEqual(combined?.points.map { $0.evidence.map(\.quote) }, [["先做首版。"], ["下周三再看。"]])
        XCTAssertEqual(combined?.points.first?.evidence.first?.startMs, 0)
        XCTAssertEqual(combined?.actionItems.map(\.id), [todoID])
        XCTAssertEqual(combined?.actionItems.map(\.task), ["整理发布说明"])
        XCTAssertNil(MeetingMinutesAlgorithm.combiningWindows([]))
        XCTAssertNil(MeetingMinutesAlgorithm.combiningWindows([blank]))
    }

    @MainActor
    func testMergeQuotaStitchesWindowsAndALaterRunStillCallsTheModel() async throws {
        let firstSegment = MeetingTranscriptSegment(
            startTime: 0,
            endTime: 1,
            speakerID: "S1",
            text: String(repeating: "议", count: 4300)
        )
        let secondSegment = MeetingTranscriptSegment(
            startTime: 1,
            endTime: 2,
            speakerID: "S1",
            text: String(repeating: "题", count: 4300)
        )
        let record = meetingRecord(title: "余额不足", segments: [firstSegment, secondSegment])
        let firstOverview = paddedSummary("第一段确认了发布范围。")
        let secondOverview = paddedSummary("第二段确认了回滚步骤。")
        let firstWindow = try minutesJSON(
            summary: firstOverview,
            points: [point("P1", "发布范围", "确认了发布范围。", evidence(firstSegment, quote: "议"))],
            todos: [todo("T1", "整理发布说明", owner: nil, due: nil, evidence: evidence(firstSegment, quote: "议"))]
        )
        let secondWindow = try minutesJSON(
            summary: secondOverview,
            points: [point("P1", "回滚", "准备回滚。", evidence(secondSegment, quote: "题"))],
            todos: [todo("T1", "整理发布说明", owner: nil, due: nil, evidence: evidence(secondSegment, quote: "题"))]
        )
        let box = LockedCheckpointBox()
        let failingAPI = MeetingTestAPI(
            summaryResponse: firstWindow,
            responsesByPromptFragment: [
                "第 1/2 段": firstWindow,
                "第 2/2 段": secondWindow
            ],
            failMergeWithServerMessage: "Insufficient Balance (request_id: test)"
        )
        let stitched = try await MeetingSummaryService(api: failingAPI).summarize(
            record: record,
            configuration: testSummaryConfiguration,
            onCheckpoint: { box.set($0) }
        )

        XCTAssertEqual(stitched.overview, "\(firstOverview)\n\n\(secondOverview)")
        XCTAssertEqual(stitched.points.map(\.id), ["P1", "P2"])
        XCTAssertEqual(stitched.points.map(\.title), ["发布范围", "回滚"])
        XCTAssertEqual(stitched.points.map { $0.evidence.map(\.quote) }, [["议"], ["题"]])
        XCTAssertEqual(stitched.actionItems.map(\.task), ["整理发布说明"])
        let failingPrompts = await failingAPI.receivedUserPrompts
        XCTAssertTrue(failingPrompts.contains { $0.contains("第 1/2 段") })
        XCTAssertTrue(failingPrompts.contains { $0.contains("第 2/2 段") })
        XCTAssertEqual(failingPrompts.filter { $0.contains("请合并成一份") }.count, 1)

        let saved = try XCTUnwrap(
            box.checkpoints.last { $0.finishedSummary == nil && $0.windowSummaries?.count == 2 }
        )
        let mergedOverview = paddedSummary("模型把两段合并成一份纪要。")
        let retryAPI = try MeetingTestAPI(
            summaryResponse: minutesJSON(summary: mergedOverview)
        )
        let merged = try await MeetingSummaryService(api: retryAPI).summarize(
            record: record,
            configuration: testSummaryConfiguration,
            checkpoint: saved
        )

        XCTAssertEqual(merged.overview, mergedOverview)
        let retryPrompts = await retryAPI.receivedUserPrompts
        XCTAssertEqual(retryPrompts.count, 1)
        XCTAssertTrue(retryPrompts[0].contains("请合并成一份"))
        XCTAssertFalse(retryPrompts[0].contains("逐字稿每一行"))
        XCTAssertFalse(retryPrompts[0].contains("第 1/2 段"))
    }

    @MainActor
    func testSingleChunkInsufficientBalanceDoesNotInventMinutes() async {
        let record = meetingRecord(
            title: "短会额度",
            segments: [
                MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: "今天确认了发布范围。")
            ]
        )
        let api = MeetingTestAPI(
            summaryResponse: #"{"summary":"不应该被采用","points":[],"todos":[]}"#,
            failAllWithServerMessage: "Insufficient Balance (request_id: test)"
        )

        do {
            _ = try await MeetingSummaryService(api: api).summarize(
                record: record,
                configuration: testSummaryConfiguration
            )
            XCTFail("单段额度不足不应生成纪要")
        } catch let error as MeetingMinutesError {
            XCTAssertEqual(error, .quota)
            XCTAssertEqual(error.errorDescription, "AI 服务额度不足。逐字稿已保留，可以稍后重试。")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    @MainActor
    func testMergeNetworkOrSchemaFailureDoesNotStitchWindows() async throws {
        let record = meetingRecord(
            title: "合并失败",
            segments: [
                MeetingTranscriptSegment(startTime: 0, endTime: 1, speakerID: "S1", text: String(repeating: "议", count: 4300)),
                MeetingTranscriptSegment(startTime: 1, endTime: 2, speakerID: "S1", text: String(repeating: "题", count: 4300))
            ]
        )
        let window = try minutesJSON(summary: paddedSummary("这一段确认了发布范围。"))
        let networkAPI = MeetingTestAPI(
            summaryResponse: window,
            failMergeWithURLError: true
        )

        do {
            _ = try await MeetingSummaryService(api: networkAPI).summarize(
                record: record,
                configuration: testSummaryConfiguration
            )
            XCTFail("网络失败不应拼接分段纪要")
        } catch let error as MeetingMinutesError {
            XCTAssertEqual(error, .network)
        } catch {
            XCTFail("unexpected error \(error)")
        }

        let schemaAPI = MeetingTestAPI(
            summaryResponse: "不是 JSON",
            scriptedResponses: [window, window, "不是 JSON", "还是不是"]
        )
        do {
            _ = try await MeetingSummaryService(api: schemaAPI).summarize(
                record: record,
                configuration: testSummaryConfiguration
            )
            XCTFail("格式失败不应拼接分段纪要")
        } catch let error as MeetingMinutesError {
            XCTAssertEqual(error, .schemaRejected)
        } catch {
            XCTFail("unexpected error \(error)")
        }
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

    func testMeetingSearchMatchesSummaryAndActionItems() {
        let record = MeetingRecord(
            title: "产品评审",
            audioFileName: "meeting-\(UUID().uuidString).m4a",
            summary: MeetingSummary(
                overview: "本周交付首版",
                keyPoints: ["优先完成登录流程"],
                decisions: ["先支持 macOS"],
                actionItems: [MeetingActionItem(task: "整理接口清单")],
                openQuestions: ["是否支持离线模式"]
            )
        )

        XCTAssertTrue(record.matchesSearch("首版"))
        XCTAssertTrue(record.matchesSearch("接口清单"))
        XCTAssertTrue(record.matchesSearch("离线模式"))
    }

    func testLegacyMeetingSummaryAndActionItemDecodeNewFieldsWithDefaults() throws {
        let data = Data(
            #"{"overview":"已完成","keyPoints":[],"decisions":[],"actionItems":[{"id":"00000000-0000-0000-0000-000000000001","task":"发送纪要","owner":"","dueDate":""}],"openQuestions":[]}"#.utf8
        )

        let summary = try JSONDecoder().decode(MeetingSummary.self, from: data)

        XCTAssertNil(summary.citations)
        XCTAssertTrue(summary.points.isEmpty)
        XCTAssertEqual(try XCTUnwrap(summary.actionItems.first).ownerLabel, "未指定")
        XCTAssertEqual(try XCTUnwrap(summary.actionItems.first).dueLabel, "未提及")
        XCTAssertFalse(try XCTUnwrap(summary.actionItems.first).isCompleted)
    }

    func testLegacyMeetingRecordDecodesWithoutTheNewAudioFields() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","audioFileName":"meeting-\(id.uuidString).m4a","title":"旧会议"}
        """
        let record = try JSONDecoder().decode(MeetingRecord.self, from: Data(json.utf8))

        XCTAssertEqual(record.title, "旧会议")
        XCTAssertEqual(record.audioChunks, [])
        XCTAssertTrue(record.audioEvents.isEmpty)
        XCTAssertTrue(record.speakerTurns.isEmpty)
        XCTAssertTrue(record.segmentSpeakerOverrides.isEmpty)
        XCTAssertTrue(record.minutesVersions.isEmpty)
        XCTAssertNil(record.captureMode)
        XCTAssertNil(record.awaitingAssets)
        XCTAssertNil(record.diarizationDegraded)
        XCTAssertEqual(record.resolvedCaptureMode, .microphone)
        XCTAssertEqual(record.status, .failed)
        XCTAssertTrue(record.canRetryProcessing)

        let waiting = """
        {"id":"\(id.uuidString)","audioFileName":"meeting-\(id.uuidString).m4a","title":"占位","status":"failed","awaitingAssets":true}
        """
        let placeholder = try JSONDecoder().decode(MeetingRecord.self, from: Data(waiting.utf8))
        XCTAssertEqual(placeholder.awaitingAssets, true)
        XCTAssertFalse(placeholder.canRetryProcessing)
    }

    func testDiscoveredChunksKeepClosedSlicesAndMarkTheNewestOpen() {
        let id = UUID()
        let first = MeetingAudioChunkFile.microphoneName(meetingID: id, index: 0)
        let second = MeetingAudioChunkFile.microphoneName(meetingID: id, index: 1)
        let names = [first, second, "meeting-\(id.uuidString).mic.m4a", "notes.txt"]
        let discovered = MeetingAudioChunkFile.discoveredChunks(meetingID: id, fileNames: names)

        XCTAssertEqual(discovered.map(\.index), [0, 1])
        XCTAssertTrue(discovered[0].closed)
        XCTAssertFalse(discovered[1].closed)

        let stored = [
            MeetingAudioChunk(
                kind: .microphone,
                index: 1,
                fileName: second,
                startOffset: 30,
                duration: 30,
                closed: true
            )
        ]
        let merged = MeetingAudioChunkFile.mergedChunks(stored: stored, discovered: discovered)
        let latest = merged.first { $0.index == 1 }
        XCTAssertEqual(latest?.closed, true)
        XCTAssertEqual(latest?.duration, 30)
        XCTAssertEqual(latest?.startOffset, 30)
    }

    func testRecoverableChunksDropAnUnplayableOpenSlice() {
        let closed = MeetingAudioChunk(
            kind: .microphone,
            index: 0,
            fileName: "a.m4a",
            startOffset: 0,
            duration: 30,
            closed: true
        )
        let open = MeetingAudioChunk(
            kind: .microphone,
            index: 1,
            fileName: "b.m4a",
            startOffset: 30,
            duration: 4,
            closed: false
        )
        let dropped = MeetingAudioChunkFile.recoverableChunks([closed, open]) { _ in false }
        XCTAssertEqual(dropped, [closed])
        let kept = MeetingAudioChunkFile.recoverableChunks([closed, open]) { $0.index == 1 }
        XCTAssertEqual(kept, [closed, open])
    }

    func testRemergeKeepsAnOverrideAndDoesNotNumberTheUncertainSpeaker() {
        let keptID = UUID()
        let assignedID = UUID()
        let shortID = UUID()
        let segments = [
            MeetingTranscriptSegment(
                id: assignedID,
                startTime: 0,
                endTime: 2,
                speakerID: "old",
                text: "先说范围"
            ),
            MeetingTranscriptSegment(
                id: keptID,
                startTime: 3,
                endTime: 5,
                speakerID: "old",
                text: "这句保持原说话人"
            ),
            MeetingTranscriptSegment(
                id: shortID,
                startTime: 10,
                endTime: 10.2,
                speakerID: "old",
                text: "嗯"
            )
        ]
        let turns = [
            MeetingSpeakerTurnRecord(startTime: 0, endTime: 2.5, clusterID: "mic:0")
        ]
        let overrides = [
            MeetingSegmentSpeakerOverride(segmentID: keptID, speakerID: "kept")
        ]
        let speakers = [
            MeetingSpeaker(id: "mic:0", name: "说话人 1", colorIndex: 0),
            MeetingSpeaker(id: "kept", name: "主持人", colorIndex: 1)
        ]

        let merged = MeetingSpeakerRemerge.apply(
            segments: segments,
            turns: turns,
            overrides: overrides,
            speakers: speakers
        )

        XCTAssertEqual(merged.segments[0].speakerID, "mic:0")
        XCTAssertEqual(merged.segments[1].speakerID, "kept")
        XCTAssertEqual(merged.segments[2].speakerID, MeetingMinutesAlgorithm.uncertainSpeakerID)
        XCTAssertEqual(
            merged.speakers.first { $0.id == "kept" }?.name,
            "主持人"
        )
        XCTAssertEqual(
            merged.speakers.first { $0.id == MeetingMinutesAlgorithm.uncertainSpeakerID }?.name,
            MeetingMinutesAlgorithm.uncertainSpeakerName
        )
        XCTAssertFalse(
            merged.speakers.contains { $0.name == "说话人 3" }
        )
    }

    func testCanonicalAssemblyKeepsAFinishedTrackAndRebuildsTheMissingOne() {
        let bothReady = MeetingCanonicalAssembly.plan(microphoneReady: true, systemReady: true)
        XCTAssertFalse(bothReady.assembleMicrophone)
        XCTAssertFalse(bothReady.assembleSystem)

        let systemMissing = MeetingCanonicalAssembly.plan(microphoneReady: true, systemReady: false)
        XCTAssertFalse(systemMissing.assembleMicrophone)
        XCTAssertTrue(systemMissing.assembleSystem)

        let microphoneMissing = MeetingCanonicalAssembly.plan(microphoneReady: false, systemReady: true)
        XCTAssertTrue(microphoneMissing.assembleMicrophone)
        XCTAssertFalse(microphoneMissing.assembleSystem)
    }

    func testAssemblerConcatenatesClosedSlices() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-meeting-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("a.caf")
        let second = directory.appendingPathComponent("b.caf")
        let output = directory.appendingPathComponent("out.caf")
        try writeSilentCAF(to: first, seconds: 0.2)
        try writeSilentCAF(to: second, seconds: 0.2)

        let duration = try await MeetingAudioAssembler.concatenate(urls: [first, second], outputURL: output)

        XCTAssertGreaterThan(duration, 0.3)
        let playable = await MeetingAudioAssembler.playableDuration(at: output)
        XCTAssertGreaterThan(try XCTUnwrap(playable), 0.3)
    }

    func testMeetingSkillIsAvailableInNavigation() {
        XCTAssertTrue(SkillID.allCases.contains(.meetingNotes))
        XCTAssertEqual(SkillID.meetingNotes.navigationTitle, "会议记录")
    }
}

private func gateSamples(decibels: Float, count: Int) -> [Float] {
    let amplitude = pow(10, decibels / 20)
    return Array(repeating: amplitude, count: count)
}

private func writeSilentCAF(to url: URL, seconds: Double) throws {
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frames = AVAudioFrameCount(16000 * seconds)
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    try file.write(from: buffer)
}

private let testSummaryConfiguration = AIAPIConfiguration(
    endpoint: "https://example.com/v1/chat/completions",
    model: "test",
    apiKey: "test-key"
)

private actor MeetingTestAPI: AITextCompletionAPI {
    let summaryResponse: String
    var scriptedResponses: [String]
    var responsesByPromptFragment: [String: String]
    var failAllWithServerMessage: String?
    var failMergeWithServerMessage: String?
    var failMergeWithURLError = false
    private(set) var receivedConfiguration: AIAPIConfiguration?
    private(set) var receivedOptions: [AICompletionOptions] = []
    private(set) var receivedUserPrompts: [String] = []

    init(
        summaryResponse: String,
        scriptedResponses: [String] = [],
        responsesByPromptFragment: [String: String] = [:],
        failAllWithServerMessage: String? = nil,
        failMergeWithServerMessage: String? = nil,
        failMergeWithURLError: Bool = false
    ) {
        self.summaryResponse = summaryResponse
        self.scriptedResponses = scriptedResponses
        self.responsesByPromptFragment = responsesByPromptFragment
        self.failAllWithServerMessage = failAllWithServerMessage
        self.failMergeWithServerMessage = failMergeWithServerMessage
        self.failMergeWithURLError = failMergeWithURLError
    }

    func complete(
        systemPrompt _: String,
        userPrompt _: String,
        configuration: AIAPIConfiguration
    ) async throws -> String {
        try await complete(
            systemPrompt: "",
            userPrompt: "",
            configuration: configuration,
            options: .standardJSON
        )
    }

    func complete(
        systemPrompt _: String,
        userPrompt: String,
        configuration: AIAPIConfiguration,
        options: AICompletionOptions
    ) async throws -> String {
        receivedConfiguration = configuration
        receivedOptions.append(options)
        receivedUserPrompts.append(userPrompt)
        if let message = failAllWithServerMessage {
            throw AIAPIError.server(message)
        }
        if userPrompt.contains("请合并成一份") {
            if failMergeWithURLError {
                throw URLError(.cannotConnectToHost)
            }
            if let message = failMergeWithServerMessage {
                throw AIAPIError.server(message)
            }
        }
        if !scriptedResponses.isEmpty {
            return scriptedResponses.removeFirst()
        }
        for (fragment, response) in responsesByPromptFragment where userPrompt.contains(fragment) {
            return response
        }
        return summaryResponse
    }
}

private final class LockedCheckpointBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: MeetingSummaryCheckpoint?
    private var history: [MeetingSummaryCheckpoint] = []

    var value: MeetingSummaryCheckpoint? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    var checkpoints: [MeetingSummaryCheckpoint] {
        lock.lock()
        defer { lock.unlock() }
        return history
    }

    func set(_ checkpoint: MeetingSummaryCheckpoint) {
        lock.lock()
        stored = checkpoint
        history.append(checkpoint)
        lock.unlock()
    }
}

private func paddedSummary(_ text: String) -> String {
    var value = text
    while value.count < 220 {
        value += "会上确认了这一安排。"
    }
    if value.count > 400 {
        value = String(value.prefix(400))
    }
    return value
}

private func meetingRecord(
    title: String,
    segments: [MeetingTranscriptSegment],
    speakers: [MeetingSpeaker]? = nil
) -> MeetingRecord {
    MeetingRecord(
        title: title,
        audioFileName: "meeting-\(UUID().uuidString).m4a",
        speakers: speakers ?? [MeetingSpeaker(id: "S1", name: "说话人 1", colorIndex: 0)],
        transcript: segments
    )
}

private func evidence(_ segment: MeetingTranscriptSegment, quote: String) -> [String: Any] {
    [
        "segment_id": segment.id.uuidString,
        "start_ms": Int(segment.startTime * 1000),
        "end_ms": Int(segment.endTime * 1000),
        "quote": quote
    ]
}

private func point(
    _ id: String,
    _ title: String,
    _ detail: String,
    _ evidence: [String: Any]
) -> [String: Any] {
    ["id": id, "title": title, "detail": detail, "evidence": [evidence]]
}

private func todo(
    _ id: String,
    _ task: String,
    owner: String?,
    due: String?,
    evidence: [String: Any]
) -> [String: Any] {
    [
        "id": id,
        "task": task,
        "owner": owner.map { $0 as Any } ?? NSNull(),
        "due": due.map { $0 as Any } ?? NSNull(),
        "evidence": [evidence]
    ]
}

private func minutesJSON(
    summary: String,
    points: [[String: Any]] = [],
    todos: [[String: Any]] = []
) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: [
        "summary": summary,
        "points": points,
        "todos": todos
    ])
    return String(decoding: data, as: UTF8.self)
}

private let sampleGeneration = MeetingMinutesGeneration(
    modelName: "test",
    promptVersion: MeetingMinutesAlgorithm.promptVersion,
    generatedAt: Date(timeIntervalSince1970: 0),
    transcriptFingerprint: "test"
)
