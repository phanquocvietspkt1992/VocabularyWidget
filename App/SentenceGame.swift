import Foundation
import Combine

struct SentencePair: Codable, Equatable, Identifiable {
    var id = UUID()
    var english: String
    var vietnamese: String
}

struct SentenceTopic: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var pairs: [SentencePair]

    static func sample() -> SentenceTopic {
        SentenceTopic(name: "Sample Sentences", pairs: [
            SentencePair(english: "Please wait.", vietnamese: "Vui lòng đợi."),
            SentencePair(english: "The meeting starts.", vietnamese: "Cuộc họp bắt đầu."),
            SentencePair(english: "Please open the window.", vietnamese: "Vui lòng mở cửa sổ."),
            SentencePair(english: "We can fix this today.", vietnamese: "Chúng ta có thể sửa việc này hôm nay."),
            SentencePair(english: "Can you check the new report?", vietnamese: "Bạn có thể kiểm tra báo cáo mới không?"),
            SentencePair(english: "I will send you the notes tomorrow.", vietnamese: "Tôi sẽ gửi ghi chú cho bạn vào ngày mai."),
            SentencePair(english: "We go to the park after the meeting.", vietnamese: "Chúng ta đến công viên sau cuộc họp."),
            SentencePair(english: "Please tell the team when you are ready to test this change.",
                         vietnamese: "Vui lòng báo cho nhóm khi bạn sẵn sàng kiểm thử thay đổi này.")
        ])
    }

    func validated() throws -> SentenceTopic {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.pairs = pairs.map {
            SentencePair(id: $0.id, english: $0.english.trimmingCharacters(in: .whitespacesAndNewlines),
                         vietnamese: $0.vietnamese.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard !result.name.isEmpty, !result.pairs.isEmpty,
              result.pairs.allSatisfy({ !$0.english.isEmpty && !$0.vietnamese.isEmpty }),
              Set(result.pairs.map(\.id)).count == result.pairs.count else { throw SentenceGameError.invalidTopic }
        guard Set(result.pairs.map { Self.normalized($0.english) }).count == result.pairs.count,
              Set(result.pairs.map { Self.normalized($0.vietnamese) }).count == result.pairs.count else {
            throw SentenceGameError.duplicatePair
        }
        return result
    }

    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func parsePairs(_ text: String) throws -> [SentencePair] {
        let rows = text.components(separatedBy: .newlines).enumerated().compactMap { index, value -> (line: Int, text: String)? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (index + 1, trimmed)
        }
        let hasTabs = rows.contains { $0.text.contains("\t") }
        let pairs: [(pair: SentencePair, englishLine: Int, vietnameseLine: Int)]

        if hasTabs {
            var parsed: [(pair: SentencePair, englishLine: Int, vietnameseLine: Int)] = []
            for row in rows {
                let columns = row.text.components(separatedBy: "\t")
                guard columns.count == 2,
                      !columns[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !columns[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SentenceImportError.malformedLine(row.line)
                }
                parsed.append((SentencePair(english: columns[0], vietnamese: columns[1]), row.line, row.line))
            }
            pairs = parsed
        } else {
            guard rows.count.isMultiple(of: 2) else {
                throw SentenceImportError.incompletePair(rows.last?.line ?? 1)
            }
            pairs = stride(from: 0, to: rows.count, by: 2).map { index in
                (SentencePair(english: rows[index].text, vietnamese: rows[index + 1].text),
                 rows[index].line, rows[index + 1].line)
            }
        }

        var result: [SentencePair] = []
        var englishSources: [String: (vietnamese: String, line: Int)] = [:]
        var vietnameseSources: [String: (english: String, line: Int)] = [:]
        for item in pairs {
            let pair = SentencePair(
                english: item.pair.english.trimmingCharacters(in: .whitespacesAndNewlines),
                vietnamese: item.pair.vietnamese.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let english = normalized(pair.english)
            let vietnamese = normalized(pair.vietnamese)
            if let source = englishSources[english] {
                guard source.vietnamese == vietnamese else {
                    throw SentenceImportError.englishConflict(firstLine: source.line, secondLine: item.englishLine)
                }
                continue
            }
            if let source = vietnameseSources[vietnamese] {
                guard source.english == english else {
                    throw SentenceImportError.vietnameseConflict(firstLine: source.line, secondLine: item.vietnameseLine)
                }
                continue
            }
            englishSources[english] = (vietnamese, item.englishLine)
            vietnameseSources[vietnamese] = (english, item.vietnameseLine)
            result.append(pair)
        }
        return result
    }
}

enum SentenceGameError: LocalizedError, Equatable {
    case invalidTopic, duplicatePair, duplicateTopic, invalidPaste, unreadable, writeFailed, recoveryFailed
    case historyUnreadable, historyWriteFailed, historyRecoveryFailed, stale, tooSmall
    case sessionUnreadable, sessionMissing, sessionWriteFailed, sessionRecoveryFailed, builderRequiresTiles
    case builderSessionUnreadable, builderSessionWriteFailed, builderSessionRecoveryFailed

    var errorDescription: String? {
        switch self {
        case .invalidTopic: return "Enter a topic name and a nonempty English and Vietnamese sentence for every pair."
        case .duplicatePair: return "English and Vietnamese sentences must each be unique within the topic (ignoring case and whitespace)."
        case .duplicateTopic: return "Topic names must be unique."
        case .invalidPaste: return "Each nonempty row must contain English, one tab, then Vietnamese."
        case .unreadable: return "Sentence data cannot be read. It has not been replaced."
        case .writeFailed: return "The change could not be saved. Previous sentence data was restored."
        case .recoveryFailed: return "Saving and recovery failed. Editing is locked. Export recovery data when available."
        case .historyUnreadable: return "Answer history cannot be read. It has not been replaced."
        case .historyWriteFailed: return "The answer was scored, but its history could not be saved. Previous history was restored."
        case .historyRecoveryFailed: return "The answer was scored, but saving and restoring history failed. History editing is locked."
        case .stale: return "Saved topics changed. Reopen the editor before saving again."
        case .tooSmall: return "At least four distinct sentence pairs are needed to play."
        case .sessionUnreadable: return "Saved sentence rounds cannot be read. They have not been replaced."
        case .sessionMissing: return "There is no saved round for this topic and mode."
        case .sessionWriteFailed: return "The round could not be saved. Previous saved rounds were restored."
        case .sessionRecoveryFailed: return "Saving and recovery failed. Saved round editing is locked."
        case .builderRequiresTiles: return "Word Order uses word tiles and cannot use a Stage or Quick round."
        case .builderSessionUnreadable: return "Saved Word Order rounds cannot be read. They have not been replaced."
        case .builderSessionWriteFailed: return "The Word Order round could not be saved. Previous Word Order data was restored."
        case .builderSessionRecoveryFailed: return "Saving and recovery failed. Word Order round editing is locked."
        }
    }
}

enum SentenceImportError: LocalizedError, Equatable {
    case malformedLine(Int)
    case incompletePair(Int)
    case englishConflict(firstLine: Int, secondLine: Int)
    case vietnameseConflict(firstLine: Int, secondLine: Int)

    var errorDescription: String? {
        switch self {
        case .malformedLine(let line):
            return "Line \(line) is not a valid English/Vietnamese pair. Use two lines per pair or one tab-separated row."
        case .incompletePair(let line):
            return "Line \(line) has no Vietnamese meaning below it. Add the missing line and try again."
        case .englishConflict(let firstLine, let secondLine):
            return "English sentence conflict on lines \(firstLine) and \(secondLine). The same English sentence has different Vietnamese meanings."
        case .vietnameseConflict(let firstLine, let secondLine):
            return "Vietnamese meaning conflict on lines \(firstLine) and \(secondLine). The same meaning is paired with different English sentences."
        }
    }
}

final class SentenceRepository {
    static let key = "sentenceTopics.v1"
    private struct Archive: Codable { let version: Int; let topics: [SentenceTopic] }
    private let defaults: UserDefaults
    private let writer: ((Any?) throws -> Void)?
    private let reader: (() -> Any?)?
    private(set) var recoveryBytes: Data?
    private(set) var isLocked = false

    init(defaults: UserDefaults = .standard, writer: ((Any?) throws -> Void)? = nil, reader: (() -> Any?)? = nil) {
        self.defaults = defaults
        self.writer = writer
        self.reader = reader
    }

    private func raw() -> Any? { reader.map { $0() } ?? defaults.object(forKey: Self.key) }

    func load() throws -> [SentenceTopic] {
        guard let value = raw() else { return [] }
        guard let bytes = value as? Data else { throw SentenceGameError.unreadable }
        do {
            let archive = try JSONDecoder().decode(Archive.self, from: bytes)
            guard archive.version == 1 else { throw SentenceGameError.unreadable }
            let valid = try Self.validate(archive.topics)
            guard valid == archive.topics else { throw SentenceGameError.unreadable }
            return valid
        } catch { throw SentenceGameError.unreadable }
    }

    private static func validate(_ topics: [SentenceTopic]) throws -> [SentenceTopic] {
        let valid = try topics.map { try $0.validated() }
        guard Set(valid.map(\.id)).count == valid.count,
              Set(valid.map { SentenceTopic.normalized($0.name) }).count == valid.count else {
            throw SentenceGameError.duplicateTopic
        }
        return valid
    }

    @discardableResult
    func save(_ topics: [SentenceTopic], expected: [SentenceTopic]) throws -> [SentenceTopic] {
        guard !isLocked else { throw SentenceGameError.recoveryFailed }
        let previous = try load()
        guard previous == expected else { throw SentenceGameError.stale }
        let oldBytes = raw() as? Data
        let replacement = try Self.validate(topics)
        let bytes = try JSONEncoder().encode(Archive(version: 1, topics: replacement))
        let write = writer ?? { value in
            if let value { self.defaults.set(value, forKey: Self.key) }
            else { self.defaults.removeObject(forKey: Self.key) }
        }
        do {
            try write(bytes)
            guard raw() as? Data == bytes, try load() == replacement else { throw SentenceGameError.writeFailed }
        } catch {
            do {
                try write(oldBytes)
                guard raw() as? Data == oldBytes, try load() == previous else { throw SentenceGameError.writeFailed }
            } catch {
                recoveryBytes = oldBytes
                isLocked = true
                throw SentenceGameError.recoveryFailed
            }
            throw SentenceGameError.writeFailed
        }
        return try load()
    }
}

enum SentenceMode: String, Codable, CaseIterable, Identifiable {
    case stage = "Stage", quick = "Quick", builder = "Sentence Builder"
    var id: String { rawValue }
    var displayName: String { self == .builder ? "Word Order" : rawValue }
}

struct SentenceHistoryOption: Codable, Equatable {
    let letter: String
    let id: UUID
    let english: String
}

struct SentenceRoundHistoryRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let roundID: UUID
    let topicID: UUID
    let topicName: String
    let mode: SentenceMode
    let answeredAt: Date
    let questionVietnamese: String
    let correctEnglish: String
    let options: [SentenceHistoryOption]
    let selectedLetter: String
    let selectedID: UUID
    let selectedEnglish: String
    let isCorrect: Bool
    let questionIndex: Int

    init(roundID: UUID, topic: SentenceTopic, mode: SentenceMode, answeredAt: Date,
         question: SentenceQuestion, selectedID: UUID, questionIndex: Int) {
        let selected = question.options.first { $0.id == selectedID }!
        id = UUID()
        self.roundID = roundID
        topicID = topic.id
        topicName = topic.name
        self.mode = mode
        self.answeredAt = answeredAt
        questionVietnamese = question.pair.vietnamese
        correctEnglish = question.pair.english
        options = zip(["A", "B", "C", "D"], question.options).map {
            SentenceHistoryOption(letter: $0.0, id: $0.1.id, english: $0.1.english)
        }
        selectedLetter = ["A", "B", "C", "D"][question.options.firstIndex { $0.id == selectedID }!]
        self.selectedID = selectedID
        selectedEnglish = selected.english
        isCorrect = selectedID == question.pair.id
        self.questionIndex = questionIndex
    }
}

final class SentenceRoundHistoryRepository {
    static let key = "sentenceRoundHistory.v1"
    private struct Archive: Codable { let version: Int; let records: [SentenceRoundHistoryRecord] }
    private let defaults: UserDefaults
    private let writer: (Any?) throws -> Void
    private let reader: () -> Any?
    private(set) var recoveryBytes: Data?
    private(set) var isLocked = false

    init(defaults: UserDefaults = .standard, writer: ((Any?) throws -> Void)? = nil, reader: (() -> Any?)? = nil) {
        self.defaults = defaults
        self.writer = writer ?? { value in
            if let value { defaults.set(value, forKey: Self.key) }
            else { defaults.removeObject(forKey: Self.key) }
        }
        self.reader = reader ?? { defaults.object(forKey: Self.key) }
    }

    private func raw() -> Any? { reader() }

    func load() throws -> [SentenceRoundHistoryRecord] {
        guard let value = raw() else { return [] }
        guard let bytes = value as? Data else { throw SentenceGameError.historyUnreadable }
        do {
            let archive = try JSONDecoder().decode(Archive.self, from: bytes)
            guard archive.version == 1 else { throw SentenceGameError.historyUnreadable }
            return archive.records
        } catch { throw SentenceGameError.historyUnreadable }
    }

    @discardableResult
    func append(_ record: SentenceRoundHistoryRecord) throws -> [SentenceRoundHistoryRecord] {
        guard !isLocked else { throw SentenceGameError.historyRecoveryFailed }
        let previous = try load()
        let oldBytes = raw() as? Data
        let replacement = previous + [record]
        let bytes = try JSONEncoder().encode(Archive(version: 1, records: replacement))
        do {
            try writer(bytes)
            guard raw() as? Data == bytes, try load() == replacement else { throw SentenceGameError.historyWriteFailed }
        } catch {
            do {
                try writer(oldBytes)
                guard raw() as? Data == oldBytes, try load() == previous else { throw SentenceGameError.historyWriteFailed }
            } catch {
                recoveryBytes = oldBytes
                isLocked = true
                throw SentenceGameError.historyRecoveryFailed
            }
            throw SentenceGameError.historyWriteFailed
        }
        return try load()
    }

    func appendOnce(_ record: SentenceRoundHistoryRecord) throws -> [SentenceRoundHistoryRecord] {
        let previous = try load()
        if let existing = previous.first(where: { $0.roundID == record.roundID && $0.questionIndex == record.questionIndex }) {
            guard existing.topicID == record.topicID, existing.topicName == record.topicName,
                existing.mode == record.mode,
                  existing.questionVietnamese == record.questionVietnamese,
                  existing.correctEnglish == record.correctEnglish, existing.options == record.options,
                  existing.selectedID == record.selectedID, existing.selectedEnglish == record.selectedEnglish,
                  existing.isCorrect == record.isCorrect else { throw SentenceGameError.historyWriteFailed }
            return previous
        }
        return try append(record)
    }
}

@MainActor
final class SentenceRoundHistoryModel: ObservableObject {
    @Published private(set) var records: [SentenceRoundHistoryRecord] = []
    @Published private(set) var error: String?
    private let repository: SentenceRoundHistoryRepository
    private var pending: [String: SentenceRoundHistoryRecord] = [:]

    init(repository: SentenceRoundHistoryRepository = SentenceRoundHistoryRepository()) {
        self.repository = repository
        reload()
    }

    var newestFirst: [SentenceRoundHistoryRecord] {
        records.sorted { $0.answeredAt > $1.answeredAt }
    }

    func reload() {
        do { records = try repository.load(); error = nil }
        catch let failure { error = failure.localizedDescription }
    }

    func append(_ answer: SentenceAnswer, roundID: UUID, topic: SentenceTopic,
                mode: SentenceMode, questionIndex: Int, answeredAt: Date = Date()) {
        let record = SentenceRoundHistoryRecord(roundID: roundID, topic: topic, mode: mode,
                                                answeredAt: answeredAt, question: answer.question,
                                                selectedID: answer.selectedID, questionIndex: questionIndex)
        do { records = try repository.append(record); error = nil }
        catch let failure { error = failure.localizedDescription }
    }

    func recordCommitted(_ answer: SentenceAnswer, roundID: UUID, topic: SentenceTopic,
                         mode: SentenceMode, questionIndex: Int, answeredAt: Date = Date()) {
        let key = "\(roundID.uuidString).\(questionIndex)"
        let record = pending[key] ?? SentenceRoundHistoryRecord(
            roundID: roundID, topic: topic, mode: mode, answeredAt: answeredAt,
            question: answer.question, selectedID: answer.selectedID, questionIndex: questionIndex
        )
        pending[key] = record
        do {
            records = try repository.appendOnce(record)
            pending.removeValue(forKey: key)
            if pending.isEmpty { error = nil }
        } catch let failure { error = failure.localizedDescription }
    }

    func retryPending() {
        for (key, record) in pending.sorted(by: { $0.value.answeredAt < $1.value.answeredAt }) {
            do {
                records = try repository.appendOnce(record)
                pending.removeValue(forKey: key)
                error = nil
            } catch let failure {
                error = failure.localizedDescription
                return
            }
        }
    }

    func reconcile(_ round: SentenceRound) {
        for (questionIndex, answer) in round.answers.enumerated() {
            recordCommitted(answer, roundID: round.id, topic: round.topic,
                            mode: round.mode, questionIndex: questionIndex)
        }
    }
}

@MainActor
final class SentenceRevealController: ObservableObject {
    @Published private(set) var isRevealing = false
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func begin(delay: UInt64 = 1_200_000_000, reveal: @escaping @MainActor () -> Void) {
        guard !isRevealing else { return }
        isRevealing = true
        let token = UUID()
        generation = token
        task = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.isRevealing = false
            self.task = nil
            reveal()
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        isRevealing = false
    }

    deinit { task?.cancel() }
}

@MainActor
final class SentenceLibraryModel: ObservableObject {
    @Published private(set) var topics: [SentenceTopic] = []
    @Published private(set) var error: String?
    private let repository: SentenceRepository
    var recoveryBytes: Data? { repository.recoveryBytes }
    var canEdit: Bool { !repository.isLocked && error == nil }

    init(repository: SentenceRepository = SentenceRepository()) {
        self.repository = repository
        reload()
    }

    func reload() {
        do { topics = try repository.load(); error = nil }
        catch { self.error = error.localizedDescription }
        if repository.isLocked { error = SentenceGameError.recoveryFailed.localizedDescription }
    }

    func upsert(_ topic: SentenceTopic, expected: [SentenceTopic]) throws {
        var replacement = expected
        if let index = replacement.firstIndex(where: { $0.id == topic.id }) { replacement[index] = topic }
        else { replacement.append(topic) }
        do { topics = try repository.save(replacement, expected: expected); error = nil }
        catch {
            reload()
            throw error
        }
    }

    func delete(_ id: UUID, expected: [SentenceTopic]) throws {
        do { topics = try repository.save(expected.filter { $0.id != id }, expected: expected); error = nil }
        catch { reload(); throw error }
    }
}

struct SentenceQuestion: Identifiable {
    let pair: SentencePair
    let options: [SentencePair]
    var id: UUID { pair.id }
}

struct SentenceAnswer: Codable, Equatable {
    let question: SentenceQuestion
    let selectedID: UUID
    var correct: Bool { selectedID == question.pair.id }
}

struct SentenceRound {
    let id: UUID
    let topic: SentenceTopic
    let mode: SentenceMode
    let questions: [SentenceQuestion]
    private(set) var answers: [SentenceAnswer] = []
    private(set) var selectedID: UUID?
    private(set) var index = 0

    init<Generator: RandomNumberGenerator>(topic: SentenceTopic, mode: SentenceMode,
                                          retryIDs: Set<UUID>? = nil, using generator: inout Generator) throws {
        id = UUID()
        self.topic = try topic.validated()
        self.mode = mode
        guard mode != .builder else { throw SentenceGameError.builderRequiresTiles }
        guard self.topic.pairs.count >= 4 else { throw SentenceGameError.tooSmall }
        let source = self.topic.pairs
        let eligible = source.filter { retryIDs?.contains($0.id) ?? true }.shuffled(using: &generator)
        let chosen = mode == .quick ? Array(eligible.prefix(5)) : eligible
        guard !chosen.isEmpty else { throw SentenceGameError.tooSmall }
        questions = chosen.map { pair in
            let distractors = source.filter { $0.id != pair.id }.shuffled(using: &generator).prefix(3)
            return SentenceQuestion(pair: pair, options: (Array(distractors) + [pair]).shuffled(using: &generator))
        }
    }

    init(topic: SentenceTopic, mode: SentenceMode, retryIDs: Set<UUID>? = nil) throws {
        var generator = SystemRandomNumberGenerator()
        try self.init(topic: topic, mode: mode, retryIDs: retryIDs, using: &generator)
    }

    var finished: Bool { index == questions.count }
    var current: SentenceQuestion? { finished ? nil : questions[index] }
    var revealed: Bool { answers.count > index }
    var score: Int { answers.filter(\.correct).count }
    var incorrectIDs: Set<UUID> { Set(answers.filter { !$0.correct }.map { $0.question.id }) }

    @discardableResult
    mutating func select(_ id: UUID) -> SentenceAnswer? {
        guard let current, !revealed, current.options.contains(where: { $0.id == id }) else { return nil }
        selectedID = id
        if mode == .quick { return commitAnswer() }
        return nil
    }

    @discardableResult
    mutating func confirm() -> SentenceAnswer? {
        guard current != nil, selectedID != nil, !revealed else { return nil }
        return commitAnswer()
    }

    private mutating func commitAnswer() -> SentenceAnswer? {
        guard let current, let selectedID, !revealed else { return nil }
        let answer = SentenceAnswer(question: current, selectedID: selectedID)
        answers.append(answer)
        return answer
    }

    mutating func advance() {
        guard revealed else { return }
        index += 1
        selectedID = nil
    }

    fileprivate init(snapshot: SentenceRoundSnapshot) throws {
        try snapshot.validate()
        id = snapshot.roundID
        topic = snapshot.topic
        mode = snapshot.mode
        questions = snapshot.questions
        answers = snapshot.answers
        selectedID = snapshot.selectedID
        index = snapshot.index
    }
}

struct SentenceRoundSnapshot: Codable, Equatable {
    let roundID: UUID
    let topic: SentenceTopic
    let mode: SentenceMode
    let questions: [SentenceQuestion]
    let answers: [SentenceAnswer]
    let selectedID: UUID?
    let index: Int

    init(round: SentenceRound) {
        roundID = round.id
        topic = round.topic
        mode = round.mode
        questions = round.questions
        answers = round.answers
        selectedID = round.selectedID
        index = round.index
    }

    var finished: Bool { index == questions.count }
    var score: Int { answers.filter(\.correct).count }

    func restore() throws -> SentenceRound { try SentenceRound(snapshot: self) }

    fileprivate func validate() throws {
        guard try topic.validated() == topic,
              !questions.isEmpty, questions.count <= topic.pairs.count,
              index >= 0, index <= questions.count,
              answers.count == index || (index < questions.count && answers.count == index + 1),
              Set(questions.map(\.id)).count == questions.count else {
            throw SentenceGameError.sessionUnreadable
        }
        let pairs = Dictionary(uniqueKeysWithValues: topic.pairs.map { ($0.id, $0) })
        for question in questions {
            guard pairs[question.id] == question.pair,
                  question.options.count == 4,
                  Set(question.options.map(\.id)).count == 4,
                  question.options.allSatisfy({ pairs[$0.id] == $0 }),
                  question.options.filter({ $0.id == question.id }).count == 1 else {
                throw SentenceGameError.sessionUnreadable
            }
        }
        for (answerIndex, answer) in answers.enumerated() {
            guard answerIndex < questions.count,
                  answer.question == questions[answerIndex],
                  answer.question.options.contains(where: { $0.id == answer.selectedID }) else {
                throw SentenceGameError.sessionUnreadable
            }
        }
        if answers.count > index {
            guard selectedID == answers[index].selectedID else { throw SentenceGameError.sessionUnreadable }
        }
        if let selectedID {
            guard index < questions.count,
                  questions[index].options.contains(where: { $0.id == selectedID }),
                  mode == .stage || answers.count > index else {
                throw SentenceGameError.sessionUnreadable
            }
        }
    }
}

extension SentenceQuestion: Codable, Equatable {}

struct SentenceSavedRound: Codable, Equatable, Identifiable {
    let round: SentenceRoundSnapshot
    let savedAt: Date
    var id: String { Self.slot(topicID: round.topic.id, mode: round.mode) }
    var topicID: UUID { round.topic.id }
    var mode: SentenceMode { round.mode }

    static func slot(topicID: UUID, mode: SentenceMode) -> String { "\(topicID.uuidString).\(mode.rawValue)" }
}

final class SentenceRoundSessionRepository {
    static let key = "sentenceGameSessions.v1"
    private struct Archive: Codable { let version: Int; let sessions: [SentenceSavedRound] }
    private let defaults: UserDefaults
    private let writer: ((Any?) throws -> Void)?
    private let reader: (() -> Any?)?
    private(set) var isLocked = false

    init(defaults: UserDefaults = .standard, writer: ((Any?) throws -> Void)? = nil, reader: (() -> Any?)? = nil) {
        self.defaults = defaults
        self.writer = writer
        self.reader = reader
    }

    private func raw() -> Any? { reader.map { $0() } ?? defaults.object(forKey: Self.key) }

    func loadAll() throws -> [SentenceSavedRound] {
        guard let value = raw() else { return [] }
        guard let bytes = value as? Data else { throw SentenceGameError.sessionUnreadable }
        do {
            let archive = try JSONDecoder().decode(Archive.self, from: bytes)
            guard archive.version == 1,
                  Set(archive.sessions.map(\.id)).count == archive.sessions.count else {
                throw SentenceGameError.sessionUnreadable
            }
            for session in archive.sessions { try session.round.validate() }
            return archive.sessions.sorted { $0.savedAt > $1.savedAt }
        } catch { throw SentenceGameError.sessionUnreadable }
    }

    func load(topicID: UUID, mode: SentenceMode) throws -> SentenceSavedRound? {
        try loadAll().first { $0.id == SentenceSavedRound.slot(topicID: topicID, mode: mode) }
    }

    @discardableResult
    func save(_ round: SentenceRound, savedAt: Date = Date()) throws -> SentenceSavedRound {
        guard !isLocked else { throw SentenceGameError.sessionRecoveryFailed }
        let previous = try loadAll()
        let oldBytes = raw() as? Data
        let snapshot = SentenceRoundSnapshot(round: round)
        try snapshot.validate()
        let saved = SentenceSavedRound(round: snapshot, savedAt: savedAt)
        let slot = saved.id
        let replacement = (previous.filter { $0.id != slot } + [saved]).sorted { $0.savedAt > $1.savedAt }
        try persist(replacement, previous: previous, oldBytes: oldBytes)
        return saved
    }

    func remove(topicID: UUID, mode: SentenceMode) throws {
        let slot = SentenceSavedRound.slot(topicID: topicID, mode: mode)
        try update { $0.filter { $0.id != slot } }
    }

    func remove(topicID: UUID) throws {
        try update { $0.filter { $0.topicID != topicID } }
    }

    private func update(_ transform: ([SentenceSavedRound]) -> [SentenceSavedRound]) throws {
        guard !isLocked else { throw SentenceGameError.sessionRecoveryFailed }
        let previous = try loadAll()
        let replacement = transform(previous)
        guard replacement != previous else { return }
        try persist(replacement, previous: previous, oldBytes: raw() as? Data)
    }

    private func persist(_ sessions: [SentenceSavedRound], previous: [SentenceSavedRound], oldBytes: Data?) throws {
        let bytes = try JSONEncoder().encode(Archive(version: 1, sessions: sessions))
        let write = writer ?? { value in
            if let value { self.defaults.set(value, forKey: Self.key) }
            else { self.defaults.removeObject(forKey: Self.key) }
        }
        do {
            try write(bytes)
            guard raw() as? Data == bytes, try loadAll() == sessions else { throw SentenceGameError.sessionWriteFailed }
        } catch {
            do {
                try write(oldBytes)
                guard raw() as? Data == oldBytes, try loadAll() == previous else { throw SentenceGameError.sessionWriteFailed }
            } catch {
                isLocked = true
                throw SentenceGameError.sessionRecoveryFailed
            }
            throw SentenceGameError.sessionWriteFailed
        }
    }
}

@MainActor
final class SentenceRoundSessionModel: ObservableObject {
    @Published private(set) var sessions: [SentenceSavedRound] = []
    @Published private(set) var error: String?
    private let repository: SentenceRoundSessionRepository

    init(repository: SentenceRoundSessionRepository = SentenceRoundSessionRepository()) {
        self.repository = repository
        reload()
    }

    func session(topicID: UUID, mode: SentenceMode) -> SentenceSavedRound? {
        sessions.first { $0.id == SentenceSavedRound.slot(topicID: topicID, mode: mode) }
    }

    func reload() {
        do { sessions = try repository.loadAll(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func start(topic: SentenceTopic, mode: SentenceMode) throws -> SentenceRound {
        do {
            let round = try SentenceRound(topic: topic, mode: mode)
            try save(round)
            return round
        } catch { throw error }
    }

    func resume(topicID: UUID, mode: SentenceMode) throws -> SentenceRound {
        do {
            guard let saved = try repository.load(topicID: topicID, mode: mode) else {
                throw SentenceGameError.sessionMissing
            }
            let round = try saved.round.restore()
            sessions = try repository.loadAll()
            error = nil
            return round
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func save(_ round: SentenceRound) throws {
        do {
            _ = try repository.save(round)
            sessions = try repository.loadAll()
            error = nil
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func remove(topicID: UUID) throws {
        do {
            try repository.remove(topicID: topicID)
            sessions = try repository.loadAll()
            error = nil
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }
}

    struct SentenceBuilderTile: Codable, Equatable, Identifiable {
        let id: UUID
        let text: String
    }

    struct SentenceBuilderQuestion: Codable, Equatable, Identifiable {
        let pair: SentencePair
        let expectedWords: [String]
        let tiles: [SentenceBuilderTile]
        var bank: [SentenceBuilderTile]
        // Optional for v1 archives written before fixed bank slots.
        var originalBank: [SentenceBuilderTile]? = nil
        var arranged: [SentenceBuilderTile] = []
        var checks = 0
        var assisted = false
        var hintShown = false
        var viewed = false
        var stars: Int?
        var id: UUID { pair.id }

        var finished: Bool { stars != nil }
        var bankSlots: [SentenceBuilderTile] { originalBank ?? (bank + arranged) }
        var hint: String? { expectedWords.indices.contains(arranged.count) ? expectedWords[arranged.count] : nil }
        var isCorrect: Bool {
            arranged.map { SentenceBuilderRound.normalizedWord($0.text) }
                == expectedWords.map(SentenceBuilderRound.normalizedWord)
        }
    }

    struct SentenceBuilderRound: Codable, Equatable, Identifiable {
        let id: UUID
        let topic: SentenceTopic
        var questions: [SentenceBuilderQuestion]
        var index = 0

        static let minimumWords = 2
        static let maximumWords = 20
        static let maximumQuestions = 5

        init<Generator: RandomNumberGenerator>(
            topic: SentenceTopic, retryIDs: Set<UUID>? = nil, using generator: inout Generator
        ) throws {
            id = UUID()
            self.topic = try topic.validated()
            let eligible = Self.eligiblePairs(in: self.topic)
                .filter { retryIDs?.contains($0.id) ?? true }
                .shuffled(using: &generator).prefix(Self.maximumQuestions)
            guard !eligible.isEmpty else { throw SentenceGameError.tooSmall }
            questions = eligible.map { pair in
                let words = Self.words(in: pair.english)
                let tiles = words.map { SentenceBuilderTile(id: UUID(), text: $0) }
                var bank = tiles.shuffled(using: &generator)
                let expected = words.map(Self.normalizedWord)
                if bank.map({ Self.normalizedWord($0.text) }) == expected,
                   let differentIndex = bank.indices.dropFirst().first(where: {
                       Self.normalizedWord(bank[$0].text) != expected[0]
                   }) {
                    bank.swapAt(0, differentIndex)
                }
                return SentenceBuilderQuestion(pair: pair, expectedWords: words, tiles: tiles,
                                               bank: bank, originalBank: bank)
            }
        }

        init(topic: SentenceTopic, retryIDs: Set<UUID>? = nil) throws {
            var generator = SystemRandomNumberGenerator()
            try self.init(topic: topic, retryIDs: retryIDs, using: &generator)
        }

        static func words(in sentence: String) -> [String] {
            sentence.split(whereSeparator: \.isWhitespace).map {
                String($0).components(separatedBy: .punctuationCharacters).joined()
                    .lowercased()
            }.filter { !$0.isEmpty }
        }

        static func eligiblePairs(in topic: SentenceTopic) -> [SentencePair] {
            topic.pairs.filter {
                let words = words(in: $0.english)
                return (Self.minimumWords...Self.maximumWords).contains(words.count)
                    && Set(words.map(Self.normalizedWord)).count > 1
            }
        }

        static func normalizedWord(_ word: String) -> String {
            word.components(separatedBy: .punctuationCharacters).joined()
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }

        var current: SentenceBuilderQuestion? { questions.indices.contains(index) ? questions[index] : nil }
        var finished: Bool { index == questions.count }
        var score: Int { questions.compactMap(\.stars).reduce(0, +) }
        var replayIDs: Set<UUID> { Set(questions.filter { ($0.stars ?? 0) < 3 }.map(\.id)) }

        mutating func tapBank(_ id: UUID) {
            guard questions.indices.contains(index), !questions[index].finished,
                  let tileIndex = questions[index].bank.firstIndex(where: { $0.id == id }) else { return }
            preserveBankSlots()
            questions[index].arranged.append(questions[index].bank.remove(at: tileIndex))
        }

        mutating func tapArranged(_ id: UUID) {
            guard questions.indices.contains(index), !questions[index].finished,
                  let tileIndex = questions[index].arranged.firstIndex(where: { $0.id == id }) else { return }
            preserveBankSlots()
            questions[index].bank.append(questions[index].arranged.remove(at: tileIndex))
            let slots = questions[index].bankSlots.map(\.id)
            questions[index].bank.sort { slots.firstIndex(of: $0.id)! < slots.firstIndex(of: $1.id)! }
        }

        private mutating func preserveBankSlots() {
            if questions[index].originalBank == nil {
                questions[index].originalBank = questions[index].bankSlots
            }
        }

        mutating func moveArranged(from source: Int, to destination: Int) {
            guard questions.indices.contains(index), !questions[index].finished,
                  questions[index].arranged.indices.contains(source),
                  questions[index].arranged.indices.contains(destination), source != destination else { return }
            preserveBankSlots()
            let tile = questions[index].arranged.remove(at: source)
            questions[index].arranged.insert(tile, at: destination)
        }

        // Drag payloads identify both origin and tile, so stale/wrong-origin drops decline.
        @discardableResult
        mutating func dropTile(_ payload: String, before target: UUID? = nil) -> Bool {
            let parts = payload.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let id = UUID(uuidString: String(parts[1])),
                  questions.indices.contains(index), !questions[index].finished else { return false }
            let question = questions[index]
            let destination: Int
            if let target {
                guard let position = question.arranged.firstIndex(where: { $0.id == target }) else { return false }
                destination = position
            } else {
                destination = question.arranged.count
            }
            switch parts[0] {
            case "bank":
                guard let source = question.bank.firstIndex(where: { $0.id == id }) else { return false }
                preserveBankSlots()
                let tile = questions[index].bank.remove(at: source)
                questions[index].arranged.insert(tile, at: destination)
            case "arranged":
                guard let source = question.arranged.firstIndex(where: { $0.id == id }) else { return false }
                let insertion = destination - (source < destination ? 1 : 0)
                guard source != insertion else { return false }
                preserveBankSlots()
                let tile = questions[index].arranged.remove(at: source)
                questions[index].arranged.insert(tile, at: insertion)
            default:
                return false
            }
            return true
        }

        mutating func useHint() -> String? {
            guard questions.indices.contains(index), !questions[index].finished,
                  let hint = questions[index].hint else { return nil }
            questions[index].assisted = true
            questions[index].hintShown = true
            return hint
        }

        mutating func markHeard() {
            guard questions.indices.contains(index), !questions[index].finished else { return }
            questions[index].assisted = true
        }

        mutating func check() -> Bool? {
            guard questions.indices.contains(index), !questions[index].finished,
                  questions[index].arranged.count == questions[index].expectedWords.count else { return nil }
            questions[index].checks += 1
            let correct = questions[index].isCorrect
            questions[index].stars = correct ? (questions[index].assisted ? 1 : 3) : 0
            return correct
        }

        mutating func reveal() {
            guard questions.indices.contains(index), !questions[index].finished else { return }
            questions[index].viewed = true
            questions[index].stars = 0
        }

        mutating func advance() {
            guard questions.indices.contains(index), questions[index].finished else { return }
            index += 1
        }

        fileprivate func validate() throws {
            guard try topic.validated() == topic, (1...Self.maximumQuestions).contains(questions.count),
                  index >= 0, index <= questions.count,
                  Set(questions.map(\.id)).count == questions.count else { throw SentenceGameError.builderSessionUnreadable }
            let source = Dictionary(uniqueKeysWithValues: topic.pairs.map { ($0.id, $0) })
            for (questionIndex, question) in questions.enumerated() {
                let expected = Self.words(in: question.pair.english)
                let expectedIDs = Set(question.tiles.map(\.id))
                let visible = question.bank + question.arranged
                guard source[question.id] == question.pair,
                      (Self.minimumWords...Self.maximumWords).contains(expected.count),
                      question.expectedWords == expected, question.tiles.count == expected.count,
                      question.tiles.map(\.text) == expected,
                      expectedIDs.count == question.tiles.count,
                      Set(visible.map(\.id)) == expectedIDs, visible.count == expectedIDs.count,
                      visible.allSatisfy({ tile in question.tiles.contains(tile) }),
                      question.bankSlots.count == expectedIDs.count,
                      Set(question.bankSlots.map(\.id)) == expectedIDs,
                      question.bankSlots.allSatisfy({ question.tiles.contains($0) }),
                      question.checks >= 0,
                      question.stars.map({ (0...3).contains($0) }) ?? true,
                      !question.viewed || question.stars == 0,
                      !question.hintShown || question.assisted else {
                    throw SentenceGameError.builderSessionUnreadable
                }
                if question.finished && questionIndex > index { throw SentenceGameError.builderSessionUnreadable }
                if questionIndex < index && !question.finished { throw SentenceGameError.builderSessionUnreadable }
                switch question.stars {
                case 3 where question.checks >= 1 && !question.assisted:
                    break
                case 2 where question.checks >= 2 && !question.assisted:
                    break
                case 1 where question.checks >= 1 && question.assisted:
                    break
                case 0 where question.viewed:
                    break
                case 0 where question.checks >= 1 && question.arranged.count == expected.count && !question.isCorrect:
                    break
                case nil:
                    break
                default:
                    throw SentenceGameError.builderSessionUnreadable
                }
                if let stars = question.stars, stars > 0
                    && question.arranged.map({ Self.normalizedWord($0.text) }) != expected.map(Self.normalizedWord) {
                    throw SentenceGameError.builderSessionUnreadable
                }
            }
        }
    }

    struct SentenceBuilderSavedRound: Codable, Equatable, Identifiable {
        let round: SentenceBuilderRound
        let savedAt: Date
        var id: String { round.topic.id.uuidString }
    }

    final class SentenceBuilderSessionRepository {
        static let key = "sentenceBuilderSessions.v1"
        private struct Archive: Codable { let version: Int; let sessions: [SentenceBuilderSavedRound] }
        private let defaults: UserDefaults
        private let writer: ((Any?) throws -> Void)?
        private let reader: (() -> Any?)?
        private(set) var isLocked = false

        init(defaults: UserDefaults = .standard, writer: ((Any?) throws -> Void)? = nil, reader: (() -> Any?)? = nil) {
            self.defaults = defaults
            self.writer = writer
            self.reader = reader
        }

        private func raw() -> Any? { reader.map { $0() } ?? defaults.object(forKey: Self.key) }

        func loadAll() throws -> [SentenceBuilderSavedRound] {
            guard let value = raw() else { return [] }
            guard let bytes = value as? Data else { throw SentenceGameError.builderSessionUnreadable }
            do {
                let archive = try JSONDecoder().decode(Archive.self, from: bytes)
                guard archive.version == 1, Set(archive.sessions.map(\.id)).count == archive.sessions.count else {
                    throw SentenceGameError.builderSessionUnreadable
                }
                for session in archive.sessions { try session.round.validate() }
                return archive.sessions.sorted { $0.savedAt > $1.savedAt }
            } catch { throw SentenceGameError.builderSessionUnreadable }
        }

        func load(topicID: UUID) throws -> SentenceBuilderSavedRound? {
            try loadAll().first { $0.round.topic.id == topicID }
        }

        @discardableResult
        func save(_ round: SentenceBuilderRound, savedAt: Date = Date()) throws -> SentenceBuilderSavedRound {
            guard !isLocked else { throw SentenceGameError.builderSessionRecoveryFailed }
            let previous = try loadAll()
            let oldBytes = raw() as? Data
            try round.validate()
            let saved = SentenceBuilderSavedRound(round: round, savedAt: savedAt)
            let replacement = (previous.filter { $0.id != saved.id } + [saved]).sorted { $0.savedAt > $1.savedAt }
            try persist(replacement, previous: previous, oldBytes: oldBytes)
            return saved
        }

        func remove(topicID: UUID) throws {
            guard !isLocked else { throw SentenceGameError.builderSessionRecoveryFailed }
            let previous = try loadAll()
            let replacement = previous.filter { $0.round.topic.id != topicID }
            guard replacement != previous else { return }
            try persist(replacement, previous: previous, oldBytes: raw() as? Data)
        }

        private func persist(_ sessions: [SentenceBuilderSavedRound], previous: [SentenceBuilderSavedRound], oldBytes: Data?) throws {
            let bytes = try JSONEncoder().encode(Archive(version: 1, sessions: sessions))
            let write = writer ?? { value in
                if let value { self.defaults.set(value, forKey: Self.key) }
                else { self.defaults.removeObject(forKey: Self.key) }
            }
            do {
                try write(bytes)
                guard raw() as? Data == bytes, try loadAll() == sessions else { throw SentenceGameError.builderSessionWriteFailed }
            } catch {
                do {
                    try write(oldBytes)
                    guard raw() as? Data == oldBytes, try loadAll() == previous else {
                        throw SentenceGameError.builderSessionWriteFailed
                    }
                } catch {
                    isLocked = true
                    throw SentenceGameError.builderSessionRecoveryFailed
                }
                throw SentenceGameError.builderSessionWriteFailed
            }
        }
    }

    @MainActor
    final class SentenceBuilderSessionModel: ObservableObject {
        @Published private(set) var sessions: [SentenceBuilderSavedRound] = []
        @Published private(set) var error: String?
        private let repository: SentenceBuilderSessionRepository

        init(repository: SentenceBuilderSessionRepository = SentenceBuilderSessionRepository()) {
            self.repository = repository
            reload()
        }

        func session(topicID: UUID) -> SentenceBuilderSavedRound? {
            sessions.first { $0.round.topic.id == topicID }
        }

        func reload() {
            do { sessions = try repository.loadAll(); error = nil }
            catch { self.error = error.localizedDescription }
        }

        func start(topic: SentenceTopic, retryIDs: Set<UUID>? = nil) throws -> SentenceBuilderRound {
            do {
                let round = try SentenceBuilderRound(topic: topic, retryIDs: retryIDs)
                try save(round)
                return round
            } catch { throw error }
        }

        func resume(topicID: UUID) throws -> SentenceBuilderRound {
            do {
                guard let saved = try repository.load(topicID: topicID) else { throw SentenceGameError.sessionMissing }
                sessions = try repository.loadAll()
                error = nil
                return saved.round
            } catch {
                self.error = error.localizedDescription
                throw error
            }
        }

        func save(_ round: SentenceBuilderRound, afterSave: (() -> Void)? = nil) throws {
            do {
                _ = try repository.save(round)
                sessions = try repository.loadAll()
                error = nil
                afterSave?()
            } catch {
                self.error = error.localizedDescription
                throw error
            }
        }

        func remove(topicID: UUID) throws {
            do {
                try repository.remove(topicID: topicID)
                sessions = try repository.loadAll()
                error = nil
            } catch {
                self.error = error.localizedDescription
                throw error
            }
        }
    }
