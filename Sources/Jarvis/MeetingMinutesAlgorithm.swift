import Foundation

/// Validates model minutes against the transcript. Quotes must be exact substrings.
/// Items without a usable quote are dropped. Nothing here is specific to one meeting.
enum MeetingMinutesAlgorithm {
    static let promptVersion = "minutes-schema-1"
    static let uncertainSpeakerID = "uncertain"
    static let uncertainSpeakerName = "说话人不确定"
    static let ownerMissingLabel = "未指定"
    static let dueMissingLabel = "未提及"
    static let summaryCharacterRange = 200 ... 400

    struct SpeakerTurn: Equatable, Sendable {
        var speakerID: String
        var startTime: TimeInterval
        var endTime: TimeInterval
    }

    struct DraftEvidence: Decodable, Sendable {
        var segmentID: String
        var startMs: Int
        var endMs: Int
        var quote: String

        private enum CodingKeys: String, CodingKey {
            case segmentID
            case segmentIDSnake = "segment_id"
            case startMs
            case startMsSnake = "start_ms"
            case endMs
            case endMsSnake = "end_ms"
            case quote
        }

        init(segmentID: String, startMs: Int, endMs: Int, quote: String) {
            self.segmentID = segmentID
            self.startMs = startMs
            self.endMs = endMs
            self.quote = quote
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            segmentID = try container.decodeIfPresent(String.self, forKey: .segmentID)
                ?? container.decodeIfPresent(String.self, forKey: .segmentIDSnake)
                ?? ""
            startMs = try container.decodeIfPresent(Int.self, forKey: .startMs)
                ?? container.decodeIfPresent(Int.self, forKey: .startMsSnake)
                ?? 0
            endMs = try container.decodeIfPresent(Int.self, forKey: .endMs)
                ?? container.decodeIfPresent(Int.self, forKey: .endMsSnake)
                ?? 0
            quote = try container.decodeIfPresent(String.self, forKey: .quote) ?? ""
        }
    }

    struct DraftPoint: Decodable, Sendable {
        var id: String?
        var title: String?
        var detail: String?
        var evidence: [DraftEvidence]?

        init(id: String? = nil, title: String? = nil, detail: String? = nil, evidence: [DraftEvidence]? = nil) {
            self.id = id
            self.title = title
            self.detail = detail
            self.evidence = evidence
        }
    }

    struct DraftTodo: Decodable, Sendable {
        var id: String?
        var task: String?
        var owner: String?
        var due: String?
        var dueDate: String?
        var evidence: [DraftEvidence]?

        init(
            id: String? = nil,
            task: String? = nil,
            owner: String? = nil,
            due: String? = nil,
            dueDate: String? = nil,
            evidence: [DraftEvidence]? = nil
        ) {
            self.id = id
            self.task = task
            self.owner = owner
            self.due = due
            self.dueDate = dueDate
            self.evidence = evidence
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case task
            case owner
            case due
            case dueDate
            case evidence
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            task = try container.decodeIfPresent(String.self, forKey: .task)
            owner = try container.decodeIfPresent(String.self, forKey: .owner)
            due = try container.decodeIfPresent(String.self, forKey: .due)
            dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
            evidence = try container.decodeIfPresent([DraftEvidence].self, forKey: .evidence)
        }
    }

    struct DraftMinutes: Decodable, Sendable {
        var summary: String?
        var overview: String?
        var points: [DraftPoint]?
        var todos: [DraftTodo]?
        var actionItems: [DraftTodo]?

        init(
            summary: String? = nil,
            overview: String? = nil,
            points: [DraftPoint]? = nil,
            todos: [DraftTodo]? = nil,
            actionItems: [DraftTodo]? = nil
        ) {
            self.summary = summary
            self.overview = overview
            self.points = points
            self.todos = todos
            self.actionItems = actionItems
        }

        private enum CodingKeys: String, CodingKey {
            case summary
            case overview
            case points
            case todos
            case actionItems
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            summary = try container.decodeIfPresent(String.self, forKey: .summary)
            overview = try container.decodeIfPresent(String.self, forKey: .overview)
            points = try container.decodeIfPresent([DraftPoint].self, forKey: .points)
            todos = try container.decodeIfPresent([DraftTodo].self, forKey: .todos)
            actionItems = try container.decodeIfPresent([DraftTodo].self, forKey: .actionItems)
        }
    }

    struct ValidationLog: Equatable, Sendable {
        var droppedPointIDs: [String]
        var droppedTodoIDs: [String]
    }

    struct ValidationResult: Sendable {
        var summary: MeetingSummary
        var log: ValidationLog
        var summaryCharacterCount: Int
        /// True when the model returned points or todos and every one of them was dropped.
        var droppedAllCitedItems: Bool
        var summaryOutsidePreferredRange: Bool
    }

    static func validate(
        _ draft: DraftMinutes,
        transcript: [MeetingTranscriptSegment],
        speakers: [MeetingSpeaker],
        meetingDate: Date,
        generation: MeetingMinutesGeneration,
        calendar: Calendar = .current
    ) -> ValidationResult {
        let segmentsByID = Dictionary(uniqueKeysWithValues: transcript.map { ($0.id, $0) })
        let allowedOwnerText = ownerCorpus(transcript: transcript, speakers: speakers)
        var droppedPoints: [String] = []
        var droppedTodos: [String] = []
        var points: [MeetingDiscussionPoint] = []
        let draftPoints = draft.points ?? []
        for (index, draftPoint) in draftPoints.enumerated() {
            let identifier = trimmed(draftPoint.id) ?? "P\(index + 1)"
            let evidence = acceptedEvidence(draftPoint.evidence ?? [], segmentsByID: segmentsByID)
            let title = trimmed(draftPoint.title) ?? ""
            let detail = trimmed(draftPoint.detail) ?? ""
            guard !title.isEmpty || !detail.isEmpty, !evidence.isEmpty else {
                droppedPoints.append(identifier)
                continue
            }
            points.append(
                MeetingDiscussionPoint(
                    id: identifier,
                    title: title.isEmpty ? detail : title,
                    detail: title.isEmpty ? "" : detail,
                    evidence: evidence
                )
            )
        }

        var actionItems: [MeetingActionItem] = []
        let draftTodos = draft.todos ?? draft.actionItems ?? []
        for (index, draftTodo) in draftTodos.enumerated() {
            let identifier = trimmed(draftTodo.id) ?? "T\(index + 1)"
            let task = trimmed(draftTodo.task) ?? ""
            let evidence = acceptedEvidence(draftTodo.evidence ?? [], segmentsByID: segmentsByID)
            guard !task.isEmpty, !evidence.isEmpty else {
                droppedTodos.append(identifier)
                continue
            }
            let owner = acceptedOwner(
                draftTodo.owner,
                evidence: evidence,
                allowedText: allowedOwnerText,
                speakerNames: speakers.map(\.name)
            )
            let due = acceptedDueDate(draftTodo.due ?? draftTodo.dueDate, meetingDate: meetingDate, calendar: calendar)
            actionItems.append(
                MeetingActionItem(
                    task: task,
                    owner: owner.value,
                    dueDate: due.value,
                    evidence: evidence,
                    ownerMissing: owner.missing,
                    dueMissing: due.missing
                )
            )
        }

        let overview = trimmed(draft.summary) ?? trimmed(draft.overview) ?? ""
        let characterCount = overview.count
        let hadCitedDrafts = !draftPoints.isEmpty || !draftTodos.isEmpty
        let keptCitedItems = !points.isEmpty || !actionItems.isEmpty
        return ValidationResult(
            summary: MeetingSummary(
                overview: overview,
                keyPoints: [],
                decisions: [],
                actionItems: actionItems,
                openQuestions: [],
                points: points,
                generation: generation
            ),
            log: ValidationLog(droppedPointIDs: droppedPoints, droppedTodoIDs: droppedTodos),
            summaryCharacterCount: characterCount,
            droppedAllCitedItems: hadCitedDrafts && !keptCitedItems,
            summaryOutsidePreferredRange: !summaryCharacterRange.contains(characterCount)
        )
    }

    static func merging(
        _ generated: MeetingSummary,
        preserving previous: MeetingSummary?
    ) -> MeetingSummary {
        guard let previous else { return generated }
        var merged = generated
        if previous.overviewIsUserEdited {
            merged.overview = previous.overview
            merged.overviewIsUserEdited = true
        }

        for edited in previous.points where edited.isUserEdited {
            if let index = merged.points.firstIndex(where: { $0.id == edited.id || $0.title == edited.title }) {
                merged.points[index] = edited
            } else {
                merged.points.append(edited)
            }
        }

        for index in merged.actionItems.indices {
            let generatedItem = merged.actionItems[index]
            guard let previousItem = previous.actionItems.first(where: {
                $0.id == generatedItem.id || $0.task == generatedItem.task
            }) else { continue }
            if previousItem.isUserEdited {
                var kept = previousItem
                kept.isCompleted = previousItem.isCompleted
                merged.actionItems[index] = kept
            } else {
                merged.actionItems[index].isCompleted = previousItem.isCompleted
            }
        }

        for edited in previous.actionItems where edited.isUserEdited {
            let alreadyKept = merged.actionItems.contains { $0.id == edited.id || $0.task == edited.task }
            if !alreadyKept {
                merged.actionItems.append(edited)
            }
        }
        return merged
    }

    /// Joins window minutes that were already accepted when the merge call itself
    /// cannot run. Overviews stay in order, points are renumbered, and nothing is rewritten.
    static func combiningWindows(_ windows: [MeetingSummary]) -> MeetingSummary? {
        let usable = windows.filter { window in
            !window.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !window.points.isEmpty
                || !window.actionItems.isEmpty
        }
        guard !usable.isEmpty else { return nil }

        var overviews: [String] = []
        for window in usable {
            let overview = window.overview.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !overview.isEmpty, !overviews.contains(overview) else { continue }
            overviews.append(overview)
        }

        var points: [MeetingDiscussionPoint] = []
        var seenPoints = Set<String>()
        for window in usable {
            for point in window.points {
                let quotes = point.evidence.map(\.quote).joined(separator: "\u{1}")
                let key = "\(point.title)\u{1}\(point.detail)\u{1}\(quotes)"
                guard seenPoints.insert(key).inserted else { continue }
                var copy = point
                copy.id = "P\(points.count + 1)"
                points.append(copy)
            }
        }

        var actionItems: [MeetingActionItem] = []
        var seenTasks = Set<String>()
        for window in usable {
            for item in window.actionItems {
                let task = item.task.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !task.isEmpty, seenTasks.insert(task).inserted else { continue }
                actionItems.append(item)
            }
        }

        let overview = overviews.joined(separator: "\n\n")
        guard !overview.isEmpty || !points.isEmpty || !actionItems.isEmpty else { return nil }
        return MeetingSummary(
            overview: overview,
            keyPoints: [],
            decisions: [],
            actionItems: actionItems,
            openQuestions: [],
            points: points,
            generation: usable.compactMap(\.generation).last
        )
    }

    /// Best coverage below 0.5, a segment shorter than 0.8s, or a second speaker
    /// covering at least 0.3 becomes "说话人不确定". Coverage is the union of that
    /// speaker's turns, so several short turns add up and overlapping ones are not counted twice.
    static func assignedSpeakerID(
        startTime: TimeInterval,
        endTime: TimeInterval,
        turns: [SpeakerTurn]
    ) -> String {
        let duration = endTime - startTime
        guard duration >= 0.8 else { return uncertainSpeakerID }
        let ranked = coverageBySpeaker(startTime: startTime, endTime: endTime, turns: turns)
            .map { (id: $0.key, ratio: $0.value / duration) }
            .sorted { lhs, rhs in
                if lhs.ratio == rhs.ratio {
                    return lhs.id < rhs.id
                }
                return lhs.ratio > rhs.ratio
            }
        guard let best = ranked.first, best.ratio >= 0.5 else { return uncertainSpeakerID }
        if ranked.dropFirst().contains(where: { $0.ratio >= 0.3 }) {
            return uncertainSpeakerID
        }
        return best.id
    }

    /// Pause over 1.4s and length over 180 stay. A speaker change also starts a new utterance.
    static func shouldSplitUtterance(
        currentText: String,
        currentStart: TimeInterval,
        currentEnd: TimeInterval,
        nextStart: TimeInterval,
        nextEnd: TimeInterval,
        turns: [SpeakerTurn]
    ) -> Bool {
        guard !currentText.isEmpty else { return false }
        if nextStart - currentEnd > 1.4 || currentText.count > 180 {
            return true
        }
        let currentSpeaker = leadingSpeakerID(startTime: currentStart, endTime: currentEnd, turns: turns)
        let nextSpeaker = leadingSpeakerID(startTime: nextStart, endTime: nextEnd, turns: turns)
        return currentSpeaker != nextSpeaker
    }

    private static func leadingSpeakerID(
        startTime: TimeInterval,
        endTime: TimeInterval,
        turns: [SpeakerTurn]
    ) -> String? {
        let ranked = coverageBySpeaker(startTime: startTime, endTime: endTime, turns: turns)
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
        guard let best = ranked.first else { return nil }
        if ranked.dropFirst().contains(where: { $0.value == best.value }) {
            return nil
        }
        return best.key
    }

    private static func coverageBySpeaker(
        startTime: TimeInterval,
        endTime: TimeInterval,
        turns: [SpeakerTurn]
    ) -> [String: TimeInterval] {
        var ranges: [String: [(start: TimeInterval, end: TimeInterval)]] = [:]
        for turn in turns {
            let start = max(startTime, turn.startTime)
            let end = min(endTime, turn.endTime)
            guard end > start else { continue }
            ranges[turn.speakerID, default: []].append((start, end))
        }
        return ranges.mapValues { mergedDuration($0) }
    }

    private static func mergedDuration(_ ranges: [(start: TimeInterval, end: TimeInterval)]) -> TimeInterval {
        let sorted = ranges.sorted { $0.start < $1.start }
        guard var activeStart = sorted.first?.start, var activeEnd = sorted.first?.end else { return 0 }
        var total = 0.0
        for range in sorted.dropFirst() {
            if range.start <= activeEnd {
                activeEnd = max(activeEnd, range.end)
            } else {
                total += activeEnd - activeStart
                activeStart = range.start
                activeEnd = range.end
            }
        }
        total += activeEnd - activeStart
        return total
    }

    static func normalizedDueDate(_ value: String?) -> String {
        let text = trimmed(value) ?? ""
        guard !text.isEmpty, !isSpokenTimeFiller(text) else { return "" }
        return text
    }

    private struct AcceptedField {
        var value: String
        var missing: String?
    }

    private static func acceptedEvidence(
        _ drafts: [DraftEvidence],
        segmentsByID: [UUID: MeetingTranscriptSegment]
    ) -> [MeetingEvidence] {
        var accepted: [MeetingEvidence] = []
        var seen = Set<String>()
        for draft in drafts {
            guard let segmentID = UUID(uuidString: draft.segmentID),
                  let segment = segmentsByID[segmentID]
            else { continue }
            let quote = draft.quote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !quote.isEmpty, segment.text.contains(quote) else { continue }
            let key = "\(segmentID.uuidString)|\(quote)"
            guard seen.insert(key).inserted else { continue }
            let segmentStart = Int((segment.startTime * 1000).rounded())
            let segmentEnd = Int((segment.endTime * 1000).rounded())
            accepted.append(
                MeetingEvidence(
                    segmentID: segmentID,
                    startMs: segmentStart,
                    endMs: segmentEnd,
                    quote: quote
                )
            )
        }
        return accepted
    }

    private static func acceptedOwner(
        _ raw: String?,
        evidence: [MeetingEvidence],
        allowedText: String,
        speakerNames: [String]
    ) -> AcceptedField {
        let name = trimmed(raw) ?? ""
        if name.isEmpty || name == ownerMissingLabel || name == "null" || name == "无" || name == "未知" {
            return AcceptedField(value: "", missing: ownerMissingLabel)
        }
        if speakerNames.contains(where: { $0 == name }) || allowedText.contains(name) {
            return AcceptedField(value: name, missing: nil)
        }
        let quotes = evidence.map(\.quote).joined(separator: "\n")
        if quotes.contains(name) {
            return AcceptedField(value: name, missing: nil)
        }
        return AcceptedField(value: "", missing: ownerMissingLabel)
    }

    private static func acceptedDueDate(
        _ raw: String?,
        meetingDate: Date,
        calendar: Calendar
    ) -> AcceptedField {
        let text = trimmed(raw) ?? ""
        if text.isEmpty || text == dueMissingLabel || isSpokenTimeFiller(text) {
            return AcceptedField(value: "", missing: dueMissingLabel)
        }
        guard let absolute = absoluteDate(in: text, meetingDate: meetingDate, calendar: calendar) else {
            return AcceptedField(value: text, missing: nil)
        }
        let meetingDay = dayString(meetingDate, calendar: calendar)
        let absoluteDay = dayString(absolute, calendar: calendar)
        if text.contains(absoluteDay) {
            return AcceptedField(value: text, missing: nil)
        }
        return AcceptedField(
            value: "\(text)（由会议日期 \(meetingDay) 换算为 \(absoluteDay)）",
            missing: nil
        )
    }

    private static func absoluteDate(
        in text: String,
        meetingDate: Date,
        calendar: Calendar
    ) -> Date? {
        if text.contains("今天") {
            return calendar.startOfDay(for: meetingDate)
        }
        if text.contains("明天") {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: meetingDate))
        }
        if text.contains("后天") {
            return calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: meetingDate))
        }
        guard let weekday = weekday(in: text) else { return nil }
        let wantsNextWeek = text.contains("下周")
        let wantsThisWeek = text.contains("本周") || text.contains("这周")
        guard wantsNextWeek || wantsThisWeek else { return nil }
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        let start = weekCalendar.startOfDay(for: meetingDate)
        let weekdayOfMeeting = weekCalendar.component(.weekday, from: start)
        let daysFromMonday = (weekdayOfMeeting + 5) % 7
        guard let monday = weekCalendar.date(byAdding: .day, value: -daysFromMonday, to: start) else {
            return nil
        }
        let weekStart = wantsNextWeek
            ? weekCalendar.date(byAdding: .day, value: 7, to: monday) ?? monday
            : monday
        let offset = (weekday + 5) % 7
        return weekCalendar.date(byAdding: .day, value: offset, to: weekStart)
    }

    private static func weekday(in text: String) -> Int? {
        let names: [(String, Int)] = [
            ("周一", 2), ("周二", 3), ("周三", 4), ("周四", 5), ("周五", 6), ("周六", 7), ("周日", 1),
            ("星期一", 2), ("星期二", 3), ("星期三", 4), ("星期四", 5), ("星期五", 6), ("星期六", 7), ("星期日", 1),
            ("周天", 1), ("星期天", 1)
        ]
        for (name, weekday) in names where text.contains(name) {
            return weekday
        }
        return nil
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func ownerCorpus(
        transcript: [MeetingTranscriptSegment],
        speakers: [MeetingSpeaker]
    ) -> String {
        (transcript.map(\.text) + speakers.map(\.name)).joined(separator: "\n")
    }

    private static func isSpokenTimeFiller(_ text: String) -> Bool {
        let fillers = [
            "待会", "待会儿", "待一会儿", "待会完了", "等会", "等会儿", "等一下",
            "一会儿", "回头", "之后", "以后", "尽快", "马上", "随后", "晚点"
        ]
        return fillers.contains(text)
    }

    private static func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}
