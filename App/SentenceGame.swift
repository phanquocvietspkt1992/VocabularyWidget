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
    case invalidTopic, duplicatePair, duplicateTopic, invalidPaste, unreadable, writeFailed, recoveryFailed, stale, tooSmall

    var errorDescription: String? {
        switch self {
        case .invalidTopic: return "Enter a topic name and a nonempty English and Vietnamese sentence for every pair."
        case .duplicatePair: return "English and Vietnamese sentences must each be unique within the topic (ignoring case and whitespace)."
        case .duplicateTopic: return "Topic names must be unique."
        case .invalidPaste: return "Each nonempty row must contain English, one tab, then Vietnamese."
        case .unreadable: return "Sentence data cannot be read. It has not been replaced."
        case .writeFailed: return "The change could not be saved. Previous sentence data was restored."
        case .recoveryFailed: return "Saving and recovery failed. Editing is locked. Export recovery data when available."
        case .stale: return "Saved topics changed. Reopen the editor before saving again."
        case .tooSmall: return "At least four distinct sentence pairs are needed to play."
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

enum SentenceMode: String, CaseIterable, Identifiable {
    case stage = "Stage", quick = "Quick"
    var id: String { rawValue }
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

struct SentenceAnswer {
    let question: SentenceQuestion
    let selectedID: UUID
    var correct: Bool { selectedID == question.pair.id }
}

struct SentenceRound {
    let topic: SentenceTopic
    let mode: SentenceMode
    let questions: [SentenceQuestion]
    private(set) var answers: [SentenceAnswer] = []
    private(set) var selectedID: UUID?
    private(set) var index = 0

    init<Generator: RandomNumberGenerator>(topic: SentenceTopic, mode: SentenceMode,
                                          retryIDs: Set<UUID>? = nil, using generator: inout Generator) throws {
        self.topic = try topic.validated()
        self.mode = mode
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

    mutating func select(_ id: UUID) {
        guard let current, !revealed, current.options.contains(where: { $0.id == id }) else { return }
        selectedID = id
        if mode == .quick { confirm() }
    }

    mutating func confirm() {
        guard let current, let selectedID, !revealed else { return }
        answers.append(SentenceAnswer(question: current, selectedID: selectedID))
    }

    mutating func advance() {
        guard revealed else { return }
        index += 1
        selectedID = nil
    }
}