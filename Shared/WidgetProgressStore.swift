import Foundation

struct StudyHistoryRecord: Codable, Equatable {
    let topicID: String
    let wordID: String
    let day: String
    let studiedAt: Date
}

enum WidgetProgressStore {
    static let appGroupID = "group.com.phanquocviet.VocabularyWidget"
    static let interval: TimeInterval = 5 * 60
    private static let selectedKey = "selectedTopic"
    private static let studyHistoryKey = "studyHistory.v1"
    static var testDefaults: UserDefaults?

    private static var defaults: UserDefaults {
        if let testDefaults { return testDefaults }
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else {
            preconditionFailure("App Group \(appGroupID) is unavailable. Check the app and widget entitlements.")
        }
        return sharedDefaults
    }

    static var selectedTopicID: String {
        get { defaults.string(forKey: selectedKey) ?? VocabularyCatalog.topics[0].id }
        set { defaults.set(newValue, forKey: selectedKey) }
    }

    static func ensureSelectedTopicInitialized(at date: Date = .now) {
        let storedID = defaults.string(forKey: selectedKey)
        let validID = storedID.flatMap { id in
            VocabularyCatalog.containsTopic(id: id) ? id : nil
        } ?? VocabularyCatalog.topics[0].id
        defaults.set(validID, forKey: selectedKey)
        ensureAnchor(for: VocabularyCatalog.topic(for: selectedTopicID), at: date)
    }

    static func ensureAnchor(for topic: VocabularyTopic, at date: Date = .now) {
        let storedAnchor = defaults.object(forKey: anchorKey(topic.id)) as? Date
        if let storedAnchor, date >= storedAnchor { return }
        defaults.set(date, forKey: anchorKey(topic.id))
    }

    private static func indexKey(_ topicID: String) -> String { "progress.\(topicID)" }
    private static func anchorKey(_ topicID: String) -> String { "anchor.\(topicID)" }
    private static func visitedKey(_ topicID: String) -> String { "visited.\(topicID)" }

    static func hasVisited(_ topic: VocabularyTopic) -> Bool {
        defaults.bool(forKey: visitedKey(topic.id))
    }

    static func currentIndex(for topic: VocabularyTopic, at date: Date = .now) -> Int {
        guard !topic.words.isEmpty else { return 0 }
        let savedIndex = min(max(0, defaults.integer(forKey: indexKey(topic.id))), topic.words.count - 1)
        guard topic.id == selectedTopicID else {
            return savedIndex
        }
        guard let anchor = defaults.object(forKey: anchorKey(topic.id)) as? Date else {
            return min(savedIndex, topic.words.count - 1)
        }
        let elapsedIntervals = date.timeIntervalSince(anchor) / interval
        guard elapsedIntervals.isFinite else { return savedIndex }
        let elapsedSteps = elapsedIntervals > 0
            ? Int(floor(elapsedIntervals.truncatingRemainder(dividingBy: Double(topic.words.count))))
            : 0
        return (savedIndex + elapsedSteps) % topic.words.count
    }

    static func selectTopic(_ topic: VocabularyTopic, at date: Date = .now) {
        ensureSelectedTopicInitialized(at: date)
        let previous = VocabularyCatalog.topic(for: selectedTopicID)
        if previous.id == topic.id {
            if !hasVisited(topic) {
                defaults.set(0, forKey: indexKey(topic.id))
                defaults.set(date, forKey: anchorKey(topic.id))
            }
            defaults.set(true, forKey: visitedKey(topic.id))
            return
        }
        if defaults.object(forKey: anchorKey(previous.id)) != nil {
            defaults.set(currentIndex(for: previous, at: date), forKey: indexKey(previous.id))
            defaults.set(date, forKey: anchorKey(previous.id))
            defaults.set(true, forKey: visitedKey(previous.id))
        }

        selectedTopicID = topic.id
        defaults.set(true, forKey: visitedKey(topic.id))
        defaults.set(date, forKey: anchorKey(topic.id))
    }

    static func advanceSelectedTopic(at date: Date = .now) {
        ensureSelectedTopicInitialized(at: date)
        let topic = VocabularyCatalog.topic(for: selectedTopicID)
        guard !topic.words.isEmpty else { return }
        _ = advanceDisplayedWord(topicID: topic.id, displayedIndex: currentIndex(for: topic, at: date), at: date)
    }

    @discardableResult
    static func advanceDisplayedWord(topicID: String, displayedIndex: Int, at date: Date = .now) -> Bool {
        ensureSelectedTopicInitialized(at: date)
        guard selectedTopicID == topicID,
              let topic = VocabularyCatalog.topics.first(where: { $0.id == topicID }),
              !topic.words.isEmpty else { return false }
        let normalizedIndex = ((displayedIndex % topic.words.count) + topic.words.count) % topic.words.count
        let nextIndex = (normalizedIndex + 1) % topic.words.count
        defaults.set(nextIndex, forKey: indexKey(topic.id))
        defaults.set(date, forKey: anchorKey(topic.id))
        defaults.set(true, forKey: visitedKey(topic.id))
        return true
    }

    @discardableResult
    static func markStudiedAndAdvance(
        topicID: String,
        displayedIndex: Int,
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard selectedTopicID == topicID,
              let topic = VocabularyCatalog.topics.first(where: { $0.id == topicID }),
              !topic.words.isEmpty,
              topic.words.indices.contains(displayedIndex) else { return false }

        let nextIndex = (displayedIndex + 1) % topic.words.count
        let wordID = topic.words[displayedIndex].text
        let day = dayKey(for: date, calendar: calendar)
        var records: [StudyHistoryRecord] = []
        if let storedHistory = defaults.object(forKey: studyHistoryKey) {
            guard let data = storedHistory as? Data,
                  let decoded = try? JSONDecoder().decode([StudyHistoryRecord].self, from: data) else { return false }
            records = decoded
        }
        if !records.contains(where: { $0.topicID == topicID && $0.wordID == wordID && $0.day == day }) {
            records.append(StudyHistoryRecord(topicID: topicID, wordID: wordID, day: day, studiedAt: date))
            guard let data = try? JSONEncoder().encode(records) else { return false }
            defaults.set(data, forKey: studyHistoryKey)
        }

        defaults.set(nextIndex, forKey: indexKey(topic.id))
        defaults.set(date, forKey: anchorKey(topic.id))
        defaults.set(true, forKey: visitedKey(topic.id))
        return true
    }

    static func allStudyHistory() -> [StudyHistoryRecord] {
        guard let data = defaults.data(forKey: studyHistoryKey),
              let records = try? JSONDecoder().decode([StudyHistoryRecord].self, from: data) else { return [] }
        return records
    }

    static func studiedWordIDs(for topicID: String) -> Set<String> {
        Set(allStudyHistory().lazy.filter { $0.topicID == topicID }.map(\.wordID))
    }

    static func studiedWordCount(for topicID: String) -> Int {
        studiedWordIDs(for: topicID).count
    }

    static func studyHistory(forDay day: String) -> [StudyHistoryRecord] {
        allStudyHistory().filter { $0.day == day }
    }

    static func studyHistory(from startDate: Date, through endDate: Date) -> [StudyHistoryRecord] {
        guard startDate <= endDate else { return [] }
        return allStudyHistory().filter { startDate...endDate ~= $0.studiedAt }
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        var gregorianCalendar = Calendar(identifier: .gregorian)
        gregorianCalendar.timeZone = calendar.timeZone
        let components = gregorianCalendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return "" }
        return String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"), year, month, day)
    }

    static func resetProgress(for topic: VocabularyTopic, at date: Date = .now) {
        defaults.set(0, forKey: indexKey(topic.id))
        defaults.set(date, forKey: anchorKey(topic.id))
        defaults.set(true, forKey: visitedKey(topic.id))
    }

    static func nextChange(after date: Date = .now, for topic: VocabularyTopic) -> Date {
        ensureAnchor(for: topic, at: date)
        guard let anchor = defaults.object(forKey: anchorKey(topic.id)) as? Date else { return date.addingTimeInterval(interval) }
        let elapsedSeconds = max(0, date.timeIntervalSince(anchor))
        guard elapsedSeconds.isFinite else {
            defaults.set(date, forKey: anchorKey(topic.id))
            return date.addingTimeInterval(interval)
        }
        let remainder = elapsedSeconds.truncatingRemainder(dividingBy: interval)
        let delay = remainder == 0 ? interval : interval - remainder
        return date.addingTimeInterval(delay)
    }

    static func currentEntryDate(for topic: VocabularyTopic, at date: Date = .now) -> Date {
        nextChange(after: date, for: topic).addingTimeInterval(-interval)
    }

    static func secondsUntilNextChange(for topic: VocabularyTopic, at date: Date = .now) -> Int {
        let remaining = nextChange(after: date, for: topic).timeIntervalSince(date)
        guard remaining.isFinite else { return Int(interval) }
        return max(0, Int(ceil(remaining)))
    }
}

enum CustomTopicStore {
    struct Topic: Codable, Identifiable, Equatable {
        let id: String
        let name: String
    }

    enum CreateError: Error, Equatable {
        case emptyName, duplicateName, storageFailure
    }

    private static let storageKey = "customTopics.v1"
    private static var defaults: UserDefaults {
        if let testDefaults = WidgetProgressStore.testDefaults { return testDefaults }
        guard let sharedDefaults = UserDefaults(suiteName: WidgetProgressStore.appGroupID) else {
            preconditionFailure("App Group \(WidgetProgressStore.appGroupID) is unavailable.")
        }
        return sharedDefaults
    }

    static var topics: [Topic] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Topic].self, from: data) else { return [] }
        return decoded
    }

    @discardableResult
    static func create(name: String) throws -> Topic {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw CreateError.emptyName }
        let key = normalized(cleanName)
        let existingNames = VocabularyCatalog.topics.map(\.name) + topics.map(\.name)
        guard !existingNames.contains(where: { normalized($0) == key }) else { throw CreateError.duplicateName }
        let topic = Topic(id: "custom_\(UUID().uuidString)", name: cleanName)
        var updated = topics
        updated.append(topic)
        guard let data = try? JSONEncoder().encode(updated) else { throw CreateError.storageFailure }
        defaults.set(data, forKey: storageKey)
        return topic
    }

    private static func normalized(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}

enum CustomVocabularyStore {
    enum AddError: Error, Equatable {
        case invalidWord, invalidPartOfSpeech, invalidMeaning, invalidExamples, duplicate, storageFailure
    }

    struct BatchIssue: Equatable {
        let block: Int
        let message: String
    }

    struct BatchResult {
        let added: [VocabularyWord]
        let issues: [BatchIssue]
    }

    private static let storageKey = "customVocabularyByTopic.v1"
    private static var defaults: UserDefaults {
        if let testDefaults = WidgetProgressStore.testDefaults { return testDefaults }
        guard let sharedDefaults = UserDefaults(suiteName: WidgetProgressStore.appGroupID) else {
            preconditionFailure("App Group \(WidgetProgressStore.appGroupID) is unavailable.")
        }
        return sharedDefaults
    }

    static func words(for topicID: String) -> [VocabularyWord] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: [VocabularyWord]].self, from: data) else { return [] }
        return decoded[topicID] ?? []
    }

    @discardableResult
    static func add(text: String, partOfSpeech: String, meaning: String, examples: [String], to topicID: String) throws -> VocabularyWord {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMeaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExamples = examples.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        try validate(text: cleanText, partOfSpeech: partOfSpeech, meaning: cleanMeaning, examples: cleanExamples)

        var all = loadAll()
        let key = normalized(cleanText)
        let existing = VocabularyCatalog.baseWordTexts(for: topicID) + (all[topicID] ?? []).map(\.text)
        guard !existing.contains(where: { normalized($0) == key }) else { throw AddError.duplicate }
        let word = VocabularyWord(text: cleanText, partOfSpeech: partOfSpeech, meaning: cleanMeaning, examples: cleanExamples)
        all[topicID, default: []].append(word)
        guard let data = try? JSONEncoder().encode(all) else { throw AddError.storageFailure }
        defaults.set(data, forKey: storageKey)
        return word
    }

    static func addBatch(_ source: String, to topicID: String) throws -> BatchResult {
        let normalizedSource = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedSource.components(separatedBy: "\n")
        var blocks: [[String]] = []
        var current: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !current.isEmpty { blocks.append(current); current = [] }
            } else {
                current.append(trimmed)
            }
        }
        if !current.isEmpty { blocks.append(current) }

        var all = loadAll()
        var known = Set((VocabularyCatalog.baseWordTexts(for: topicID) + (all[topicID] ?? []).map(\.text)).map(normalized))
        var accepted: [VocabularyWord] = []
        var issues: [BatchIssue] = []
        for (offset, block) in blocks.enumerated() {
            let number = offset + 1
            guard block.count == 8 else {
                issues.append(.init(block: number, message: "cần đúng 8 dòng (từ, loại từ, nghĩa và 5 ví dụ)"))
                continue
            }
            let text = block[0]
            let partOfSpeech = block[1]
            let meaning = block[2]
            let examples = Array(block[3...7])
            do {
                try validate(text: text, partOfSpeech: partOfSpeech, meaning: meaning, examples: examples)
            } catch AddError.invalidWord { issues.append(.init(block: number, message: "thiếu từ")); continue }
            catch AddError.invalidPartOfSpeech { issues.append(.init(block: number, message: "loại từ không hợp lệ")); continue }
            catch AddError.invalidMeaning { issues.append(.init(block: number, message: "thiếu nghĩa")); continue }
            catch { issues.append(.init(block: number, message: "cần đủ 5 ví dụ")); continue }
            let key = normalized(text)
            guard known.insert(key).inserted else {
                issues.append(.init(block: number, message: "từ đã tồn tại trong chủ đề hoặc danh sách này"))
                continue
            }
            accepted.append(VocabularyWord(text: text, partOfSpeech: partOfSpeech, meaning: meaning, examples: examples))
        }

        guard !accepted.isEmpty else { return BatchResult(added: [], issues: issues) }
        all[topicID, default: []].append(contentsOf: accepted)
        guard let data = try? JSONEncoder().encode(all) else { throw AddError.storageFailure }
        defaults.set(data, forKey: storageKey)
        return BatchResult(added: accepted, issues: issues)
    }

    private static func validate(text: String, partOfSpeech: String, meaning: String, examples: [String]) throws {
        let allowedPartsOfSpeech = ["(n)", "(v)", "(adj)", "(adv)", "(prep)", "(conj)", "(pron)", "(interj)"]
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AddError.invalidWord }
        guard allowedPartsOfSpeech.contains(partOfSpeech) else { throw AddError.invalidPartOfSpeech }
        guard !meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AddError.invalidMeaning }
        guard examples.count == 5, examples.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw AddError.invalidExamples }
    }

    private static func loadAll() -> [String: [VocabularyWord]] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: [VocabularyWord]].self, from: data) else { return [:] }
        return decoded
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}

struct VocabularyTimelinePoint {
    let date: Date
    let index: Int
}

enum VocabularyTimelineSchedule {
    static let futureEntryCount = 287

    static func make(for topic: VocabularyTopic, at now: Date) -> [VocabularyTimelinePoint] {
        let currentIndex = WidgetProgressStore.currentIndex(for: topic, at: now)
        let currentEntryDate = WidgetProgressStore.currentEntryDate(for: topic, at: now)
        let nextChange = WidgetProgressStore.nextChange(after: now, for: topic)
        let wordCount = max(1, topic.words.count)
        var points = [VocabularyTimelinePoint(date: currentEntryDate, index: currentIndex)]

        for step in 0..<futureEntryCount {
            points.append(VocabularyTimelinePoint(
                date: nextChange.addingTimeInterval(Double(step) * WidgetProgressStore.interval),
                index: (currentIndex + step + 1) % wordCount
            ))
        }
        return points
    }
}
