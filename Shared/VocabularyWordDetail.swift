import Foundation

struct VocabularyWordIdentity: Equatable {
    let topicID: String
    let index: Int
    let text: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index && lhs.topicID.utf8.elementsEqual(rhs.topicID.utf8) && lhs.text.utf8.elementsEqual(rhs.text.utf8)
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = WordDetailRoute.scheme
        components.host = "word"
        components.path = "/detail"
        components.queryItems = [URLQueryItem(name: "v", value: "1"),
                                 URLQueryItem(name: "topicID", value: topicID),
                                 URLQueryItem(name: "index", value: String(index)),
                                 URLQueryItem(name: "text", value: text)]
        return components.url!
    }

    func resolve(in topics: [VocabularyTopic]) -> VocabularyWordSnapshot? {
        guard Set(topics.map(\.id)).count == topics.count,
              let topic = topics.first(where: { $0.id.utf8.elementsEqual(topicID.utf8) }),
              topic.words.indices.contains(index), topic.words[index].text.utf8.elementsEqual(text.utf8) else { return nil }
        return VocabularyWordSnapshot(identity: self, topicName: topic.name, word: topic.words[index])
    }
}

enum WordDetailRoute: Equatable {
    static let scheme = "vocabularywidget-word"
    static let rootURL = URL(string: "vocabularywidget-word://app/")!
    case root
    case word(VocabularyWordIdentity)

    static func parse(_ url: URL) -> Self? { parse(url.absoluteString) }

    static func parse(_ raw: String) -> Self? {
        let bytes = Array(raw.utf8)
        for offset in bytes.indices where bytes[offset] == 37 {
            guard offset + 2 < bytes.count,
                  bytes[(offset + 1)...(offset + 2)].allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        }
        guard let components = URLComponents(string: raw), components.scheme == scheme,
              components.user == nil, components.password == nil, components.port == nil,
              components.fragment == nil else { return nil }
          guard let hostRange = components.rangeOfHost, let pathRange = components.rangeOfPath,
              hostRange.upperBound == pathRange.lowerBound,
              components.percentEncodedHost == components.host else { return nil }
          if components.host == "app", components.percentEncodedPath == "/", components.query == nil { return .root }
          guard components.host == "word", components.percentEncodedPath == "/detail",
              let items = components.queryItems, items.count == 4,
              Set(items.map(\.name)) == Set(["v", "topicID", "index", "text"]),
              items.allSatisfy({ $0.value != nil }) else { return nil }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        guard values["v"] == "1", let topicID = values["topicID"], !topicID.isEmpty,
              let text = values["text"], !text.isEmpty, let indexText = values["index"],
              !indexText.isEmpty, indexText.utf8.allSatisfy({ (48...57).contains($0) }),
              let index = Int(indexText) else { return nil }
        return .word(VocabularyWordIdentity(topicID: topicID, index: index, text: text))
    }
}

struct VocabularyWordSnapshot {
    let identity: VocabularyWordIdentity
    let topicName: String
    let word: VocabularyWord
}

struct VocabularyDetailSession: Identifiable {
    let id = UUID()
    private(set) var identity: VocabularyWordIdentity
    private(set) var snapshot: VocabularyWordSnapshot?
    private(set) var generation = UUID()

    init(identity: VocabularyWordIdentity, catalog: () throws -> [VocabularyTopic] = VocabularyCatalog.detailTopics) {
        self.identity = identity
        snapshot = (try? catalog()).flatMap { identity.resolve(in: $0) }
    }

    func acceptsCompletion(_ token: UUID) -> Bool { generation == token }

    mutating func cancelPlayback() { generation = UUID() }

    func actionProblem(catalog: () throws -> [VocabularyTopic] = VocabularyCatalog.detailTopics,
                       selectedID: () -> String = { WidgetProgressStore.selectedTopicID }) -> String? {
        guard let topics = try? catalog(), identity.resolve(in: topics) != nil else {
            return "This word is no longer available."
        }
        guard selectedID().utf8.elementsEqual(identity.topicID.utf8) else { return "Progress actions are available only for the selected topic." }
        guard WidgetProgressStore.hasReadableStudyHistory() else { return "Study history cannot be read. Progress has not changed." }
        return nil
    }

    mutating func advance(markLearned: Bool, at date: Date = .now, calendar: Calendar = .current,
                          catalog: () throws -> [VocabularyTopic] = VocabularyCatalog.detailTopics,
                          selectedID: () -> String = { WidgetProgressStore.selectedTopicID },
                          advance: (String, Int, Date) -> Bool = { WidgetProgressStore.advanceDisplayedWord(topicID: $0, displayedIndex: $1, at: $2) },
                          mark: (String, Int, Date, Calendar) -> Bool = { WidgetProgressStore.markStudiedAndAdvance(topicID: $0, displayedIndex: $1, at: $2, calendar: $3) },
                          onSuccess: () -> Void = {}) -> Bool {
        cancelPlayback()
        guard let topics = try? catalog(), identity.resolve(in: topics) != nil,
              let topic = topics.first(where: { $0.id.utf8.elementsEqual(identity.topicID.utf8) }),
              WidgetProgressStore.hasReadableStudyHistory(),
              selectedID().utf8.elementsEqual(identity.topicID.utf8) else { return false }
        let accepted = markLearned ? mark(identity.topicID, identity.index, date, calendar)
                                  : advance(identity.topicID, identity.index, date)
        guard accepted else { return false }
        let nextIndex = (identity.index + 1) % topic.words.count
        identity = VocabularyWordIdentity(topicID: topic.id, index: nextIndex, text: topic.words[nextIndex].text)
        snapshot = identity.resolve(in: topics)
        onSuccess()
        return true
    }
}

struct VocabularyDetailRoutingState {
    private(set) var detail: VocabularyDetailSession?
    private(set) var pending: WordDetailRoute?

    mutating func receive(_ route: WordDetailRoute, blocked: Bool, cancelPlayback: () -> Void = {}) {
        if blocked { pending = route; return }
        pending = nil
        cancelPlayback()
        switch route {
        case .root: detail = nil
        case .word(let identity): detail = VocabularyDetailSession(identity: identity)
        }
    }

    mutating func drain(blocked: Bool, cancelPlayback: () -> Void = {}) {
        guard !blocked, let route = pending else { return }
        receive(route, blocked: false, cancelPlayback: cancelPlayback)
    }

    mutating func close(cancelPlayback: () -> Void = {}) {
        cancelPlayback()
        detail = nil
    }
}