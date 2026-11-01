import Foundation

struct SpeakWordIntent {
    let word: String
    func perform() async throws { fatalError("Detail playback checks must inject their performer.") }
}

@main
struct ProgressStoreChecks {
    private static var checksPassed = 0

    @MainActor
    private static func checkDetailPresentation(_ suite: UserDefaults) {
        let topic = VocabularyCatalog.topics[0]
        let identity = VocabularyWordIdentity(topicID: topic.id, index: 0, text: topic.words[0].text)
        let model = TopicSelectionModel()
        let router = VocabularyDetailRouter()
        let before = suite.dictionaryRepresentation()
        var cancellations = 0
        let owner = UUID()
        router.registerPlayback(owner: owner) { cancellations += 1 }
        router.open(identity.url, blocked: false)
        let firstID = router.state.detail!.id
        router.open(URL(string: "https://example.com")!, blocked: false)
        check(router.state.detail?.id == firstID && cancellations == 1, "production handler ignores foreign URL without audio cancellation")
        router.open(identity.url, blocked: true)
        router.open(WordDetailRoute.rootURL, blocked: true)
        router.drain(blocked: true)
        check(router.state.detail?.id == firstID && cancellations == 1, "production handler queues latest root without dismissing a modal")
        router.drain(blocked: false)
        check(router.state.detail == nil && cancellations == 2, "production handler drains root after modal dismissal")
        router.open(identity.url, blocked: false)
        let repeatedID = router.state.detail!.id
        router.open(identity.url, blocked: false)
        check(router.state.detail?.id != repeatedID && cancellations == 4, "production repeated URL cancels playback before fresh detail")
        router.unregisterPlayback(owner: UUID())
        router.close()
        check(cancellations == 5, "old view cannot unregister new playback owner")
        check(NSDictionary(dictionary: suite.dictionaryRepresentation()).isEqual(to: before), "production URL opening/queue/close has no defaults writes")

          let modalBaseline = suite.dictionaryRepresentation()
          for route in [identity.url, WordDetailRoute.rootURL] {
            let queuedRouter = VocabularyDetailRouter()
            queuedRouter.open(identity.url, blocked: false)
            let displayedID = queuedRouter.state.detail!.id
            model.resetTopicID = topic.id
            model.showingResetConfirmation = true
            check(model.blocksWordDetail && model.presentedSheets.contains("reset"), "reset toggle immediately retains native presentation blocker")
            queuedRouter.open(identity.url, blocked: model.blocksWordDetail)
            queuedRouter.open(route, blocked: model.blocksWordDetail)
            check(model.showingResetConfirmation && model.resetTopicID == topic.id && queuedRouter.state.detail?.id == displayedID,
                "queued latest link does not drop active reset confirmation")
            model.resetTopicID = nil
            model.showingResetConfirmation = false
            model.trackPresentedSheets()
            Task { @MainActor in
                await Task.yield()
                queuedRouter.drain(blocked: model.blocksWordDetail)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            check(model.blocksWordDetail && queuedRouter.state.pending == WordDetailRoute.parse(route) && queuedRouter.state.detail?.id == displayedID,
                "reset binding false and scheduler yield cannot drain during native dismissal")
            check(NSDictionary(dictionary: suite.dictionaryRepresentation()).isEqual(to: modalBaseline), "reset Cancel and pending app-close link write no defaults")
            model.presentedSheets.remove("reset")
            queuedRouter.drain(blocked: model.blocksWordDetail)
            check(!model.blocksWordDetail && queuedRouter.state.pending == nil,
                "reset onDismiss releases blocker and consumes latest route")
            check(route == WordDetailRoute.rootURL ? queuedRouter.state.detail == nil : queuedRouter.state.detail?.id != displayedID,
                "actual reset dismissal applies queued app-close or fresh word detail")
            check(NSDictionary(dictionary: suite.dictionaryRepresentation()).isEqual(to: modalBaseline), "actual reset dismissal and queued detail routing write no defaults")
          }

          let deleteRouter = VocabularyDetailRouter()
          deleteRouter.open(identity.url, blocked: false)
          let detailBeforeDeletePrompt = deleteRouter.state.detail!.id
          model.deleteTopicID = "custom_delete-pending"
          model.deleteTopicName = "Delete Pending"
          model.showingDeleteTopicConfirmation = true
          check(model.blocksWordDetail && model.presentedSheets.contains("delete-topic"),
              "delete confirmation immediately blocks detail presentation")
          deleteRouter.open(WordDetailRoute.rootURL, blocked: model.blocksWordDetail)
          model.showingDeleteTopicConfirmation = false
          check(model.blocksWordDetail && deleteRouter.state.pending == .root && deleteRouter.state.detail?.id == detailBeforeDeletePrompt,
              "queued detail link remains blocked until delete sheet onDismiss")
          model.deleteTopicID = nil
          model.deleteTopicName = nil
          model.presentedSheets.remove("delete-topic")
          deleteRouter.drain(blocked: model.blocksWordDetail)
          check(!model.blocksWordDetail && deleteRouter.state.pending == nil && deleteRouter.state.detail == nil,
              "delete sheet dismissal drains the latest queued app-close link")

        let playback = VocabularyDetailPlayback()
        var starts = 0
        playback.speak("inactive", perform: { _ in starts += 1 })
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        check(starts == 0 && !playback.isSpeaking, "inactive host cannot start detail audio")
        playback.isActive = true
        playback.speak("cancel before start", perform: { _ in starts += 1 })
        playback.isActive = false
        playback.cancel()
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        check(starts == 0 && !playback.isSpeaking, "scene cancellation before queued task prevents background start")
        playback.isActive = true
        var oldCompletion: CheckedContinuation<Void, Error>?
        var newCompletion: CheckedContinuation<Void, Error>?
        playback.speak("first", perform: { _ in
            starts += 1
            try await withCheckedThrowingContinuation { oldCompletion = $0 }
        })
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        check(starts == 1 && playback.isSpeaking && oldCompletion != nil, "explicit Speak starts injected performer and shows loading")
        playback.speak("second", perform: { _ in
            starts += 1
            try await withCheckedThrowingContinuation { newCompletion = $0 }
        })
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        oldCompletion?.resume(throwing: NSError(domain: "DetailTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Old error"]))
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        check(starts == 2 && playback.isSpeaking && playback.errorMessage == nil, "late canceled completion cannot clear loading or set old error on new word")
        newCompletion?.resume(throwing: NSError(domain: "DetailTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Actual audio failure"]))
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        check(!playback.isSpeaking && playback.errorMessage == "Actual audio failure", "current performer error is shown verbatim")
        playback.cancel()
        check(!playback.isSpeaking && playback.errorMessage == nil, "close/advance/new-route cancellation clears local audio status")
        check(NSDictionary(dictionary: suite.dictionaryRepresentation()).isEqual(to: before), "detail audio status never changes progress or selection")
    }

    private static func checkWordDetail(_ suite: UserDefaults) {
        let topic = VocabularyCatalog.topics[0]
        let identity = VocabularyWordIdentity(topicID: topic.id, index: 0, text: topic.words[0].text)
        let special = VocabularyWordIdentity(topicID: "chủ đề +%&/?", index: 12, text: "café + 50% &?#")
        check(WordDetailRoute.parse(special.url) == .word(special), "detail URLs round trip Unicode, spaces, percent and literal plus")
        check(WordDetailRoute.parse(WordDetailRoute.rootURL) == .root, "root URL accepted")
        let valid = identity.url.absoluteString
        for raw in [valid + "&v=1", valid + "&extra=x", valid.replacingOccurrences(of: "v=1", with: "v=2"),
                    valid.replacingOccurrences(of: "index=0", with: "index=-1"),
                    valid.replacingOccurrences(of: "index=0", with: "index=999999999999999999999999"),
                    valid.replacingOccurrences(of: "&text=colleague", with: ""),
                    valid + "#fragment", valid.replacingOccurrences(of: "//word", with: "//user@word"),
                    valid.replacingOccurrences(of: "//word", with: "//word:80"),
                    valid.replacingOccurrences(of: "//word", with: "//word:"),
                    "vocabularywidget-word://app:/",
                    valid.replacingOccurrences(of: "/detail", with: "/%64etail"),
                    valid.replacingOccurrences(of: "/detail", with: "/other"),
                    valid.replacingOccurrences(of: "//word", with: "//other"),
                    valid.replacingOccurrences(of: WordDetailRoute.scheme, with: "foreign"),
                    valid + "%", valid + "%GG"] {
            check(WordDetailRoute.parse(raw) == nil, "strict route rejects \(raw)")
        }
        let before = suite.dictionaryRepresentation()
        var session = VocabularyDetailSession(identity: identity)
        check(session.snapshot?.word.examples.count == 5, "detail loads all five current examples")
        check(NSDictionary(dictionary: suite.dictionaryRepresentation()).isEqual(to: before), "opening detail writes nothing")
        let originalGeneration = session.generation
        var callbacks = 0
        check(!session.advance(markLearned: false, selectedID: { "other" }, onSuccess: { callbacks += 1 }), "other active topic blocks action")
        check(session.identity == identity && callbacks == 0 && !session.acceptsCompletion(originalGeneration), "blocked action preserves snapshot and invalidates old completion")
        suite.set(topic.id, forKey: "selectedTopic")
        let saved = suite.dictionaryRepresentation()
        check(!session.advance(markLearned: false, advance: { _, _, _ in false }, onSuccess: { callbacks += 1 }), "rejected advance reports failure")
        check(!session.advance(markLearned: true, mark: { _, _, _, _ in false }, onSuccess: { callbacks += 1 }), "rejected mark reports failure")
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        check(session.identity == identity && callbacks == 0 && NSDictionary(dictionary: suite.dictionaryRepresentation()).isEqual(to: saved), "false callbacks preserve snapshot and defaults with no queued effects")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        suite.set(20, forKey: "progress.\(topic.id)")
        suite.set(date.addingTimeInterval(-3600), forKey: "anchor.\(topic.id)")
        check(session.advance(markLearned: false, at: date, onSuccess: { callbacks += 1 }), "advance accepts old displayed index")
        check(session.identity.index == 1 && suite.integer(forKey: "progress.\(topic.id)") == 1 && suite.object(forKey: "anchor.\(topic.id)") as? Date == date && callbacks == 1, "Next advances from displayed index and anchors at action date")
        let detailNextState = suite.dictionaryRepresentation()
        check(WidgetProgressStore.advanceDisplayedWord(topicID: topic.id, displayedIndex: 0, at: date), "widget advance comparison accepted")
        check(NSDictionary(dictionary: suite.dictionaryRepresentation()).isEqual(to: detailNextState), "detail Next and widget advance produce identical raw state")
        session = VocabularyDetailSession(identity: VocabularyWordIdentity(topicID: topic.id, index: topic.words.count - 1, text: topic.words.last!.text))
        check(session.advance(markLearned: false, at: date) && session.identity == identity, "detail Next wraps final displayed index to zero")
        session = VocabularyDetailSession(identity: identity)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
        for _ in 0..<2 {
            session = VocabularyDetailSession(identity: identity)
            check(session.advance(markLearned: true, at: date, calendar: calendar), "mark accepts displayed identity")
        }
        check(WidgetProgressStore.allStudyHistory().count == 1 && WidgetProgressStore.allStudyHistory()[0].day == WidgetProgressStore.dayKey(for: date, calendar: calendar), "mark deduplicates topic/text/local day")
        let detailMarkState = suite.dictionaryRepresentation()
        check(WidgetProgressStore.markStudiedAndAdvance(topicID: topic.id, displayedIndex: 0, at: date, calendar: calendar), "widget mark comparison accepted")
        check(NSDictionary(dictionary: suite.dictionaryRepresentation()).isEqual(to: detailMarkState), "detail Mark and widget mark produce identical raw history/progress/anchor state")
        suite.set(Data("broken".utf8), forKey: "studyHistory.v1")
        session = VocabularyDetailSession(identity: identity)
        let corruptHistory = suite.dictionaryRepresentation()
        check(!session.advance(markLearned: true, at: date), "corrupt history rejects mark")
        check(!session.advance(markLearned: false, at: date), "corrupt history rejects detail Next too")
        check(session.identity == identity && NSDictionary(dictionary: suite.dictionaryRepresentation()).isEqual(to: corruptHistory), "corrupt history leaves snapshot and state unchanged")
        suite.removeObject(forKey: "studyHistory.v1")
        suite.set(Data("broken".utf8), forKey: "review.v1")
        check(VocabularyDetailSession(identity: identity).snapshot != nil, "unrelated corrupt review does not block detail")
        suite.removeObject(forKey: "review.v1")
        let duplicate = VocabularyWord(text: identity.text, partOfSpeech: "(n)", meaning: "Different meaning", examples: Array(repeating: "Custom example", count: 5))
        suite.set(try! JSONEncoder().encode([topic.id: [duplicate]]), forKey: "customVocabularyByTopic.v1")
        let duplicateIdentity = VocabularyWordIdentity(topicID: topic.id, index: topic.words.count, text: identity.text)
        check(VocabularyDetailSession(identity: duplicateIdentity).snapshot?.word.meaning == duplicate.meaning, "same text at distinct catalog indices resolves full tuple")
        check(VocabularyDetailSession(identity: identity).snapshot?.word.meaning == topic.words[0].meaning, "built-in duplicate keeps built-in fields")
        let composed = VocabularyWordIdentity(topicID: "unicode", index: 0, text: "\u{00E9}")
        let decomposedWord = VocabularyWord(text: "e\u{0301}", partOfSpeech: "(n)", meaning: "Accent", examples: Array(repeating: "Example", count: 5))
        check(composed.resolve(in: [VocabularyTopic(id: "unicode", name: "Unicode", words: [decomposedWord])]) == nil, "exact word identity does not normalize Unicode")
        let frozen = session.snapshot?.word
        suite.set(try! JSONEncoder().encode([topic.id: [] as [VocabularyWord]]), forKey: "customVocabularyByTopic.v1")
        var removedSession = VocabularyDetailSession(identity: duplicateIdentity)
        check(removedSession.snapshot == nil && !removedSession.advance(markLearned: false, at: date), "deleted custom index is unavailable and cannot advance")
        check(session.snapshot?.word == frozen, "catalog edits do not replace a displayed snapshot")
        suite.set(Data("broken".utf8), forKey: "customVocabularyByTopic.v1")
        check(VocabularyDetailSession(identity: identity).snapshot == nil, "corrupt custom word dictionary does not fall back")
        suite.removeObject(forKey: "customVocabularyByTopic.v1")
        for invalid in [VocabularyWordIdentity(topicID: "missing", index: 0, text: identity.text),
                        VocabularyWordIdentity(topicID: topic.id, index: 5000, text: identity.text),
                        VocabularyWordIdentity(topicID: topic.id, index: 1, text: identity.text),
                        VocabularyWordIdentity(topicID: " " + topic.id, index: 0, text: identity.text)] {
            check(VocabularyDetailSession(identity: invalid).snapshot == nil, "missing, stale and unnormalized identities do not fall back")
        }
        suite.set(try! JSONEncoder().encode([CustomTopicStore.Topic(id: topic.id, name: "Collision")]), forKey: "customTopics.v1")
        check(VocabularyDetailSession(identity: identity).snapshot == nil, "duplicate topic IDs reject catalog")
        suite.set(Data("broken".utf8), forKey: "customTopics.v1")
        let broken = suite.dictionaryRepresentation()
        session = VocabularyDetailSession(identity: identity)
        check(session.snapshot == nil && !session.advance(markLearned: false, at: date), "corrupt catalog blocks resolution and advance")
        check(NSDictionary(dictionary: suite.dictionaryRepresentation()).isEqual(to: broken), "corrupt catalog action writes nothing")
        suite.removeObject(forKey: "customTopics.v1")
        suite.removeObject(forKey: "customVocabularyByTopic.v1")
        var router = VocabularyDetailRoutingState()
        var cancellations = 0
        router.receive(.word(identity), blocked: false, cancelPlayback: { cancellations += 1 })
        let firstID = router.detail!.id
        router.receive(.word(identity), blocked: true)
        router.receive(.word(duplicateIdentity), blocked: true)
        check(router.detail?.id == firstID && router.pending == .word(duplicateIdentity), "blocked modals retain detail and only latest pending link")
        router.drain(blocked: true)
        check(router.detail?.id == firstID, "drain cannot dismiss another modal")
        router.drain(blocked: false, cancelPlayback: { cancellations += 1 })
        check(router.detail?.identity == duplicateIdentity && router.detail?.id != firstID && cancellations == 2, "drained link gets fresh presentation and cancels playback")
        router.receive(.word(identity), blocked: false)
        let repeatID = router.detail!.id
        router.receive(.word(identity), blocked: false)
        check(router.detail?.id != repeatID, "repeated URL creates fresh detail")
        router.receive(.root, blocked: false, cancelPlayback: { cancellations += 1 })
        check(router.detail == nil && router.pending == nil && cancellations == 3, "root closes only detail and cancels playback")
    }

    private static func checkBackupCore(_ suite: UserDefaults) {
        let broken = Data("[{]".utf8)
        suite.set(broken, forKey: "customTopics.v1")
        check((try? VocabularyLearningStore.exportBackup()) == nil, "export must reject corrupt source rather than export fallback empty topics")
        check(suite.data(forKey: "customTopics.v1") == broken, "failed export preserves source bytes")
        suite.removeObject(forKey: "customTopics.v1")
        let empty = try! VocabularyLearningStore.decodeBackup(VocabularyLearningStore.exportBackup())
        check(try! empty.validatedSnapshot().isEmpty, "absent stores form a valid empty backup")
        check((try? VocabularyLearningStore.decodeBackup(Data("{}".utf8))) == nil, "empty JSON object is not a backup")
        suite.set("keep", forKey: "unrelated")
        suite.set(999, forKey: "progress.stale")
        suite.set(false, forKey: "visited.stale")
        let previous = try! VocabularyLearningStore.rawSnapshot()
        let populated = try! VocabularyLearningStore.decodeBackup(VocabularyLearningStore.exportBackup())
        var writes = 0
        do {
            try VocabularyLearningStore.restore(empty, writer: { key, value in
                writes += 1
                if writes == 2 { throw LearningStorageError.writeFailed }
                if let value { suite.set(value, forKey: key) } else { suite.removeObject(forKey: key) }
            })
            check(false, "injected writer failure must be reported")
        } catch { check(true, "injected writer failure must be reported") }
        check(NSDictionary(dictionary: try! VocabularyLearningStore.rawSnapshot()).isEqual(to: previous), "failed replacement restores exact snapshot and false flags")
        var reads = 0
        do {
            try VocabularyLearningStore.restore(empty, reader: {
                reads += 1
                if reads == 1 { throw LearningStorageError.writeFailed }
                return suite.dictionaryRepresentation().filter { VocabularyLearningStore.owns($0.key) }
            })
            check(false, "injected readback failure must be reported")
        } catch { check(true, "injected readback failure must be reported") }
        check(NSDictionary(dictionary: try! VocabularyLearningStore.rawSnapshot()).isEqual(to: previous), "readback failure rolls back")
        try! VocabularyLearningStore.restore(empty)
        check(try! VocabularyLearningStore.rawSnapshot().isEmpty, "empty restore removes destination-only owned keys")
        check(suite.string(forKey: "unrelated") == "keep", "restore leaves unrelated preferences alone")
        try! VocabularyLearningStore.restore(populated)
        check(suite.integer(forKey: "progress.stale") == 999, "restore preserves nonnegative out-of-range stale indices")
        suite.set(broken, forKey: "studyHistory.v1")
        writes = 0
        do { try VocabularyLearningStore.restore(empty, writer: { _, _ in writes += 1 }) } catch {}
        check(writes == 0 && suite.data(forKey: "studyHistory.v1") == broken, "unreadable destination blocks restore before writes")
    }

    private static func checkReviewCore(_ suite: UserDefaults) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12))!
        suite.set("work_communication", forKey: "selectedTopic")
        let protected = try! VocabularyLearningStore.rawSnapshot()
        var session = VocabularyReviewSession()
        try! session.start(at: start, calendar: calendar)
        check(session.total == 10 && session.currentWord?.text == "colleague" && !session.revealed, "fresh review has at most ten distinct new words in catalog order")
        let first = session.cardID
        do { try session.grade(.remember, card: first, at: start, calendar: calendar); check(false, "hidden card cannot be graded") }
        catch { check(session.completed == 0, "hidden card cannot be graded") }
        try! session.reveal(card: first, at: start, calendar: calendar)
        var writes = 0
        do {
            try session.grade(.remember, card: first, at: start, calendar: calendar, writer: { data in
                writes += 1
                if writes == 1 { throw LearningStorageError.writeFailed }
                if let data { suite.set(data, forKey: "review.v1") } else { suite.removeObject(forKey: "review.v1") }
            })
            check(false, "failed grade reports failure")
        } catch { check(session.revealed && session.completed == 0 && session.reviewedToday == 0, "failed grade keeps answer and prior counters") }
        check(NSDictionary(dictionary: try! VocabularyLearningStore.rawSnapshot()).isEqual(to: protected), "failed grade has no persisted side effects")
        try! session.grade(.remember, card: first, at: start, calendar: calendar)
        check(session.completed == 1 && session.reviewedToday == 1 && !session.revealed && session.currentWord?.text == "teammate", "accepted grade advances once and hides next answer")
        try! session.refresh(at: start, calendar: calendar)
        check(session.completed == 1 && session.currentWord?.text == "teammate", "refresh after successful grade preserves the session and exact saved review bytes")
        let state = try! VocabularyReviewStore.state(in: VocabularyLearningStore.rawSnapshot())
        let due = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        check(state.records[0].stage == 1 && state.records[0].dueAt == due, "Remember schedules next local midnight across DST")
        check(NSDictionary(dictionary: try! VocabularyLearningStore.rawSnapshot().filter { $0.key != "review.v1" }).isEqual(to: protected), "grading never changes widget progress, selection, history or schedule")
        do { try session.grade(.remember, card: first, at: start, calendar: calendar); check(false, "old card action rejected") }
        catch { check(session.completed == 1, "old card action rejected") }
        var gradedAt = due.addingTimeInterval(12 * 3600)
        for days in [3, 7, 14, 30, 30] {
            try! session.start(at: gradedAt, calendar: calendar)
            check(session.currentWord?.text == "colleague", "due word takes precedence over unrated words")
            try! session.reveal(card: session.cardID, at: gradedAt, calendar: calendar)
            try! session.grade(.remember, card: session.cardID, at: gradedAt, calendar: calendar)
            let record = try! VocabularyReviewStore.state(in: VocabularyLearningStore.rawSnapshot()).records[0]
            check(record.dueAt == calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: gradedAt)), "Remember interval follows staged local calendar days and cap")
            gradedAt = record.dueAt.addingTimeInterval(12 * 3600)
        }
        try! session.start(at: gradedAt, calendar: calendar)
        try! session.reveal(card: session.cardID, at: gradedAt, calendar: calendar)
        try! session.grade(.again, card: session.cardID, at: gradedAt, calendar: calendar)
        let again = try! VocabularyReviewStore.state(in: VocabularyLearningStore.rawSnapshot()).records[0]
        check(again.stage == 0 && again.dueAt == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: gradedAt)), "Again resets stage and schedules tomorrow")
        gradedAt = again.dueAt.addingTimeInterval(12 * 3600)
        try! session.start(at: gradedAt, calendar: calendar)
        try! session.reveal(card: session.cardID, at: gradedAt, calendar: calendar)
        try! session.grade(.remember, card: session.cardID, at: gradedAt, calendar: calendar)
        check(try! VocabularyReviewStore.state(in: VocabularyLearningStore.rawSnapshot()).records[0].stage == 1, "Remember after Again restarts at one day")
        try! session.reveal(card: session.cardID, at: gradedAt, calendar: calendar)
        let stale = session.cardID
        suite.set("travel", forKey: "selectedTopic")
        do { try session.grade(.remember, card: stale, at: gradedAt, calendar: calendar); check(false, "selection change rejects stale grade") }
        catch { check(true, "selection change rejects stale grade") }
        try! session.refresh(at: gradedAt, calendar: calendar)
        check(session.topicID == "travel" && session.completed == 0 && !session.revealed, "selection change abandons old queue and answer")
        try! session.reveal(card: session.cardID, at: gradedAt, calendar: calendar)
        try! session.refresh(at: calendar.date(byAdding: .day, value: 1, to: gradedAt)!, calendar: calendar)
        check(!session.revealed && session.completed == 0, "midnight refresh hides answer and opens fresh queue")
        suite.set("missing_topic", forKey: "selectedTopic")
        try! session.start(at: start, calendar: calendar)
        check(session.queue.isEmpty, "unknown selected topic must not fall back for review")
        suite.set(Data("broken".utf8), forKey: "review.v1")
        do { try session.refresh(at: start, calendar: calendar); check(false, "corrupt review must fail refresh") }
        catch { check(session.queue.isEmpty && !session.revealed, "corrupt review must fail refresh with hidden empty session") }
    }

    private static func checkBackupValidation(_ suite: UserDefaults) {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let topic = CustomTopicStore.Topic(id: "custom_owned", name: "Work Communication")
        let word = VocabularyWord(text: "colleague", partOfSpeech: "(n)", meaning: "user meaning", examples: ["One.", "Two.", "Three.", "Four.", "Five."])
        let record = StudyHistoryRecord(topicID: topic.id, wordID: word.text, day: "2026-11-01", studiedAt: date)
        let identity = ReviewIdentity(topicID: topic.id, wordID: word.text)
        let reviewRecord = VocabularyReviewRecord(identity: identity, stage: 1, dueAt: date.addingTimeInterval(100), reviewedAt: date)
        let attempt = VocabularyReviewAttempt(id: UUID(), identity: identity, grade: .remember, at: date)
        let review = VocabularyReviewState(records: [reviewRecord], attempts: [attempt])
        let valid: [String: Any] = [
            "customTopics.v1": try! JSONEncoder().encode([topic]),
            "customVocabularyByTopic.v1": try! JSONEncoder().encode(["work_communication": [word], topic.id: [word], "removed_builtin": [word]]),
            "selectedTopic": topic.id,
            "progress.\(topic.id)": 0,
            "anchor.\(topic.id)": date,
            "visited.\(topic.id)": false,
            "progress.removed_builtin": 9999,
            "schedule.v1": try! JSONEncoder().encode(VocabularySchedule()),
            "studyHistory.v1": try! JSONEncoder().encode([record]),
            "review.v1": try! JSONEncoder().encode(review)
        ]
        func unchecked(_ values: [String: Any], version: Int = 1, at: Date? = nil) -> VocabularyBackup {
            VocabularyBackup(schemaVersion: version, createdAt: at ?? date,
                             payload: try! PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0))
        }
        let backup = try! VocabularyLearningStore.decodeBackup(VocabularyLearningStore.encodeBackup(valid, at: date))
        try! VocabularyLearningStore.restore(backup)
        check(NSDictionary(dictionary: try! VocabularyLearningStore.rawSnapshot()).isEqual(to: valid), "full backup retains raw Data, absent keys, false flags, zero indices, and stale references")
        check(CustomTopicStore.topics == [topic] && CustomVocabularyStore.words(for: "work_communication") == [word], "built-in display-name collisions and user words matching bundled words remain valid")
        var invalids: [[String: Any]] = []
        func invalid(_ key: String, _ value: Any) {
            var changed = valid
            changed[key] = value
            invalids.append(changed)
        }
        invalid("selectedTopic", 123)
        invalid("selectedTopic", "custom_missing")
        invalid("progress.\(topic.id)", -1)
        invalid("progress.\(topic.id)", true)
        invalid("progress.\(topic.id)", 1.5)
        invalid("progress.\(topic.id)", "0")
        invalid("anchor.\(topic.id)", "date")
        invalid("anchor.\(topic.id)", Date(timeIntervalSince1970: 1e13))
        invalid("visited.\(topic.id)", 1)
        invalid("visited.custom_missing", true)
        invalid("progress.", 1)
        invalid("unrelated", "must not enter backup")
        invalid("customTopics.v1", "not Data")
        invalid("customTopics.v1", Data("[{]".utf8))
        invalid("customTopics.v1", try! JSONEncoder().encode([topic, topic]))
        invalid("customTopics.v1", try! JSONEncoder().encode([topic, CustomTopicStore.Topic(id: "custom_second", name: " WORK  COMMUNICATION ")]))
        invalid("customTopics.v1", try! JSONEncoder().encode([CustomTopicStore.Topic(id: "work_communication", name: "invalid")]))
        invalid("customTopics.v1", try! JSONEncoder().encode([CustomTopicStore.Topic(id: "custom_empty", name: " ")]))
        invalid("customVocabularyByTopic.v1", try! JSONEncoder().encode([topic.id: [word, word]]))
        invalid("customVocabularyByTopic.v1", try! JSONEncoder().encode(["custom_missing": [word]]))
        for bad in [
            VocabularyWord(text: " ", partOfSpeech: "(n)", meaning: "ok", examples: word.examples),
            VocabularyWord(text: "ok", partOfSpeech: "noun", meaning: "ok", examples: word.examples),
            VocabularyWord(text: "ok", partOfSpeech: "(n)", meaning: " ", examples: word.examples),
            VocabularyWord(text: "ok", partOfSpeech: "(n)", meaning: "ok", examples: ["One."]),
            VocabularyWord(text: "ok", partOfSpeech: "(n)", meaning: "ok", examples: ["", "Two.", "Three.", "Four.", "Five."])
        ] { invalid("customVocabularyByTopic.v1", try! JSONEncoder().encode([topic.id: [bad]])) }
        invalid("schedule.v1", Data("{}".utf8))
        invalid("schedule.v1", try! JSONEncoder().encode(VocabularySchedule(startMinute: 0, endMinute: 0)))
        invalid("studyHistory.v1", try! JSONEncoder().encode([record, record]))
        invalid("studyHistory.v1", try! JSONEncoder().encode([StudyHistoryRecord(topicID: topic.id, wordID: word.text, day: "2026-02-30", studiedAt: date)]))
        invalid("studyHistory.v1", try! JSONEncoder().encode([StudyHistoryRecord(topicID: "custom_missing", wordID: word.text, day: "2026-11-01", studiedAt: date)]))
        invalid("review.v1", Data("{}".utf8))
        invalid("review.v1", try! JSONEncoder().encode(VocabularyReviewState(schemaVersion: 2)))
        invalid("review.v1", try! JSONEncoder().encode(VocabularyReviewState(records: [reviewRecord, reviewRecord])))
        invalid("review.v1", try! JSONEncoder().encode(VocabularyReviewState(attempts: [attempt, attempt])))
        invalid("review.v1", try! JSONEncoder().encode(VocabularyReviewState(records: [.init(identity: identity, stage: 6, dueAt: date.addingTimeInterval(100), reviewedAt: date)])))
        invalid("review.v1", try! JSONEncoder().encode(VocabularyReviewState(records: [.init(identity: identity, stage: 0, dueAt: date, reviewedAt: date)])))
        invalid("review.v1", Data("{\"schemaVersion\":1,\"records\":[],\"attempts\":[{\"id\":\"\(UUID().uuidString)\",\"identity\":{\"topicID\":\"work\",\"wordID\":\"word\"},\"grade\":\"bad\",\"at\":1}]}".utf8))
        for values in invalids {
            var writes = 0
            do { try VocabularyLearningStore.restore(unchecked(values), writer: { _, _ in writes += 1 }); check(false, "invalid snapshot must fail") }
            catch { check(writes == 0 && NSDictionary(dictionary: try! VocabularyLearningStore.rawSnapshot()).isEqual(to: valid), "invalid snapshot rejects before any writes and leaves destination intact") }
        }
        for bad in [unchecked(valid, version: 2), unchecked(valid, at: Date(timeIntervalSince1970: 1e13))] {
            check((try? bad.validatedSnapshot()) == nil, "unknown envelope schema and invalid dates rejected")
        }
        for json in ["", "{", "{}", "{\"schemaVersion\":1}", "{\"schemaVersion\":1,\"createdAt\":0}", "{\"schemaVersion\":1,\"payload\":\"AA==\"}", "{\"schemaVersion\":\"1\",\"createdAt\":0,\"payload\":\"AA==\"}"] {
            check((try? VocabularyLearningStore.decodeBackup(Data(json.utf8))) == nil, "malformed or incomplete envelope rejected")
        }
        let empty = unchecked([:])
        do {
            try VocabularyLearningStore.restore(empty, writer: { _, _ in throw LearningStorageError.writeFailed })
            check(false, "unrecoverable writer failure must report recovery data")
        } catch LearningStorageError.rollbackFailed(let data) {
            let recovered = try! VocabularyLearningStore.decodeBackup(data).validatedSnapshot()
            check(NSDictionary(dictionary: recovered).isEqual(to: valid), "double failure exposes a complete recovery backup")
        } catch { check(false, "double failure must be classified as failed rollback") }
    }

    private static func checkReviewEdges(_ suite: UserDefaults) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let topic = VocabularyCatalog.topic(for: "work_communication")
        let other = VocabularyCatalog.topic(for: "travel")
        suite.set(topic.id, forKey: "selectedTopic")
        func identity(_ index: Int) -> ReviewIdentity { ReviewIdentity(topicID: topic.id, wordID: topic.words[index].text) }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date))!
        let today = calendar.startOfDay(for: date)
        let records = [
            VocabularyReviewRecord(identity: identity(4), stage: 1, dueAt: yesterday, reviewedAt: yesterday.addingTimeInterval(-3600)),
            VocabularyReviewRecord(identity: identity(2), stage: 1, dueAt: yesterday, reviewedAt: yesterday.addingTimeInterval(-3600)),
            VocabularyReviewRecord(identity: identity(1), stage: 1, dueAt: today, reviewedAt: yesterday),
            VocabularyReviewRecord(identity: identity(0), stage: 1, dueAt: date.addingTimeInterval(60), reviewedAt: yesterday),
            VocabularyReviewRecord(identity: .init(topicID: topic.id, wordID: "removed word"), stage: 2, dueAt: yesterday, reviewedAt: yesterday.addingTimeInterval(-3600)),
            VocabularyReviewRecord(identity: .init(topicID: "removed_topic", wordID: "removed word"), stage: 2, dueAt: yesterday, reviewedAt: yesterday.addingTimeInterval(-3600))
        ]
        let attempts = [
            VocabularyReviewAttempt(id: UUID(), identity: identity(2), grade: .remember, at: date),
            VocabularyReviewAttempt(id: UUID(), identity: identity(2), grade: .again, at: date.addingTimeInterval(1)),
            VocabularyReviewAttempt(id: UUID(), identity: .init(topicID: other.id, wordID: other.words[0].text), grade: .remember, at: date),
            VocabularyReviewAttempt(id: UUID(), identity: identity(4), grade: .remember, at: today.addingTimeInterval(-1)),
            VocabularyReviewAttempt(id: UUID(), identity: .init(topicID: "removed_topic", wordID: "word"), grade: .again, at: date)
        ]
        suite.set(try! JSONEncoder().encode(VocabularyReviewState(records: records, attempts: attempts)), forKey: "review.v1")
        var session = VocabularyReviewSession()
        try! session.start(at: date, calendar: calendar)
        check(Array(session.queue.prefix(4)).map(\.text) == [topic.words[2].text, topic.words[4].text, topic.words[1].text, topic.words[3].text], "due ordering uses oldest due date, catalog tie order, then unrated catalog order")
        check(session.queue.count == 10 && Set(session.queue.map(\.text)).count == 10 && session.dueCount == 3, "queue caps at ten distinct identities and ignores stale due words and topics")
        check(session.reviewedToday == 1, "Reviewed Today deduplicates exact topic-word identities only in the selected topic using timestamps in local time")
        try! session.reveal(card: session.cardID, at: date, calendar: calendar)
        try! session.refresh(at: date.addingTimeInterval(61), calendar: calendar)
        check(session.dueCount == 4 && !session.revealed && session.completed == 0, "foreground refresh includes newly due restored dates safely")
        let before = try! VocabularyLearningStore.rawSnapshot()
        var readbacks = 0
        try! session.reveal(card: session.cardID, at: date.addingTimeInterval(61), calendar: calendar)
        do {
            try session.grade(.remember, card: session.cardID, at: date.addingTimeInterval(61), calendar: calendar, reader: {
                readbacks += 1
                if readbacks == 1 { throw LearningStorageError.writeFailed }
                return suite.data(forKey: "review.v1")
            })
            check(false, "grade readback failure is reported")
        } catch { check(session.revealed && session.completed == 0 && session.reviewedToday == 1, "grade readback failure keeps revealed card and prior counters") }
        check(NSDictionary(dictionary: try! VocabularyLearningStore.rawSnapshot()).isEqual(to: before), "grade readback rollback retains all original bytes")
        let backup = try! VocabularyLearningStore.decodeBackup(VocabularyLearningStore.encodeBackup(["selectedTopic": "travel"]))
        try! VocabularyLearningStore.restore(backup)
        try! session.refresh(at: date, calendar: calendar)
        check(session.topicID == "travel" && !session.revealed && session.completed == 0 && session.reviewedToday == 0, "restore while a session exists resets old queue and answer")
        for _ in 0..<10 {
            try! session.reveal(card: session.cardID, at: date, calendar: calendar)
            try! session.grade(.remember, card: session.cardID, at: date, calendar: calendar)
        }
        check(session.queue.isEmpty && session.completed == 10 && session.total == 10 && session.reviewedToday == 10, "session naturally completes after ten accepted actions")
        let completedState = try! VocabularyReviewStore.state(in: VocabularyLearningStore.rawSnapshot())
        check(completedState.records.allSatisfy { $0.dueAt == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) }, "fall-back day grading schedules calendar midnight rather than a 24-hour offset")
        try! session.start(at: date, calendar: calendar)
        check(session.queue.first?.text == other.words[10].text && session.completed == 0 && !session.revealed, "reopening review builds fresh queue and excludes rated future-due cards")
        let empty = CustomTopicStore.Topic(id: "custom_empty", name: "Empty")
        suite.set(try! JSONEncoder().encode([empty]), forKey: "customTopics.v1")
        suite.set(empty.id, forKey: "selectedTopic")
        try! session.refresh(at: date, calendar: calendar)
        check(session.total == 0 && session.queue.isEmpty && !session.revealed, "empty custom topic has a safe empty review")
        suite.set("work_communication", forKey: "selectedTopic")
        try! session.start(at: date, calendar: calendar)
        try! session.reveal(card: session.cardID, at: date, calendar: calendar)
        let broken = Data("invalid".utf8)
        suite.set(broken, forKey: "review.v1")
        do { try session.grade(.again, card: session.cardID, at: date, calendar: calendar); check(false, "corruption after reveal rejects grade") }
        catch { check(session.revealed && session.completed == 0 && suite.data(forKey: "review.v1") == broken, "corruption after reveal does not replace unreadable state or advance counters") }

        suite.removeObject(forKey: "review.v1")
        try! session.start(at: date, calendar: calendar)
        try! session.reveal(card: session.cardID, at: date, calendar: calendar)
        try! session.grade(.remember, card: session.cardID, at: date, calendar: calendar)
        check(session.reviewedToday == 1, "Work grade counts one selected-topic identity")
        suite.set(other.id, forKey: "selectedTopic")
        try! session.refresh(at: date, calendar: calendar)
        check(session.reviewedToday == 0, "switching to unreviewed Travel excludes Work attempts")
        try! session.reveal(card: session.cardID, at: date, calendar: calendar)
        try! session.grade(.again, card: session.cardID, at: date, calendar: calendar)
        check(session.reviewedToday == 1, "Travel Again grade counts only Travel's identity")
        suite.set(topic.id, forKey: "selectedTopic")
        try! session.refresh(at: date, calendar: calendar)
        check(session.reviewedToday == 1, "returning to Work excludes Travel attempts")
        var mixed = try! VocabularyReviewStore.state(in: VocabularyLearningStore.rawSnapshot())
        mixed.attempts.append(contentsOf: [
            .init(id: UUID(), identity: identity(0), grade: .again, at: date.addingTimeInterval(1)),
            .init(id: UUID(), identity: identity(0), grade: .remember, at: date.addingTimeInterval(2)),
            .init(id: UUID(), identity: .init(topicID: topic.id, wordID: "removed word"), grade: .again, at: date),
            .init(id: UUID(), identity: .init(topicID: "removed_topic", wordID: topic.words[0].text), grade: .again, at: date),
            .init(id: UUID(), identity: identity(1), grade: .again, at: today.addingTimeInterval(-1))
        ])
        suite.set(try! JSONEncoder().encode(mixed), forKey: "review.v1")
        try! session.refresh(at: date, calendar: calendar)
        check(session.reviewedToday == 1, "mixed-topic attempts deduplicate Remember and Again and ignore deleted words, topics and prior days")
        try! session.reveal(card: session.cardID, at: date, calendar: calendar)
        let staleCard = session.cardID
        let staleSnapshot = try! VocabularyLearningStore.rawSnapshot()
        let nextDay = calendar.date(byAdding: .day, value: 1, to: today)!
        var staleWrites = 0
        var callbacks = 0
        do {
            try session.grade(.again, card: staleCard, at: nextDay, calendar: calendar, writer: { _ in
                staleWrites += 1
                DispatchQueue.main.async { callbacks += 1 }
            })
            check(false, "day rollover rejects stale grade")
        } catch LearningStorageError.staleSession { check(true, "day rollover rejects stale grade") }
        catch { check(false, "day rollover reports the stale-session error") }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        check(staleWrites == 0 && callbacks == 0 && session.reviewedToday == 1
              && NSDictionary(dictionary: try! VocabularyLearningStore.rawSnapshot()).isEqual(to: staleSnapshot),
              "stale grade leaves counters and persistence unchanged with no callback after draining queued work")
        try! session.refresh(at: nextDay, calendar: calendar)
        check(session.reviewedToday == 0 && !session.revealed && session.cardID != staleCard, "local day rollover resets selected-topic count and hides the stale card")
    }

    private static func checkCustomTopicDeletion(_ suite: UserDefaults) {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let day = WidgetProgressStore.dayKey(for: date, calendar: calendar)
        let selected = try! CustomTopicStore.create(name: "Delete Selected")
        let retained = try! CustomTopicStore.create(name: "Keep This Topic")
        let empty = try! CustomTopicStore.create(name: "Delete Empty")
        let builtIn = VocabularyCatalog.topics[0]
        let examples = ["Example one.", "Example two.", "Example three.", "Example four.", "Example five."]
        func addWord(_ text: String, to topicID: String) {
            try! CustomVocabularyStore.add(text: text, partOfSpeech: "(n)", meaning: "từ thử", examples: examples, to: topicID)
        }
        addWord("selected-only", to: selected.id)
        addWord("retained-word", to: retained.id)
        addWord("built-in-user-word", to: builtIn.id)

        WidgetProgressStore.selectedTopicID = selected.id
        for (topicID, index) in [(selected.id, 4), (retained.id, 2), (builtIn.id, 3)] {
            suite.set(index, forKey: "progress.\(topicID)")
            suite.set(date, forKey: "anchor.\(topicID)")
            suite.set(true, forKey: "visited.\(topicID)")
        }
        let histories = [selected.id, retained.id, builtIn.id].map {
            StudyHistoryRecord(topicID: $0, wordID: "shared-history-word", day: day, studiedAt: date)
        }
        suite.set(try! JSONEncoder().encode(histories), forKey: "studyHistory.v1")
        var review = VocabularyReviewState()
        review.records = [selected.id, retained.id, builtIn.id].map {
            VocabularyReviewRecord(identity: ReviewIdentity(topicID: $0, wordID: "review-word"), stage: 1,
                                   dueAt: date.addingTimeInterval(86_400), reviewedAt: date)
        }
        review.attempts = [selected.id, retained.id, builtIn.id].map {
            VocabularyReviewAttempt(id: UUID(), identity: ReviewIdentity(topicID: $0, wordID: "review-word"), grade: .remember, at: date)
        }
        suite.set(try! JSONEncoder().encode(review), forKey: "review.v1")
        suite.set("preserve", forKey: "unrelated.preference")

        let fallbackID = VocabularyCatalog.topics[0].id
        let newSelection = try! CustomTopicStore.delete(id: selected.id, at: date)
        check(newSelection == fallbackID && WidgetProgressStore.selectedTopicID == fallbackID,
              "deleting the selected custom topic selects the first built-in topic")
        check(CustomTopicStore.topics == [retained, empty], "topic deletion preserves remaining custom topic order")
        check(CustomVocabularyStore.words(for: selected.id).isEmpty
              && CustomVocabularyStore.words(for: retained.id).map(\.text) == ["retained-word"]
              && CustomVocabularyStore.words(for: builtIn.id).map(\.text).contains("built-in-user-word"),
              "topic deletion removes only that topic's words")
        check(suite.object(forKey: "progress.\(selected.id)") == nil
              && suite.object(forKey: "anchor.\(selected.id)") == nil
              && suite.object(forKey: "visited.\(selected.id)") == nil,
              "topic deletion removes its progress, anchor and visited flag")
        check(suite.integer(forKey: "progress.\(retained.id)") == 2
              && suite.integer(forKey: "progress.\(builtIn.id)") == 3
              && suite.object(forKey: "anchor.\(fallbackID)") as? Date == date
              && suite.bool(forKey: "visited.\(fallbackID)"),
              "topic deletion preserves other progress and anchors the fallback")
        let historyAfterDelete = try! JSONDecoder().decode([StudyHistoryRecord].self, from: suite.data(forKey: "studyHistory.v1")!)
        check(historyAfterDelete.map(\.topicID).sorted() == [retained.id, builtIn.id].sorted(),
              "topic deletion removes only its study history")
        let reviewAfterDelete = try! JSONDecoder().decode(VocabularyReviewState.self, from: suite.data(forKey: "review.v1")!)
        check(reviewAfterDelete.records.map(\.identity.topicID).sorted() == [retained.id, builtIn.id].sorted()
              && reviewAfterDelete.attempts.map(\.identity.topicID).sorted() == [retained.id, builtIn.id].sorted(),
              "topic deletion removes only its review records and attempts")
        check(suite.string(forKey: "unrelated.preference") == "preserve", "topic deletion preserves unrelated defaults")
        check((try? VocabularyLearningStore.exportBackup()) != nil, "backup remains valid after deleting a topic")

        let beforeRejectedDelete = suite.dictionaryRepresentation()
        do {
            _ = try CustomTopicStore.delete(id: builtIn.id, at: date)
            check(false, "built-in topic deletion is rejected")
        } catch CustomTopicStore.DeleteError.builtInTopic {
            check(true, "built-in topic deletion is rejected")
        } catch { check(false, "built-in topic deletion reports the correct error") }
        do {
            _ = try CustomTopicStore.delete(id: "custom_missing", at: date)
            check(false, "missing custom topic deletion is rejected")
        } catch CustomTopicStore.DeleteError.notFound {
            check(true, "missing custom topic deletion is rejected")
        } catch { check(false, "missing custom topic deletion reports the correct error") }
        check(NSDictionary(dictionary: suite.dictionaryRepresentation()).isEqual(to: beforeRejectedDelete),
              "rejected built-in and missing topic deletions write nothing")

        let beforeWriteFailure = suite.dictionaryRepresentation()
        var injectedFailure = false
        do {
            _ = try CustomTopicStore.delete(id: retained.id, at: date, writer: { key, value in
                if key == "progress.\(retained.id)" && value == nil && !injectedFailure {
                    injectedFailure = true
                    throw LearningStorageError.writeFailed
                }
                if let value { suite.set(value, forKey: key) }
                else { suite.removeObject(forKey: key) }
            }, reader: {
                suite.dictionaryRepresentation().filter { VocabularyLearningStore.owns($0.key) }
            })
            check(false, "failed topic-delete write is rejected")
        } catch LearningStorageError.writeFailed {
            check(injectedFailure, "failed topic-delete write is rejected")
        } catch { check(false, "failed topic deletion reports a write error") }
        check(NSDictionary(dictionary: suite.dictionaryRepresentation()).isEqual(to: beforeWriteFailure)
              && CustomTopicStore.topics.contains(where: { $0.id == retained.id }),
              "failed topic deletion rolls all saved topic data back")

        let validTopics = suite.data(forKey: "customTopics.v1")!
        let unreadable = Data("broken".utf8)
        suite.set(unreadable, forKey: "customTopics.v1")
        do {
            _ = try CustomTopicStore.delete(id: retained.id, at: date)
            check(false, "topic deletion refuses unreadable source storage")
        } catch LearningStorageError.unreadableStorage {
            check(true, "topic deletion refuses unreadable source storage")
        } catch { check(false, "unreadable topic storage reports the correct error") }
        check(suite.data(forKey: "customTopics.v1") == unreadable, "rejected deletion preserves unreadable topic bytes")
        suite.set(validTopics, forKey: "customTopics.v1")
        _ = try! CustomTopicStore.delete(id: empty.id, at: date)
        check(!CustomTopicStore.topics.contains(where: { $0.id == empty.id }), "empty custom topics can be deleted")
    }

    static func main() {
        let testSuiteID = "VocabularyWidget.ProgressStoreChecks.\(UUID().uuidString)"
        let suite = HistoryTrackingDefaults(suiteName: testSuiteID)!
        let realAppGroupDefaults = UserDefaults(suiteName: WidgetProgressStore.appGroupID)!
        let protectedKey = "VocabularyWidget.ProgressStoreChecks.protected.\(UUID().uuidString)"
        realAppGroupDefaults.set("keep", forKey: protectedKey)
        WidgetProgressStore.testDefaults = suite
        suite.removePersistentDomain(forName: testSuiteID)
        checkWordDetail(suite)
        suite.removePersistentDomain(forName: testSuiteID)
        MainActor.assumeIsolated { checkDetailPresentation(suite) }
        suite.removePersistentDomain(forName: testSuiteID)
        checkBackupCore(suite)
        suite.removePersistentDomain(forName: testSuiteID)
        checkReviewCore(suite)
        suite.removePersistentDomain(forName: testSuiteID)
        checkBackupValidation(suite)
        suite.removePersistentDomain(forName: testSuiteID)
        checkReviewEdges(suite)
        suite.removePersistentDomain(forName: testSuiteID)
        checkCustomTopicDeletion(suite)
        suite.removePersistentDomain(forName: testSuiteID)
        defer {
            suite.removePersistentDomain(forName: testSuiteID)
            WidgetProgressStore.testDefaults = nil
            realAppGroupDefaults.removeObject(forKey: protectedKey)
        }

        let builtInTopics = VocabularyCatalog.topics.prefix(8)
        check(builtInTopics.map(\.id) == ["work_communication", "meetings", "software_development", "project_delivery", "it_support", "travel", "work", "daily"],
              "built-in topic IDs should remain stable")
        check(builtInTopics.map(\.name) == ["Work Communication", "Meetings & Collaboration", "Software Development", "IT Project Management",
                                            "IT Support & Troubleshooting", "Travel", "Basic Work Vocabulary", "Everyday Communication"],
              "built-in topic display names should be English")
        check(builtInTopics.reduce(0) { $0 + $1.words.count } == 400, "built-in catalog should keep 400 words")
        check(builtInTopics[0].words[0].meaning == "đồng nghiệp", "translating topic names should preserve Vietnamese vocabulary meanings")
        for topic in builtInTopics {
            for word in topic.words {
                let cleaned = word.examples.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                check(cleaned.count == 5 && !cleaned.contains("") && Set(cleaned).count == 5,
                      "built-in word \(topic.id)/\(word.text) should have five unique examples")
            }
        }

        check(VocabularyCatalog.topics.count == 8, "topic catalog should contain five IT topics and three existing topics")
        let expectedPartsOfSpeech: Set<String> = ["(n)", "(v)", "(adj)", "(adv)"]
        for topic in VocabularyCatalog.topics {
            check(topic.words.count == 50, "\(topic.id) should contain 50 vocabulary entries")
            for word in topic.words {
                check(expectedPartsOfSpeech.contains(word.partOfSpeech), "\(word.text) should use one of the agreed part-of-speech abbreviations")
                check(!word.meaning.isEmpty && !word.example.isEmpty, "\(word.text) should include a meaning and example")
            }
        }

        let travel = VocabularyCatalog.topic(for: "travel")
        let work = VocabularyCatalog.topic(for: "work")
        let workCommunication = VocabularyCatalog.topic(for: "work_communication")
        let start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_800_000_000))!

        WidgetProgressStore.ensureSelectedTopicInitialized(at: start)
        check(WidgetProgressStore.selectedTopicID == workCommunication.id, "a new install should default to the first IT topic")
        check(!WidgetProgressStore.hasVisited(workCommunication), "initial default should not imply that the learner visited the topic")
        check(WidgetProgressStore.currentIndex(for: workCommunication, at: start) == 0, "the default topic should start at its first word")

        var emptyNameRejected = false
        do { _ = try CustomTopicStore.create(name: "  \n") } catch CustomTopicStore.CreateError.emptyName { emptyNameRejected = true } catch {}
        check(emptyNameRejected, "a custom topic should reject an empty name")
        var duplicateNameRejected = false
        do { _ = try CustomTopicStore.create(name: "  WORK COMMUNICATION ") } catch CustomTopicStore.CreateError.duplicateName { duplicateNameRejected = true } catch {}
        check(duplicateNameRejected, "a custom topic should reject a case-insensitive duplicate built-in name")
        let createdTopic = try! CustomTopicStore.create(name: "  App Systems  ")
        let reloadedTopic = CustomTopicStore.topics.first(where: { $0.id == createdTopic.id })
        check(createdTopic.name == "App Systems" && reloadedTopic == createdTopic, "a custom topic should trim its name and persist a stable ID")
        check(VocabularyCatalog.topic(for: createdTopic.id).words.isEmpty, "a new custom topic should begin empty")
        WidgetProgressStore.selectTopic(VocabularyCatalog.topic(for: createdTopic.id), at: start)
        check(WidgetProgressStore.selectedTopicID == createdTopic.id, "a newly created topic should be selectable by its persistent ID")
        check(WidgetProgressStore.currentIndex(for: VocabularyCatalog.topic(for: createdTopic.id), at: start) == 0, "an empty custom topic should have a safe initial progress index")
        _ = try! CustomVocabularyStore.add(text: "system", partOfSpeech: "(n)", meaning: "hệ thống", examples: ["The system is ready.", "This system is reliable.", "We use a new system.", "The system stores data.", "The system works well."], to: createdTopic.id)
        check(VocabularyCatalog.topic(for: createdTopic.id).words.count == 1, "custom words should attach to the newly created topic")
        check(VocabularyCatalog.topic(for: workCommunication.id).words.count == 50, "creating another topic should not alter the built-in topic vocabulary")
        WidgetProgressStore.selectTopic(workCommunication, at: start.addingTimeInterval(10))

        let customExamples = ["We discussed expectations.", "What are your expectations?", "Set clear expectations.", "My expectation is reasonable.", "The result met expectations."]
        let customWord = try! CustomVocabularyStore.add(text: " alignment ", partOfSpeech: "(n)", meaning: " đồng thuận ", examples: customExamples, to: workCommunication.id)
        check(customWord.text == "alignment" && customWord.meaning == "đồng thuận", "custom word fields should be trimmed")
        check(VocabularyCatalog.topic(for: workCommunication.id).words.count == 51, "custom word should be appended to its topic")
        check(VocabularyCatalog.topic(for: workCommunication.id).words.last?.examples == customExamples, "all five custom examples should persist")
        check(VocabularyCatalog.topic(for: "meetings").words.count == 50, "custom words should not leak into another topic")
        let batch = """
        alignment
        (n)
        đồng thuận
        We need alignment on the plan.
        We reached alignment yesterday.
        The team is aligned.
        Can we align on this?
        I agree with that alignment.

        collaboration
        (n)
        sự hợp tác
        Collaboration helps us deliver.
        We value collaboration.
        The teams work in collaboration.
        Better collaboration saves time.
        Collaboration improved this project.

        COLLABORATION
        (n)
        sự hợp tác
        Collaboration helps us deliver.
        We value collaboration.
        The teams work in collaboration.
        Better collaboration saves time.
        Collaboration improved this project.

        malformed
        (n)
        thiếu ví dụ
        Only one example.
        """.replacingOccurrences(of: "\n", with: "\r\n")
        let batchResult = try! CustomVocabularyStore.addBatch(batch, to: workCommunication.id)
        check(batchResult.added.map(\.text) == ["collaboration"], "batch import should add valid unique words and reject duplicates")
        check(batchResult.issues.count == 3 && batchResult.issues[0].block == 1 && batchResult.issues[1].block == 3 && batchResult.issues[2].block == 4, "batch import should report existing, malformed, and in-batch duplicate blocks by number")
        check(VocabularyCatalog.topic(for: workCommunication.id).words.last?.examples.count == 5, "batch imported entries should retain all five examples")
        do {
            try CustomVocabularyStore.add(text: "ALIGNMENT", partOfSpeech: "(n)", meaning: "đồng thuận", examples: customExamples, to: workCommunication.id)
            check(false, "normalized duplicate should be rejected")
        } catch CustomVocabularyStore.AddError.duplicate {
            check(true, "normalized duplicate should be rejected")
        } catch {
            check(false, "duplicate should report the duplicate error")
        }
        do {
            try CustomVocabularyStore.add(text: "unfilled", partOfSpeech: "(n)", meaning: "chưa điền", examples: Array(customExamples.prefix(4)), to: workCommunication.id)
            check(false, "custom words with fewer than five examples should be rejected")
        } catch CustomVocabularyStore.AddError.invalidExamples {
            check(true, "custom words with fewer than five examples should be rejected")
        } catch {
            check(false, "missing examples should report the validation error")
        }
        check(WidgetProgressStore.currentIndex(for: VocabularyCatalog.topic(for: workCommunication.id), at: start) == 0, "adding a word should preserve current position and anchor")

        suite.removePersistentDomain(forName: testSuiteID)
        WidgetProgressStore.selectedTopicID = travel.id
        WidgetProgressStore.ensureSelectedTopicInitialized(at: start)
        check(WidgetProgressStore.selectedTopicID == travel.id, "a saved topic should remain selected after adding new topics")
        check(!WidgetProgressStore.hasVisited(travel), "initial default should not imply that the learner visited the topic")
        check(WidgetProgressStore.currentIndex(for: travel, at: start) == 0, "a new topic should start at its first word")
        check(WidgetProgressStore.currentIndex(for: travel, at: start.addingTimeInterval(299)) == 0, "word should remain for five minutes")
        check(WidgetProgressStore.currentIndex(for: travel, at: start.addingTimeInterval(300)) == 1, "word should advance at five minutes")
        let firstSelection = start
        WidgetProgressStore.selectTopic(travel, at: firstSelection)
        check(WidgetProgressStore.currentIndex(for: travel, at: firstSelection) == 0, "reselecting the default topic at its anchor should preserve word one")
        check(WidgetProgressStore.currentIndex(for: travel, at: firstSelection.addingTimeInterval(299)) == 0, "first selected word should remain for five minutes")
        check(WidgetProgressStore.currentIndex(for: travel, at: firstSelection.addingTimeInterval(300)) == 1, "the first selected word should advance after five minutes")
        check(WidgetProgressStore.secondsUntilNextChange(for: travel, at: firstSelection.addingTimeInterval(299)) == 1, "the app countdown should show one second at the interval boundary")
        check(WidgetProgressStore.secondsUntilNextChange(for: travel, at: firstSelection.addingTimeInterval(300)) == 300, "the app countdown should restart after the word advances")
        WidgetProgressStore.selectTopic(travel, at: firstSelection.addingTimeInterval(100))
        check(WidgetProgressStore.nextChange(after: firstSelection.addingTimeInterval(100), for: travel) == firstSelection.addingTimeInterval(300), "reselecting an active topic should not reset its timer")
        let nearBoundary = firstSelection.addingTimeInterval(299)
        check(WidgetProgressStore.nextChange(after: nearBoundary, for: travel).timeIntervalSince(WidgetProgressStore.currentEntryDate(for: travel, at: nearBoundary)) == 1, "the current snapshot should lead to the next tick in one second")
        let schedule = VocabularyTimelineSchedule.make(for: travel, at: nearBoundary)
        check(schedule.count == VocabularyTimelineSchedule.futureEntryCount + 1, "the timeline should contain the current word and a day of future entries")
        check(schedule[0].index == 0 && schedule[1].index == 1, "the schedule should begin with the current word then advance")
        for pair in zip(schedule, schedule.dropFirst()) {
            check(pair.1.date == WidgetProgressStore.nextChange(after: pair.0.date, for: travel), "scheduled entries should follow the active-window tick function")
        }

        let switchedAt = firstSelection.addingTimeInterval(600)
        WidgetProgressStore.selectTopic(work, at: switchedAt)
        check(suite.integer(forKey: "progress.travel") == 2, "switching topics should save the current position")
        check(WidgetProgressStore.currentIndex(for: travel, at: switchedAt.addingTimeInterval(3_000)) == 2, "an inactive topic should stay paused while another topic is selected")
        check(WidgetProgressStore.hasVisited(work), "choosing a topic should save that it was visited")
        check(WidgetProgressStore.currentIndex(for: work, at: switchedAt) == 0, "a newly selected topic should start at its first word")
        check(WidgetProgressStore.currentIndex(for: work, at: switchedAt.addingTimeInterval(299)) == 0, "a newly selected topic should get a full first interval")
        check(WidgetProgressStore.currentIndex(for: work, at: switchedAt.addingTimeInterval(300)) == 1, "a newly selected topic should advance after five minutes")
        let resumedAt = switchedAt.addingTimeInterval(3_000)
        WidgetProgressStore.selectTopic(travel, at: resumedAt)
        check(WidgetProgressStore.currentIndex(for: travel, at: resumedAt) == 2, "returning to a topic should resume its saved position")
        check(suite.integer(forKey: "progress.work") == 10, "progress for another topic should be saved independently")
        check(WidgetProgressStore.currentIndex(for: travel, at: resumedAt.addingTimeInterval(300)) == 3, "resumed progress should continue on the five-minute cadence")
        check(WidgetProgressStore.nextChange(after: resumedAt, for: travel) == resumedAt.addingTimeInterval(300), "next-change time should follow the resumed anchor")
        let tappedAt = resumedAt.addingTimeInterval(300)
        check(WidgetProgressStore.advanceDisplayedWord(topicID: travel.id, displayedIndex: 1, at: tappedAt), "the next-word action should accept the displayed topic")
        check(WidgetProgressStore.currentIndex(for: travel, at: tappedAt) == 2, "manual next should advance from the displayed word rather than skip a stale timed entry")
        let regularTapAt = tappedAt.addingTimeInterval(100)
        WidgetProgressStore.advanceSelectedTopic(at: regularTapAt)
        check(WidgetProgressStore.currentIndex(for: travel, at: regularTapAt) == 3, "the next-word action should advance and save progress")
        check(WidgetProgressStore.currentIndex(for: travel, at: regularTapAt.addingTimeInterval(300)) == 4, "manual advance should restart the five-minute dwell for that word")
        for _ in 0..<(travel.words.count - 4) {
            WidgetProgressStore.advanceSelectedTopic(at: regularTapAt)
        }
        check(WidgetProgressStore.currentIndex(for: travel, at: regularTapAt) == travel.words.count - 1, "manual advance should reach the final word")
        WidgetProgressStore.advanceSelectedTopic(at: regularTapAt)
        check(WidgetProgressStore.currentIndex(for: travel, at: regularTapAt) == 0, "manual advance should wrap from the last word to the first")
        for _ in 0..<(travel.words.count - 1) {
            WidgetProgressStore.advanceSelectedTopic(at: regularTapAt)
        }
        let wrapSchedule = VocabularyTimelineSchedule.make(for: travel, at: regularTapAt)
        check(wrapSchedule[0].index == travel.words.count - 1 && wrapSchedule[1].index == 0, "the timed timeline should wrap after the final word too")

        let mismatchAt = regularTapAt.addingTimeInterval(600)
        WidgetProgressStore.selectTopic(work, at: mismatchAt)
        let workBeforeStaleIntent = WidgetProgressStore.currentIndex(for: work, at: mismatchAt)
        check(!WidgetProgressStore.advanceDisplayedWord(topicID: travel.id, displayedIndex: 5, at: mismatchAt.addingTimeInterval(1)), "a stale widget action should be rejected after the selected topic changes")
        check(WidgetProgressStore.currentIndex(for: work, at: mismatchAt.addingTimeInterval(1)) == workBeforeStaleIntent, "a stale card must not advance the newly selected topic")
        WidgetProgressStore.resetProgress(for: travel, at: mismatchAt.addingTimeInterval(10))
        check(WidgetProgressStore.currentIndex(for: travel, at: mismatchAt.addingTimeInterval(10)) == 0, "resetting an inactive topic should clear only that topic's position")
        check(WidgetProgressStore.currentIndex(for: work, at: mismatchAt.addingTimeInterval(10)) == workBeforeStaleIntent, "resetting an inactive topic should leave the selected topic untouched")

        WidgetProgressStore.selectedTopicID = "missing-topic"
        WidgetProgressStore.ensureSelectedTopicInitialized(at: resumedAt)
        check(WidgetProgressStore.selectedTopicID == workCommunication.id, "an unknown saved topic should recover to the first available topic")
        let emptyTopic = VocabularyTopic(id: "empty", name: "Empty", words: [])
        check(WidgetProgressStore.currentIndex(for: emptyTopic, at: resumedAt) == 0, "an empty topic should not produce a negative or invalid index")
        check(realAppGroupDefaults.string(forKey: protectedKey) == "keep", "progress checks should not mutate the real App Group suite")

        WidgetProgressStore.selectedTopicID = travel.id
        suite.set(Int.max, forKey: "progress.travel")
        suite.set(resumedAt, forKey: "anchor.travel")
        check(WidgetProgressStore.currentIndex(for: travel, at: resumedAt.addingTimeInterval(300)) == 0, "an out-of-range saved position should be clamped before timed advancement")
        suite.set(Int.min, forKey: "progress.travel")
        check(WidgetProgressStore.currentIndex(for: travel, at: resumedAt) == 0, "a negative corrupt saved position should recover to the first word")
        suite.set(Date(timeIntervalSince1970: -Double.greatestFiniteMagnitude), forKey: "anchor.travel")
        check((0..<travel.words.count).contains(WidgetProgressStore.currentIndex(for: travel, at: Date(timeIntervalSince1970: Double.greatestFiniteMagnitude))), "extreme clock values should not create an invalid array index")
        let extremeAnchorNext = WidgetProgressStore.nextChange(after: resumedAt, for: travel)
        let extremeAnchorCurrent = WidgetProgressStore.currentEntryDate(for: travel, at: resumedAt)
        check(extremeAnchorNext.timeIntervalSince(extremeAnchorCurrent) == WidgetProgressStore.interval, "an extreme but finite old anchor should still produce a valid timeline interval")
        suite.set(resumedAt.addingTimeInterval(600), forKey: "anchor.travel")
        let afterClockRollback = WidgetProgressStore.currentEntryDate(for: travel, at: resumedAt)
        check(afterClockRollback == resumedAt, "a future anchor after the device clock moves backward should be repaired")
        check(WidgetProgressStore.nextChange(after: resumedAt, for: travel) == resumedAt.addingTimeInterval(300), "clock rollback should restart a full five-minute interval")

        suite.removePersistentDomain(forName: testSuiteID)
        WidgetProgressStore.selectedTopicID = travel.id
        let passiveStart = start.addingTimeInterval(10_000)
        WidgetProgressStore.ensureSelectedTopicInitialized(at: passiveStart)
        let switchAfterWidgetUse = passiveStart.addingTimeInterval(900)
        WidgetProgressStore.selectTopic(work, at: switchAfterWidgetUse)
        check(WidgetProgressStore.hasVisited(travel), "leaving the default topic after widget use should mark its progress as started")
        check(suite.integer(forKey: "progress.travel") == 3, "leaving the saved topic should save its elapsed position")
        let switchBackAt = switchAfterWidgetUse.addingTimeInterval(6_000)
        WidgetProgressStore.selectTopic(travel, at: switchBackAt)
        check(WidgetProgressStore.currentIndex(for: travel, at: switchBackAt) == 3, "returning to a passively started topic should preserve rather than reset its position")
        let resetAt = switchBackAt.addingTimeInterval(100)
        WidgetProgressStore.resetProgress(for: travel, at: resetAt)
        check(WidgetProgressStore.currentIndex(for: travel, at: resetAt) == 0, "an explicit topic reset should return to the first word")
        check(WidgetProgressStore.currentIndex(for: travel, at: resetAt.addingTimeInterval(299)) == 0, "a reset should restart the five-minute dwell")
        check(WidgetProgressStore.currentIndex(for: travel, at: resetAt.addingTimeInterval(300)) == 1, "a reset topic should resume the normal cadence")

        suite.removePersistentDomain(forName: testSuiteID)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let historyStart = ISO8601DateFormatter().date(from: "2024-01-01T01:30:00Z")!
        WidgetProgressStore.selectTopic(travel, at: historyStart)
        WidgetProgressStore.resetProgress(for: travel, at: historyStart)
        check(WidgetProgressStore.markStudiedAndAdvance(topicID: travel.id, displayedIndex: 0, at: historyStart, calendar: utcCalendar), "mark studied should accept the selected nonempty topic")
        check(WidgetProgressStore.allStudyHistory().count == 1, "a normal studied tap should create exactly one record")
        let firstHistoryRecord = WidgetProgressStore.allStudyHistory().first
        check(firstHistoryRecord?.topicID == travel.id && firstHistoryRecord?.wordID == travel.words[0].text, "study history should store the selected topic and displayed word text")
        check(firstHistoryRecord?.day == "2024-01-01" && firstHistoryRecord?.studiedAt == historyStart, "study history should store the injected local day key and tap date")
        check(WidgetProgressStore.currentIndex(for: travel, at: historyStart) == 1, "mark studied should advance from the displayed word")
        check(suite.object(forKey: "anchor.\(travel.id)") as? Date == historyStart, "mark studied should restart the five-minute timer at the tap")
        check(WidgetProgressStore.currentIndex(for: travel, at: historyStart.addingTimeInterval(299)) == 1, "marked word should remain for 299 seconds")
        check(WidgetProgressStore.currentIndex(for: travel, at: historyStart.addingTimeInterval(300)) == 2, "marked word should continue the 300-second cadence")
        check(WidgetProgressStore.dayKey(for: historyStart, calendar: utcCalendar) == "2024-01-01", "day keys should use fixed numeric formatting")
        var newYorkCalendar = utcCalendar
        newYorkCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        check(WidgetProgressStore.dayKey(for: historyStart, calendar: newYorkCalendar) == "2023-12-31", "day keys should use the injected local time zone")

        for identifier in [Calendar.Identifier.buddhist, .japanese] {
            var nonGregorianCalendar = Calendar(identifier: identifier)
            nonGregorianCalendar.timeZone = newYorkCalendar.timeZone
            check(WidgetProgressStore.dayKey(for: historyStart, calendar: nonGregorianCalendar) == "2023-12-31", "non-Gregorian calendars should still produce the Gregorian local day")
            check(WidgetProgressStore.markStudiedAndAdvance(topicID: travel.id, displayedIndex: 2, at: historyStart, calendar: nonGregorianCalendar), "studied taps should accept an injected non-Gregorian calendar")
            check(WidgetProgressStore.studyHistory(forDay: "2023-12-31").count == 1, "stored Gregorian local days should deduplicate across calendar identifiers")
        }
        // Keep the later history checks focused on the original UTC record.
        suite.set(try! JSONEncoder().encode([firstHistoryRecord!]), forKey: "studyHistory.v1")
        let beforeNext = WidgetProgressStore.allStudyHistory().count
        suite.historyReads = 0
        suite.historyWrites = 0
        check(WidgetProgressStore.advanceDisplayedWord(topicID: travel.id, displayedIndex: 1, at: historyStart.addingTimeInterval(1)), "the ordinary next action should still advance")
        check(suite.historyReads == 0 && suite.historyWrites == 0, "ordinary next must not read or write history")
        check(WidgetProgressStore.allStudyHistory().count == beforeNext, "ordinary next must not record study history")
        check(WidgetProgressStore.markStudiedAndAdvance(topicID: travel.id, displayedIndex: 0, at: historyStart.addingTimeInterval(60), calendar: utcCalendar), "repeat marking should remain an accepted action")
        check(WidgetProgressStore.allStudyHistory().count == 1, "the same word should be deduplicated within a local day")
        check(WidgetProgressStore.currentIndex(for: travel, at: historyStart.addingTimeInterval(60)) == 1, "same-day deduplication should still advance from the displayed word")
        check(suite.object(forKey: "anchor.travel") as? Date == historyStart.addingTimeInterval(60), "same-day deduplication should restart the anchor at tap time")
        let nextDay = historyStart.addingTimeInterval(86_400)
        check(WidgetProgressStore.markStudiedAndAdvance(topicID: travel.id, displayedIndex: 0, at: nextDay, calendar: utcCalendar), "the same word should be markable on another day")
        check(WidgetProgressStore.allStudyHistory().count == 2, "a new local day should create a separate record")
        check(WidgetProgressStore.studiedWordIDs(for: travel.id) == [travel.words[0].text] && WidgetProgressStore.studiedWordCount(for: travel.id) == 1, "distinct topic counts should not count duplicate days")
        check(WidgetProgressStore.studyHistory(forDay: "2024-01-02").count == 1, "history should be queryable by local day key")
        check(WidgetProgressStore.studyHistory(from: nextDay, through: nextDay).count == 1, "history should be queryable by an inclusive date range")

        let historyBeforeReset = WidgetProgressStore.allStudyHistory()
        WidgetProgressStore.resetProgress(for: travel, at: nextDay.addingTimeInterval(100))
        check(WidgetProgressStore.allStudyHistory() == historyBeforeReset, "resetting progress must preserve study history")
        let historyBeforeStale = WidgetProgressStore.allStudyHistory()
        WidgetProgressStore.selectTopic(work, at: nextDay.addingTimeInterval(200))
        let beforeStaleState = suite.dictionaryRepresentation() as NSDictionary
        suite.historyWrites = 0
        check(!WidgetProgressStore.markStudiedAndAdvance(topicID: travel.id, displayedIndex: 0, at: nextDay.addingTimeInterval(199), calendar: utcCalendar), "a stale topic mark should be rejected even before the active anchor")
        check(suite.historyWrites == 0, "a stale topic must not write history")
        check(suite.dictionaryRepresentation() as NSDictionary == beforeStaleState, "a stale studied tap must not change any persisted state")
        check(WidgetProgressStore.allStudyHistory() == historyBeforeStale, "a stale topic must not add study history")

        let customHistoryTopic = try! CustomTopicStore.create(name: "History Tests")
        let customHistoryWord = try! CustomVocabularyStore.add(text: "retrospective", partOfSpeech: "(n)", meaning: "buổi nhìn lại", examples: Array(customExamples.prefix(5)), to: customHistoryTopic.id)
        WidgetProgressStore.selectTopic(VocabularyCatalog.topic(for: customHistoryTopic.id), at: nextDay.addingTimeInterval(300))
        check(WidgetProgressStore.markStudiedAndAdvance(topicID: customHistoryTopic.id, displayedIndex: 0, at: nextDay.addingTimeInterval(301), calendar: utcCalendar), "custom topics and words should support study history")
        check(WidgetProgressStore.studiedWordIDs(for: customHistoryTopic.id) == [customHistoryWord.text], "custom vocabulary should be recorded by word text")

        let emptyHistoryTopic = try! CustomTopicStore.create(name: "Empty History Tests")
        WidgetProgressStore.selectTopic(VocabularyCatalog.topic(for: emptyHistoryTopic.id), at: nextDay.addingTimeInterval(400))
        let beforeEmptyMark = WidgetProgressStore.allStudyHistory().count
        check(!WidgetProgressStore.markStudiedAndAdvance(topicID: emptyHistoryTopic.id, displayedIndex: 0, at: nextDay.addingTimeInterval(401), calendar: utcCalendar), "an empty topic should reject the studied action")
        check(WidgetProgressStore.allStudyHistory().count == beforeEmptyMark, "an empty topic must not add study history")

        WidgetProgressStore.selectTopic(travel, at: nextDay.addingTimeInterval(500))
        check(WidgetProgressStore.markStudiedAndAdvance(topicID: travel.id, displayedIndex: travel.words.count - 1, at: nextDay.addingTimeInterval(501), calendar: utcCalendar), "mark studied should accept the final displayed word")
        check(WidgetProgressStore.currentIndex(for: travel, at: nextDay.addingTimeInterval(501)) == 0, "mark studied should wrap after the final word")

        check(suite.object(forKey: "anchor.travel") as? Date == nextDay.addingTimeInterval(501), "a wrapping studied tap should restart the anchor at tap time")

        for invalidIndex in [-1, travel.words.count, Int.min, Int.max] {
            let beforeInvalidIndex = suite.dictionaryRepresentation() as NSDictionary
            suite.historyWrites = 0
            check(!WidgetProgressStore.markStudiedAndAdvance(topicID: travel.id, displayedIndex: invalidIndex, at: nextDay, calendar: utcCalendar), "studied taps should reject out-of-range displayed indexes")
            check(suite.historyWrites == 0 && suite.dictionaryRepresentation() as NSDictionary == beforeInvalidIndex, "an invalid displayed index must not write history or progress")
        }

        for corruptHistory in [Data("not JSON".utf8), Data("{}".utf8), Data("[{\"topicID\":\"travel\"}]".utf8)] {
            suite.set(corruptHistory, forKey: "studyHistory.v1")
            suite.set(7, forKey: "progress.travel")
            suite.set(nextDay.addingTimeInterval(600), forKey: "anchor.travel")
            suite.set(false, forKey: "visited.travel")
            let beforeCorruptMark = suite.dictionaryRepresentation() as NSDictionary
            suite.historyWrites = 0
            check(!WidgetProgressStore.markStudiedAndAdvance(topicID: travel.id, displayedIndex: 7, at: nextDay, calendar: utcCalendar), "malformed history should reject studied taps")
            check(suite.historyWrites == 0, "malformed history must not be overwritten")
            check(suite.data(forKey: "studyHistory.v1") == corruptHistory, "malformed history bytes must be preserved byte-for-byte")
            check(suite.dictionaryRepresentation() as NSDictionary == beforeCorruptMark, "rejected malformed history must preserve index, future anchor, visited and selected state")
            check(WidgetProgressStore.allStudyHistory().isEmpty, "read-only queries may return empty history for malformed data")
            check(suite.dictionaryRepresentation() as NSDictionary == beforeCorruptMark, "read-only history queries must preserve malformed bytes and progress")
        }

        let corruptHistoryBeforeNext = suite.data(forKey: "studyHistory.v1")
        suite.historyReads = 0
        suite.historyWrites = 0
        let nextWrapAt = nextDay.addingTimeInterval(700)
        check(WidgetProgressStore.advanceDisplayedWord(topicID: travel.id, displayedIndex: travel.words.count - 1, at: nextWrapAt), "Next should still accept and wrap with corrupt history")
        check(suite.historyReads == 0 && suite.historyWrites == 0, "Next wrapping must not read or write malformed history")
        check(suite.integer(forKey: "progress.travel") == 0 && suite.object(forKey: "anchor.travel") as? Date == nextWrapAt, "Next wrap should preserve its progress and tap-time anchor behavior")
        check(suite.data(forKey: "studyHistory.v1") == corruptHistoryBeforeNext, "Next must preserve malformed history bytes")
        let beforeStaleNext = suite.dictionaryRepresentation() as NSDictionary
        suite.historyReads = 0
        suite.historyWrites = 0
        check(!WidgetProgressStore.advanceDisplayedWord(topicID: work.id, displayedIndex: 0, at: nextWrapAt.addingTimeInterval(1)), "Next should still reject stale topics with corrupt history")
        check(suite.historyReads == 0 && suite.historyWrites == 0, "stale Next must not read or write history")
        check(suite.dictionaryRepresentation() as NSDictionary == beforeStaleNext, "stale Next should preserve initialized progress")
        check(WidgetProgressStore.advanceDisplayedWord(topicID: travel.id, displayedIndex: -1, at: nextWrapAt), "Next should retain displayed-index normalization")
        check(suite.integer(forKey: "progress.travel") == 0, "Next should normalize minus one to the final word and wrap")

        checkPreviousReleaseRetention()

        for unreadable in [Data("not JSON".utf8) as Any, Data("[{}]".utf8), "legacy storage"] {
            suite.removePersistentDomain(forName: testSuiteID)
            suite.set(unreadable, forKey: "customTopics.v1")
            suite.set("custom_previous_release", forKey: "selectedTopic")
            suite.set(3, forKey: "progress.custom_previous_release")
            suite.set(nextDay, forKey: "anchor.custom_previous_release")
            let beforeStartup = suite.dictionaryRepresentation() as NSDictionary
            WidgetProgressStore.ensureSelectedTopicInitialized(at: nextDay)
            check(suite.dictionaryRepresentation() as NSDictionary == beforeStartup, "startup must not replace selection or state when the custom topic catalog is unreadable")
            do {
                _ = try CustomTopicStore.create(name: "Another topic")
                check(false, "creating a topic must reject unreadable existing storage")
            } catch CustomTopicStore.CreateError.storageFailure {
                check(true, "unreadable topic storage should report storageFailure")
            } catch { check(false, "unreadable topic storage should report storageFailure") }
            check(suite.dictionaryRepresentation() as NSDictionary == beforeStartup, "creating a topic must preserve unreadable storage and state")

            suite.removeObject(forKey: "customTopics.v1")
            suite.set(unreadable, forKey: "customVocabularyByTopic.v1")
            let beforeAdd = suite.dictionaryRepresentation() as NSDictionary
            do {
                _ = try CustomVocabularyStore.add(text: "retention", partOfSpeech: "(n)", meaning: "retention", examples: customExamples, to: travel.id)
                check(false, "adding a word must reject unreadable existing storage")
            } catch CustomVocabularyStore.AddError.storageFailure {
                check(true, "unreadable vocabulary storage should report storageFailure")
            } catch { check(false, "unreadable vocabulary storage should report storageFailure") }
            do {
                _ = try CustomVocabularyStore.addBatch("retention\n(n)\nretention\nOne.\nTwo.\nThree.\nFour.\nFive.", to: travel.id)
                check(false, "batch import must reject unreadable existing storage")
            } catch CustomVocabularyStore.AddError.storageFailure {
                check(true, "unreadable batch storage should report storageFailure")
            } catch { check(false, "unreadable batch storage should report storageFailure") }
            check(suite.dictionaryRepresentation() as NSDictionary == beforeAdd, "single and batch additions must preserve unreadable storage byte-for-byte")

            suite.set(unreadable, forKey: "schedule.v1")
            let beforeScheduleEdit = suite.dictionaryRepresentation() as NSDictionary
            var replacementSchedule = VocabularySchedule()
            replacementSchedule.intervalMinutes = 7
            check(!WidgetProgressStore.updateSchedule(replacementSchedule, at: nextDay), "schedule edits must reject unreadable existing schedule storage")
            check(suite.dictionaryRepresentation() as NSDictionary == beforeScheduleEdit, "rejected schedule edits must preserve stored bytes, progress and anchors")
        }

        print("Progress checks passed (\(checksPassed) checks).")
    }

    private static func checkPreviousReleaseRetention() {
        let suiteID = "VocabularyWidget.RetentionChecks.\(UUID().uuidString)"
        let previousDefaults = WidgetProgressStore.testDefaults
        let seeded = UserDefaults(suiteName: suiteID)!
        defer {
            seeded.removePersistentDomain(forName: suiteID)
            WidgetProgressStore.testDefaults = previousDefaults
        }
        let topicsData = Data("""
        [{"id":"custom_previous_release","name":"My systems"},{"id":"custom_other","name":"My meetings"}]
        """.utf8)
        let wordsData = Data("""
        {
          "custom_previous_release":[
            {"text":"retention","partOfSpeech":"(n)","meaning":"saved meaning","examples":["First.","Second.","Third.","Fourth.","Fifth."]},
            {"text":"persist","partOfSpeech":"(v)","meaning":"keep data","examples":["Save one.","Save two.","Save three.","Save four.","Save five."]}
          ],
          "custom_other":[{"text":"review","partOfSpeech":"(v)","meaning":"user meaning","examples":["Review one.","Review two.","Review three.","Review four.","Review five."]}],
          "work_communication":[{"text":"colleague","partOfSpeech":"(n)","meaning":"user-authored colleague meaning","examples":["Custom one.","Custom two.","Custom three.","Custom four.","Custom five."]}]
        }
        """.utf8)
        let scheduleData = Data("""
        {"startMinute":450,"endMinute":1410,"intervalMinutes":11,"notificationsEnabled":true}
        """.utf8)
        let historyData = Data("""
        [{"topicID":"custom_previous_release","wordID":"retention","day":"2026-10-31","studiedAt":815184000}]
        """.utf8)
        let startupDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture: [String: Any] = [
            "customTopics.v1": topicsData,
            "customVocabularyByTopic.v1": wordsData,
            "selectedTopic": "custom_previous_release",
            "progress.custom_previous_release": 1,
            "anchor.custom_previous_release": startupDate.addingTimeInterval(-60),
            "visited.custom_previous_release": true,
            "progress.custom_other": 0,
            "anchor.custom_other": startupDate.addingTimeInterval(-120),
            "visited.custom_other": true,
            "progress.work_communication": 50,
            "anchor.work_communication": startupDate.addingTimeInterval(-180),
            "visited.work_communication": true,
            "schedule.v1": scheduleData,
            "studyHistory.v1": historyData,
            "retention.unrelatedPreference": "keep this preference"
        ]
        seeded.setPersistentDomain(fixture, forName: suiteID)
        check(seeded.synchronize(), "previous-release fixture must be flushed before reopening")
        let expectedTopics = try! JSONDecoder().decode([CustomTopicStore.Topic].self, from: topicsData)
        let expectedWords = try! JSONDecoder().decode([String: [VocabularyWord]].self, from: wordsData)
        let expectedHistory = try! JSONDecoder().decode([StudyHistoryRecord].self, from: historyData)
        let expectedSchedule = try! JSONDecoder().decode(VocabularySchedule.self, from: scheduleData)

        for _ in 0..<2 {
            let reopened = UserDefaults(suiteName: suiteID)!
            WidgetProgressStore.testDefaults = reopened
            let backup = try! VocabularyLearningStore.decodeBackup(VocabularyLearningStore.exportBackup(at: startupDate))
            let expectedOwned = fixture.filter { VocabularyLearningStore.owns($0.key) }
            check(NSDictionary(dictionary: try! backup.validatedSnapshot()).isEqual(to: expectedOwned), "previous-release backup retains every owned key and exact JSON bytes including bundled-word collisions")
            try! VocabularyLearningStore.restore(backup)
            WidgetProgressStore.ensureSelectedTopicInitialized(at: startupDate)
            check(reopened.persistentDomain(forName: suiteID)! as NSDictionary == fixture as NSDictionary, "reopening and startup must preserve every previous-release persisted field without clearing")
            check(CustomTopicStore.topics == expectedTopics, "previous-release topic IDs, names and order must survive startup")
            for (topicID, words) in expectedWords {
                check(CustomVocabularyStore.words(for: topicID) == words, "previous-release words, all fields, five examples and order must survive for \(topicID)")
                check(Array(VocabularyCatalog.topic(for: topicID).words.suffix(words.count)) == words, "built-in catalog merges must append rather than overwrite custom words for \(topicID)")
            }
            check(WidgetProgressStore.currentIndex(for: VocabularyCatalog.topic(for: "custom_previous_release"), at: startupDate) == 1, "startup must resume the selected custom topic's saved position")
            check(WidgetProgressStore.currentIndex(for: VocabularyCatalog.topic(for: "work_communication"), at: startupDate) == 50, "startup must retain built-in topic additions and their saved position")
            check(WidgetProgressStore.allStudyHistory() == expectedHistory && WidgetProgressStore.schedule == expectedSchedule, "previous-release history and schedule preferences must remain readable")
        }

        let addedTopic = try! CustomTopicStore.create(name: "After update")
        let addedWord = try! CustomVocabularyStore.add(text: "coexist", partOfSpeech: "(v)", meaning: "coexist", examples: ["One.", "Two.", "Three.", "Four.", "Five."], to: "custom_previous_release")
        let batch = try! CustomVocabularyStore.addBatch("append\n(v)\nappend\nOne.\nTwo.\nThree.\nFour.\nFive.", to: "work_communication")
        check(WidgetProgressStore.testDefaults!.synchronize(), "subsequent additions must be flushed before reopening")
        let reopened = UserDefaults(suiteName: suiteID)!
        WidgetProgressStore.testDefaults = reopened
        WidgetProgressStore.ensureSelectedTopicInitialized(at: startupDate)
        check(CustomTopicStore.topics == expectedTopics + [addedTopic], "new topics must coexist with previous-release IDs, names and order")
        check(CustomVocabularyStore.words(for: "custom_previous_release") == expectedWords["custom_previous_release"]! + [addedWord], "new words must append without replacing previous-release fields or order")
        check(CustomVocabularyStore.words(for: "work_communication") == expectedWords["work_communication"]! + batch.added && batch.added.count == 1, "batch additions to built-in topics must retain previous-release user words")
        check(CustomVocabularyStore.words(for: "custom_other") == expectedWords["custom_other"]!, "additions must not replace another custom topic's words")
        var expectedAfterAdditions = fixture
        expectedAfterAdditions["customTopics.v1"] = reopened.data(forKey: "customTopics.v1")
        expectedAfterAdditions["customVocabularyByTopic.v1"] = reopened.data(forKey: "customVocabularyByTopic.v1")
        check(reopened.persistentDomain(forName: suiteID)! as NSDictionary == expectedAfterAdditions as NSDictionary, "additions and later startup must preserve selection, all progress, anchors, history, schedule and unrelated preferences")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checksPassed += 1
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}

private final class HistoryTrackingDefaults: UserDefaults {
    var historyReads = 0
    var historyWrites = 0

    override func object(forKey defaultName: String) -> Any? {
        if defaultName == "studyHistory.v1" { historyReads += 1 }
        return super.object(forKey: defaultName)
    }

    override func data(forKey defaultName: String) -> Data? {
        if defaultName == "studyHistory.v1" { historyReads += 1 }
        return super.data(forKey: defaultName)
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        if defaultName == "studyHistory.v1" { historyWrites += 1 }
        super.set(value, forKey: defaultName)
    }
}
