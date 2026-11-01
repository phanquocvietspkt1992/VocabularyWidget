import Foundation
import CoreFoundation

enum LearningStorageError: LocalizedError {
    case invalidBackup
    case unreadableStorage
    case writeFailed
    case rollbackFailed(Data)
    case staleSession

    var errorDescription: String? {
        switch self {
        case .invalidBackup: return "The backup is incomplete, invalid, or uses an unsupported version."
        case .unreadableStorage: return "Saved data could not be read. Nothing was replaced."
        case .writeFailed: return "Could not save the change. Previous data was restored."
        case .rollbackFailed: return "Could not restore previous data. Keep the recovery backup before trying again."
        case .staleSession: return "This review has changed. Start a fresh review."
        }
    }
}

struct VocabularyBackup: Codable {
    let schemaVersion: Int
    let createdAt: Date
    let payload: Data

    func validatedSnapshot() throws -> [String: Any] {
        guard schemaVersion == 1, VocabularyLearningStore.validDate(createdAt),
              let snapshot = try PropertyListSerialization.propertyList(from: payload, options: [], format: nil) as? [String: Any] else {
            throw LearningStorageError.invalidBackup
        }
        try VocabularyLearningStore.validate(snapshot)
        return snapshot
    }
}

enum VocabularyLearningStore {
    static var defaults: UserDefaults {
        get throws {
            if let defaults = WidgetProgressStore.testDefaults { return defaults }
            guard let defaults = UserDefaults(suiteName: WidgetProgressStore.appGroupID) else {
                throw LearningStorageError.unreadableStorage
            }
            return defaults
        }
    }

    static func owns(_ key: String) -> Bool {
        ["selectedTopic", "customTopics.v1", "customVocabularyByTopic.v1", "studyHistory.v1", "schedule.v1", "review.v1"].contains(key)
            || ["progress.", "anchor.", "visited."].contains(where: key.hasPrefix)
    }

    static func rawSnapshot() throws -> [String: Any] {
        let snapshot = try defaults.dictionaryRepresentation().filter { owns($0.key) }
        do { try validate(snapshot) } catch { throw LearningStorageError.unreadableStorage }
        return snapshot
    }

    static func exportBackup(at date: Date = .now) throws -> Data {
        try encodeBackup(rawSnapshot(), at: date)
    }

    static func encodeBackup(_ snapshot: [String: Any], at date: Date = .now) throws -> Data {
        try validate(snapshot)
        guard validDate(date) else { throw LearningStorageError.invalidBackup }
        let payload = try PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0)
        return try JSONEncoder().encode(VocabularyBackup(schemaVersion: 1, createdAt: date, payload: payload))
    }

    static func decodeBackup(_ data: Data) throws -> VocabularyBackup {
        do {
            let backup = try JSONDecoder().decode(VocabularyBackup.self, from: data)
            _ = try backup.validatedSnapshot()
            return backup
        } catch { throw LearningStorageError.invalidBackup }
    }

    static func restore(_ backup: VocabularyBackup,
                        writer: ((String, Any?) throws -> Void)? = nil,
                        reader: (() throws -> [String: Any])? = nil) throws {
        let replacement = try backup.validatedSnapshot()
        let previous = try rawSnapshot()
        try replace(replacement, previous: previous, writer: writer, reader: reader)
    }

    static func replace(_ replacement: [String: Any], previous: [String: Any],
                        writer: ((String, Any?) throws -> Void)? = nil,
                        reader: (() throws -> [String: Any])? = nil) throws {
        try validate(replacement)
        let storage = try defaults
        let write = writer ?? { key, value in
            if let value { storage.set(value, forKey: key) } else { storage.removeObject(forKey: key) }
        }
        let read = reader ?? { storage.dictionaryRepresentation().filter { owns($0.key) } }
        let keys = Set(previous.keys).union(replacement.keys).sorted()
        let recovery = try encodeBackup(previous)
        do {
            for key in keys { try write(key, replacement[key]) }
            let saved = try read()
            try validate(saved)
            guard NSDictionary(dictionary: saved).isEqual(to: replacement) else { throw LearningStorageError.writeFailed }
        } catch {
            do {
                for key in keys { try write(key, previous[key]) }
                let saved = try read()
                try validate(saved)
                guard NSDictionary(dictionary: saved).isEqual(to: previous) else { throw LearningStorageError.writeFailed }
            } catch { throw LearningStorageError.rollbackFailed(recovery) }
            throw LearningStorageError.writeFailed
        }
    }

    static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && abs(date.timeIntervalSince1970) < 1e12
    }

    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    static func validate(_ snapshot: [String: Any]) throws {
        func require(_ condition: Bool) throws {
            if !condition { throw LearningStorageError.invalidBackup }
        }
        func decode<Value: Decodable>(_ key: String, as type: Value.Type) throws -> Value? {
            guard let stored = snapshot[key] else { return nil }
            guard let data = stored as? Data else { throw LearningStorageError.invalidBackup }
            return try JSONDecoder().decode(type, from: data)
        }
        try require(snapshot.keys.allSatisfy(owns))
        let topics = try decode("customTopics.v1", as: [CustomTopicStore.Topic].self) ?? []
        let customIDs = Set(topics.map(\.id))
        try require(customIDs.count == topics.count)
        try require(Set(topics.map { normalized($0.name) }).count == topics.count)
        for topic in topics {
            try require(topic.id.hasPrefix("custom_") && !normalized(String(topic.id.dropFirst(7))).isEmpty
                        && !VocabularyCatalog.builtInTopicIDs.contains(topic.id) && !normalized(topic.name).isEmpty)
        }
        func validReference(_ id: String) -> Bool {
            !id.isEmpty && (!id.hasPrefix("custom_") || customIDs.contains(id))
        }
        if let selected = snapshot["selectedTopic"] {
            try require((selected as? String).map(validReference) == true)
        }
        for (key, value) in snapshot {
            for prefix in ["progress.", "anchor.", "visited."] where key.hasPrefix(prefix) {
                try require(validReference(String(key.dropFirst(prefix.count))))
                if prefix == "anchor." {
                    try require((value as? Date).map(validDate) == true)
                } else {
                    guard let number = value as? NSNumber else { throw LearningStorageError.invalidBackup }
                    let isBoolean = CFGetTypeID(number) == CFBooleanGetTypeID()
                    if prefix == "visited." { try require(isBoolean) }
                    else {
                        try require(!isBoolean && ["q", "i", "s", "l", "Q", "I", "S", "L"].contains(String(cString: number.objCType))
                                    && number.int64Value >= 0 && number.uint64Value <= UInt64(Int.max))
                    }
                }
            }
        }
        let vocabulary = try decode("customVocabularyByTopic.v1", as: [String: [VocabularyWord]].self) ?? [:]
        for (id, words) in vocabulary {
            try require(validReference(id))
            try require(Set(words.map { normalized($0.text) }).count == words.count)
            for word in words {
                try require(!normalized(word.text).isEmpty && !normalized(word.meaning).isEmpty
                            && ["(n)", "(v)", "(adj)", "(adv)", "(prep)", "(conj)", "(pron)", "(interj)"].contains(word.partOfSpeech)
                            && word.examples.count == 5 && word.examples.allSatisfy { !normalized($0).isEmpty })
            }
        }
        if let schedule = try decode("schedule.v1", as: VocabularySchedule.self) { try require(schedule.isValid) }
        let history = try decode("studyHistory.v1", as: [StudyHistoryRecord].self) ?? []
        var identities = Set<[String]>()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        for record in history {
            let day = formatter.date(from: record.day)
            try require(validReference(record.topicID) && !normalized(record.wordID).isEmpty && validDate(record.studiedAt)
                        && day.map { formatter.string(from: $0) == record.day } == true
                        && identities.insert([record.topicID, record.wordID, record.day]).inserted)
        }
        if let review = try decode("review.v1", as: VocabularyReviewState.self) {
            try require(review.schemaVersion == 1)
            var recordIDs = Set<ReviewIdentity>()
            for record in review.records {
                try require(validReference(record.identity.topicID) && !normalized(record.identity.wordID).isEmpty
                            && (0...5).contains(record.stage) && validDate(record.dueAt) && validDate(record.reviewedAt)
                            && record.dueAt > record.reviewedAt && recordIDs.insert(record.identity).inserted)
            }
            var attemptIDs = Set<UUID>()
            for attempt in review.attempts {
                try require(validReference(attempt.identity.topicID) && !normalized(attempt.identity.wordID).isEmpty
                            && validDate(attempt.at) && attemptIDs.insert(attempt.id).inserted)
            }
        }
    }
}

struct ReviewIdentity: Codable, Hashable {
    let topicID: String
    let wordID: String
}

enum ReviewGrade: String, Codable { case remember, again }

struct VocabularyReviewRecord: Codable, Equatable {
    let identity: ReviewIdentity
    let stage: Int
    let dueAt: Date
    let reviewedAt: Date
}

struct VocabularyReviewAttempt: Codable, Equatable {
    let id: UUID
    let identity: ReviewIdentity
    let grade: ReviewGrade
    let at: Date
}

struct VocabularyReviewState: Codable, Equatable {
    var schemaVersion = 1
    var records: [VocabularyReviewRecord] = []
    var attempts: [VocabularyReviewAttempt] = []
}

enum VocabularyReviewStore {
    static func state(in snapshot: [String: Any]) throws -> VocabularyReviewState {
        guard let value = snapshot["review.v1"] else { return VocabularyReviewState() }
        guard let data = value as? Data else { throw LearningStorageError.unreadableStorage }
        return try JSONDecoder().decode(VocabularyReviewState.self, from: data)
    }

    @discardableResult
    static func save(_ state: VocabularyReviewState, snapshot: [String: Any],
                     writer: ((Data?) throws -> Void)? = nil,
                     reader: (() throws -> Data?)? = nil) throws -> Data {
        let data = try JSONEncoder().encode(state)
        var updated = snapshot
        updated["review.v1"] = data
        try VocabularyLearningStore.validate(updated)
        let storage = try VocabularyLearningStore.defaults
        let write = writer ?? { value in
            if let value { storage.set(value, forKey: "review.v1") } else { storage.removeObject(forKey: "review.v1") }
        }
        let read = reader ?? { storage.object(forKey: "review.v1") as? Data }
        let previous = snapshot["review.v1"] as? Data
        do {
            try write(data)
            guard try read() == data else { throw LearningStorageError.writeFailed }
        } catch {
            do {
                try write(previous)
                guard try read() == previous else { throw LearningStorageError.writeFailed }
            } catch { throw LearningStorageError.rollbackFailed(try VocabularyLearningStore.encodeBackup(snapshot)) }
            throw LearningStorageError.writeFailed
        }
        return data
    }
}

struct VocabularyReviewSession {
    private(set) var topicID = ""
    private(set) var topicName = "Daily Review"
    private(set) var queue: [VocabularyWord] = []
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var dueCount = 0
    private(set) var reviewedToday = 0
    private(set) var revealed = false
    private(set) var cardID = UUID()
    private var context: [String: Any] = [:]
    private var localDay: Date?
    private var timeZoneID = ""

    var currentWord: VocabularyWord? { queue.first }

    private static func context(in snapshot: [String: Any]) -> [String: Any] {
        snapshot.filter { ["selectedTopic", "customTopics.v1", "customVocabularyByTopic.v1", "review.v1"].contains($0.key) }
    }

    private static func selectedID(in snapshot: [String: Any]) -> String {
        snapshot["selectedTopic"] as? String ?? VocabularyCatalog.topics[0].id
    }

    mutating func start(at date: Date = .now, calendar: Calendar = .current) throws {
        self = VocabularyReviewSession()
        let snapshot = try VocabularyLearningStore.rawSnapshot()
        let state = try VocabularyReviewStore.state(in: snapshot)
        topicID = Self.selectedID(in: snapshot)
        context = Self.context(in: snapshot)
        localDay = calendar.startOfDay(for: date)
        timeZoneID = calendar.timeZone.identifier
        reviewedToday = Self.todayCount(state, topicID: topicID, at: date, calendar: calendar)
        guard let topic = VocabularyCatalog.topics.first(where: { $0.id == topicID }) else { return }
        topicName = topic.name
        let records = Dictionary(uniqueKeysWithValues: state.records.map { ($0.identity, $0) })
        var seen = Set<String>()
        let words = topic.words.filter { seen.insert($0.text).inserted }
        let due = words.enumerated().compactMap { offset, word -> (Int, VocabularyWord, Date)? in
            guard let record = records[ReviewIdentity(topicID: topicID, wordID: word.text)], record.dueAt <= date else { return nil }
            return (offset, word, record.dueAt)
        }.sorted { $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 < $1.2 }.map { $0.1 }
        let new = words.filter { records[ReviewIdentity(topicID: topicID, wordID: $0.text)] == nil }
        queue = Array((due + new).prefix(10))
        total = queue.count
        dueCount = due.count
    }

    private static func todayCount(_ state: VocabularyReviewState, topicID: String, at date: Date, calendar: Calendar) -> Int {
        let known = Set((VocabularyCatalog.topics.first(where: { $0.id == topicID })?.words ?? []).map {
            ReviewIdentity(topicID: topicID, wordID: $0.text)
        })
        return Set(state.attempts.filter {
            known.contains($0.identity) && calendar.isDate($0.at, inSameDayAs: date)
        }.map(\.identity)).count
    }

    mutating func refresh(at date: Date = .now, calendar: Calendar = .current) throws {
        do {
            let snapshot = try VocabularyLearningStore.rawSnapshot()
            let state = try VocabularyReviewStore.state(in: snapshot)
            let knownWords = Set(VocabularyCatalog.topics.first(where: { $0.id == topicID })?.words.map(\.text) ?? [])
            let nowDue = state.records.filter {
                $0.identity.topicID == topicID && knownWords.contains($0.identity.wordID) && $0.dueAt <= date
            }.count
            if localDay != calendar.startOfDay(for: date) || timeZoneID != calendar.timeZone.identifier
                || nowDue != dueCount
                || !NSDictionary(dictionary: context).isEqual(to: Self.context(in: snapshot)) {
                try start(at: date, calendar: calendar)
            }
        } catch {
            self = VocabularyReviewSession()
            throw error
        }
    }

    private func checkedSnapshot(at date: Date, calendar: Calendar) throws -> [String: Any] {
        let snapshot = try VocabularyLearningStore.rawSnapshot()
        guard localDay == calendar.startOfDay(for: date), timeZoneID == calendar.timeZone.identifier,
              Self.selectedID(in: snapshot) == topicID,
              NSDictionary(dictionary: context).isEqual(to: Self.context(in: snapshot)),
              let word = currentWord,
              VocabularyCatalog.topics.first(where: { $0.id == topicID })?.words.contains(word) == true else {
            throw LearningStorageError.staleSession
        }
        return snapshot
    }

    mutating func reveal(card id: UUID, at date: Date = .now, calendar: Calendar = .current) throws {
        guard id == cardID else { throw LearningStorageError.staleSession }
        _ = try checkedSnapshot(at: date, calendar: calendar)
        revealed = true
    }

    mutating func grade(_ grade: ReviewGrade, card id: UUID, at date: Date = .now, calendar: Calendar = .current,
                        writer: ((Data?) throws -> Void)? = nil, reader: (() throws -> Data?)? = nil) throws {
        guard revealed, id == cardID else { throw LearningStorageError.staleSession }
        let snapshot = try checkedSnapshot(at: date, calendar: calendar)
        guard let word = currentWord else { throw LearningStorageError.staleSession }
        var state = try VocabularyReviewStore.state(in: snapshot)
        let identity = ReviewIdentity(topicID: topicID, wordID: word.text)
        let previous = state.records.first { $0.identity == identity }
        let stage = grade == .again ? 0 : min((previous?.stage ?? 0) + 1, 5)
        let days = stage == 0 ? 1 : [1, 3, 7, 14, 30][stage - 1]
        guard let due = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)),
              VocabularyLearningStore.validDate(date), due > date else { throw LearningStorageError.invalidBackup }
        let record = VocabularyReviewRecord(identity: identity, stage: stage, dueAt: due, reviewedAt: date)
        if let index = state.records.firstIndex(where: { $0.identity == identity }) { state.records[index] = record }
        else { state.records.append(record) }
        state.attempts.append(VocabularyReviewAttempt(id: UUID(), identity: identity, grade: grade, at: date))
        let saved = try VocabularyReviewStore.save(state, snapshot: snapshot, writer: writer, reader: reader)
        context["review.v1"] = saved
        completed += 1
        queue.removeFirst()
        revealed = false
        cardID = UUID()
        dueCount = state.records.filter { record in
            record.identity.topicID == topicID && record.dueAt <= date
                && VocabularyCatalog.topics.first(where: { $0.id == topicID })?.words.contains(where: { $0.text == record.identity.wordID }) == true
        }.count
        reviewedToday = Self.todayCount(state, topicID: topicID, at: date, calendar: calendar)
    }
}