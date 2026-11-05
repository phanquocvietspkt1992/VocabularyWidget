import Foundation

@main
struct SentenceGameChecks {
    static var count = 0
    static func check(_ value: Bool, _ message: String) {
        precondition(value, message)
        count += 1
    }
    static func rejects(_ message: String, expected: SentenceGameError? = nil, _ action: () throws -> Void) {
        do { try action(); fatalError(message) } catch {
            if let expected { check(error as? SentenceGameError == expected, "\(message): exact caller error") }
            count += 1
        }
    }
    static func rejectsImport(_ message: String, expected: SentenceImportError, text: String) {
        do {
            _ = try SentenceTopic.parsePairs(text)
            check(false, message)
        } catch let error as SentenceImportError {
            check(error == expected, "\(message): exact import diagnostic")
        } catch {
            check(false, "\(message): unexpected error type")
        }
    }
    static func topic(_ name: String, count: Int = 8) -> SentenceTopic {
        SentenceTopic(name: name, pairs: (0..<count).map {
            SentencePair(english: "\(name) English \($0)", vietnamese: "\(name) Vietnamese \($0)")
        })
    }
    @MainActor
    static func main() throws {
        let suiteName = "SentenceGameChecks.\(UUID())"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let separateName = "SentenceGameChecks.\(UUID())"
        let separate = UserDefaults(suiteName: separateName)!
        defer { separate.removePersistentDomain(forName: separateName) }
        suite.set("untouched", forKey: "selectedTopic")
        let store = SentenceRepository(defaults: suite)
        let first = topic("First")
        let other = topic("Other")
        check(try store.load().isEmpty, "empty isolated suite")
        var trimmed = first
        trimmed.name = "  First \n"
        let saved = try store.save([trimmed, other], expected: [])
        check(saved[0].name == "First", "trimmed name")
        check(try SentenceRepository(defaults: suite).load() == saved, "reopen saved pairs")
        check(try SentenceRepository(defaults: separate).load().isEmpty, "separate suite cannot see saved topics")
        check(suite.object(forKey: SentenceRoundHistoryRepository.key) == nil, "topic repository does not create history")
        var historyGenerator = SeededGenerator(seed: 129)
        let historyRound = try SentenceRound(topic: first, mode: .quick, using: &historyGenerator)
        let historyQuestion = historyRound.questions[0]
        let historyRecord = SentenceRoundHistoryRecord(
            roundID: UUID(), topic: first, mode: .quick, answeredAt: Date(timeIntervalSince1970: 1234),
            question: historyQuestion, selectedID: historyQuestion.options[0].id, questionIndex: 0
        )
        let historyStore = SentenceRoundHistoryRepository(defaults: suite)
        check(try historyStore.load().isEmpty, "empty isolated round history")
        let historySaved = try historyStore.append(historyRecord)
        check(historySaved == [historyRecord], "append history record")
        check(historyRecord.options.map(\.letter) == ["A", "B", "C", "D"]
            && historyRecord.options.map(\.id) == historyQuestion.options.map(\.id)
            && historyRecord.selectedLetter == "A"
            && historyRecord.selectedEnglish == historyQuestion.options[0].english
            && historyRecord.correctEnglish == historyQuestion.pair.english,
            "history captures displayed option order and selected/correct answers")
        check(SentenceSpeechLine.stageSelection(letter: "C", english: "Answer").map(\.text)
            == ["C. Answer", "Final answer?"], "Stage selection speech asks confirmation after the selected answer")
        check(SentenceSpeechLine.quickResult(letter: "B", english: "Choice", correct: true).map(\.text)
            == ["B. Choice", "Correct."], "Quick speech queues choice before score")
        check(SentenceSpeechLine.quickResult(letter: "D", english: "Choice", correct: false).map(\.text)
            == ["D. Choice", "Incorrect."], "Quick incorrect speech queues choice before score")
        check(try SentenceRoundHistoryRepository(defaults: suite).load() == historySaved, "reopen saved history")
        check(try SentenceRoundHistoryRepository(defaults: separate).load().isEmpty, "separate suite cannot see history")
        check(try SentenceRepository(defaults: suite).load() == saved, "history append preserves sentence topics")
        let sessionStore = SentenceRoundSessionRepository(defaults: suite)
        var pendingGenerator = SeededGenerator(seed: 774)
        var pendingRound = try SentenceRound(topic: first, mode: .stage, using: &pendingGenerator)
        let pendingQuestion = pendingRound.current!
        let pendingChoice = pendingQuestion.options[2].id
        pendingRound.select(pendingChoice)
        let topicBytes = suite.data(forKey: SentenceRepository.key)
        let historyBytes = suite.data(forKey: SentenceRoundHistoryRepository.key)
        let pendingSaved = try sessionStore.save(pendingRound, savedAt: Date(timeIntervalSince1970: 1240))
        let pendingReloaded = try sessionStore.load(topicID: first.id, mode: .stage)!.round.restore()
        check(pendingReloaded.id == pendingRound.id && pendingReloaded.topic == first
            && pendingReloaded.questions == pendingRound.questions
            && pendingReloaded.current?.options == pendingQuestion.options
            && pendingReloaded.selectedID == pendingChoice && pendingReloaded.answers.isEmpty,
            "pending Stage round restores snapshot, option order, and uncommitted selection")
        check(SentenceRoundSnapshot(round: try pendingSaved.round.restore()) == SentenceRoundSnapshot(round: pendingReloaded),
            "saved round snapshot restores exactly")
        var quickSavedRound = try SentenceRound(topic: first, mode: .quick)
        let quickSavedQuestion = quickSavedRound.current!
        let quickSavedAnswer = quickSavedRound.select(quickSavedQuestion.options[1].id)!
        let quickSession = try sessionStore.save(quickSavedRound)
        let quickReloaded = try sessionStore.load(topicID: first.id, mode: .quick)!.round.restore()
        check(quickReloaded.questions == quickSavedRound.questions && quickReloaded.answers == [quickSavedAnswer]
            && quickReloaded.selectedID == quickSavedAnswer.selectedID && quickReloaded.index == 0,
            "Quick auto-score and displayed options restore exactly")
        var completedRound = try SentenceRound(topic: other, mode: .stage)
        while let question = completedRound.current {
            completedRound.select(question.pair.id)
            completedRound.confirm()
            completedRound.advance()
        }
        let completedSaved = try sessionStore.save(completedRound)
        let completedReloaded = try sessionStore.load(topicID: other.id, mode: .stage)!.round.restore()
        check(completedReloaded.finished && completedReloaded.answers == completedRound.answers
            && completedReloaded.score == completedRound.score && completedReloaded.id == completedRound.id,
            "completed round restores results without rerolling")
        let allSessions = try sessionStore.loadAll()
        let savedQuickSession = try sessionStore.load(topicID: first.id, mode: .quick)
        let savedCompletedSession = try sessionStore.load(topicID: other.id, mode: .stage)
        check(allSessions.count == 3 && savedQuickSession?.id == quickSession.id
            && savedCompletedSession?.id == completedSaved.id,
            "sessions remain isolated by topic and mode")
        check(allSessions.map(\.savedAt) == allSessions.map(\.savedAt).sorted(by: >),
            "saved sessions are listed newest first")
        check(suite.data(forKey: SentenceRepository.key) == topicBytes
            && suite.data(forKey: SentenceRoundHistoryRepository.key) == historyBytes,
            "round sessions do not mutate topic or answer history stores")
        let sessionBaseline = suite.data(forKey: SentenceRoundSessionRepository.key)!
        var sessionWrites = 0
        let rejectedSessions = SentenceRoundSessionRepository(defaults: suite, writer: { bytes in
            sessionWrites += 1
            if sessionWrites == 1 { throw SentenceGameError.sessionWriteFailed }
            suite.set(bytes, forKey: SentenceRoundSessionRepository.key)
        })
        rejects("session write rollback", expected: .sessionWriteFailed) {
            try rejectedSessions.save(pendingRound)
        }
        check(try rejectedSessions.loadAll() == sessionStore.loadAll()
            && suite.data(forKey: SentenceRoundSessionRepository.key) == sessionBaseline,
            "failed session write restores previous bytes and sessions")
        sessionWrites = 0
        let mismatchedSessions = SentenceRoundSessionRepository(defaults: suite, writer: { bytes in
            sessionWrites += 1
            suite.set(sessionWrites == 1 ? Data("bad".utf8) : bytes, forKey: SentenceRoundSessionRepository.key)
        })
        rejects("session readback rollback", expected: .sessionWriteFailed) {
            try mismatchedSessions.save(pendingRound)
        }
        check(try mismatchedSessions.loadAll() == sessionStore.loadAll()
            && suite.data(forKey: SentenceRoundSessionRepository.key) == sessionBaseline,
            "session readback mismatch restores previous bytes")
        suite.set(Data("corrupt sessions".utf8), forKey: SentenceRoundSessionRepository.key)
        rejects("corrupt session read", expected: .sessionUnreadable) { _ = try sessionStore.loadAll() }
        rejects("corrupt session save", expected: .sessionUnreadable) { try sessionStore.save(pendingRound) }
        check(suite.data(forKey: SentenceRoundSessionRepository.key) == Data("corrupt sessions".utf8),
            "corrupt session data is never overwritten")
        suite.set(sessionBaseline, forKey: SentenceRoundSessionRepository.key)
        try sessionStore.remove(topicID: first.id, mode: .stage)
        let afterModeRemoval = try sessionStore.loadAll()
        let removedStageSession = try sessionStore.load(topicID: first.id, mode: .stage)
        let remainingQuickSession = try sessionStore.load(topicID: first.id, mode: .quick)
        let remainingOtherSession = try sessionStore.load(topicID: other.id, mode: .stage)
        check(afterModeRemoval.count == 2
            && removedStageSession == nil && remainingQuickSession != nil && remainingOtherSession != nil,
            "mode removal preserves the other mode and topic sessions")
        suite.set(sessionBaseline, forKey: SentenceRoundSessionRepository.key)
        try sessionStore.remove(topicID: first.id)
        let remainingSessions = try sessionStore.loadAll()
        let removedStage = try sessionStore.load(topicID: first.id, mode: .stage)
        let removedQuick = try sessionStore.load(topicID: first.id, mode: .quick)
        check(remainingSessions.map(\.id) == [completedSaved.id]
            && removedStage == nil && removedQuick == nil,
            "topic removal clears its saved modes and preserves other topics")
        let historyModel = SentenceRoundHistoryModel(repository: historyStore)
        check(historyModel.newestFirst.map(\.id) == [historyRecord.id], "history model loads saved records")
        var stageFlow = try SentenceRound(topic: first, mode: .stage)
        let stageQuestion = stageFlow.current!
        let stageBefore = historyModel.records.count
        check(stageFlow.select(stageQuestion.pair.id) == nil && stageFlow.answers.isEmpty
            && historyModel.records.count == stageBefore, "Stage selection does not score or record before confirmation")
        let stageAnswer = stageFlow.confirm()!
        historyModel.append(stageAnswer, roundID: stageFlow.id, topic: stageFlow.topic, mode: stageFlow.mode,
                            questionIndex: stageFlow.index, answeredAt: Date(timeIntervalSince1970: 1236))
        check(stageFlow.answers.count == 1 && historyModel.records.count == stageBefore + 1
            && historyModel.records.last?.questionIndex == 0, "Stage confirmation appends exactly one zero-based question index")
        check(stageFlow.confirm() == nil && historyModel.records.count == stageBefore + 1,
            "repeated Stage confirmation does not append twice")
        var quickFlow = try SentenceRound(topic: other, mode: .quick)
        let quickQuestion = quickFlow.current!
        let quickAnswer = quickFlow.select(quickQuestion.options[0].id)!
        historyModel.append(quickAnswer, roundID: quickFlow.id, topic: quickFlow.topic, mode: quickFlow.mode,
                            questionIndex: quickFlow.index, answeredAt: Date(timeIntervalSince1970: 1237))
        check(quickFlow.answers.count == 1 && historyModel.records.count == stageBefore + 2,
            "Quick selection scores and appends once")
        check(quickFlow.select(quickQuestion.options[1].id) == nil
            && historyModel.records.count == stageBefore + 2, "later Quick option tap cannot double append")
        check(historyModel.newestFirst.map(\.answeredAt) == historyModel.newestFirst.map(\.answeredAt).sorted(by: >),
            "history model presents newest records first")
        check(historyModel.newestFirst.first?.topicID == other.id
            && historyModel.newestFirst.first?.mode == .quick, "history keeps each answer's originating topic and mode")
        let secondHistoryRecord = SentenceRoundHistoryRecord(
            roundID: historyRecord.roundID, topic: other, mode: .stage, answeredAt: Date(timeIntervalSince1970: 1235),
            question: quickQuestion, selectedID: quickQuestion.options[0].id, questionIndex: 1
        )
        let historyBeforeMixedAppend = try historyStore.load()
        let mixedHistory = historyBeforeMixedAppend + [secondHistoryRecord]
        check(try historyStore.append(secondHistoryRecord) == mixedHistory,
            "retries and mixed topics append independent records")
        let historyBaseline = suite.data(forKey: SentenceRoundHistoryRepository.key)!
        var historyWrites = 0
        let rejectedHistory = SentenceRoundHistoryRepository(defaults: suite, writer: { bytes in
            historyWrites += 1
            if historyWrites == 1 { throw SentenceGameError.writeFailed }
            suite.set(bytes, forKey: SentenceRoundHistoryRepository.key)
        })
        rejects("history write rollback", expected: .historyWriteFailed) { try rejectedHistory.append(historyRecord) }
        check(try rejectedHistory.load() == mixedHistory
            && suite.data(forKey: SentenceRoundHistoryRepository.key) == historyBaseline,
            "failed history append restores previous bytes")
        historyWrites = 0
        let mismatchedHistory = SentenceRoundHistoryRepository(defaults: suite, writer: { bytes in
            historyWrites += 1
            suite.set(historyWrites == 1 ? Data("bad".utf8) : bytes, forKey: SentenceRoundHistoryRepository.key)
        })
        rejects("history readback rollback", expected: .historyWriteFailed) { try mismatchedHistory.append(historyRecord) }
        check(try mismatchedHistory.load() == mixedHistory
            && suite.data(forKey: SentenceRoundHistoryRepository.key) == historyBaseline,
            "history readback mismatch restores previous bytes")
        var callerWrites = 0
        let callerFailureStore = SentenceRoundHistoryRepository(defaults: suite, writer: { bytes in
            callerWrites += 1
            if callerWrites == 1 { throw SentenceGameError.historyWriteFailed }
            suite.set(bytes, forKey: SentenceRoundHistoryRepository.key)
        })
        let callerFailureModel = SentenceRoundHistoryModel(repository: callerFailureStore)
        let callerRecords = callerFailureModel.records
        callerFailureModel.append(stageAnswer, roundID: stageFlow.id, topic: first, mode: .stage,
                                  questionIndex: stageFlow.index, answeredAt: Date(timeIntervalSince1970: 1238))
        check(callerFailureModel.records == callerRecords && callerFailureModel.error?.contains("scored") == true
            && suite.data(forKey: SentenceRoundHistoryRepository.key) == historyBaseline,
            "failed history write restores bytes and remains visible to caller")
        callerWrites = 0
        let callerReadbackStore = SentenceRoundHistoryRepository(defaults: suite, writer: { bytes in
            callerWrites += 1
            suite.set(callerWrites == 1 ? Data("bad".utf8) : bytes, forKey: SentenceRoundHistoryRepository.key)
        })
        let callerReadbackModel = SentenceRoundHistoryModel(repository: callerReadbackStore)
        let readbackRecords = callerReadbackModel.records
        callerReadbackModel.append(quickAnswer, roundID: quickFlow.id, topic: other, mode: .quick,
                                   questionIndex: quickFlow.index, answeredAt: Date(timeIntervalSince1970: 1239))
        check(callerReadbackModel.records == readbackRecords && callerReadbackModel.error?.contains("scored") == true
            && suite.data(forKey: SentenceRoundHistoryRepository.key) == historyBaseline,
            "readback rollback restores bytes and exposes UI error")
        var retryRound = try SentenceRound(topic: other, mode: .quick)
        let retryAnswer = retryRound.select(retryRound.current!.options[0].id)!
        var retryWrites = 0
        let retryRepository = SentenceRoundHistoryRepository(defaults: suite, writer: { bytes in
            retryWrites += 1
            if retryWrites == 1 { throw SentenceGameError.historyWriteFailed }
            suite.set(bytes, forKey: SentenceRoundHistoryRepository.key)
        })
        let retryHistoryModel = SentenceRoundHistoryModel(repository: retryRepository)
        retryHistoryModel.recordCommitted(retryAnswer, roundID: retryRound.id, topic: other, mode: .quick,
                                          questionIndex: 0, answeredAt: Date(timeIntervalSince1970: 1241))
        check(retryHistoryModel.error != nil && retryHistoryModel.records == mixedHistory
            && suite.data(forKey: SentenceRoundHistoryRepository.key) == historyBaseline,
            "failed committed history remains visible and queued for retry")
        let reopenedHistoryModel = SentenceRoundHistoryModel(repository: historyStore)
        reopenedHistoryModel.reconcile(retryRound)
        retryHistoryModel.retryPending()
        retryHistoryModel.recordCommitted(retryAnswer, roundID: retryRound.id, topic: other, mode: .quick,
                                          questionIndex: 0, answeredAt: Date(timeIntervalSince1970: 1242))
        let retriedRecords = try historyStore.load()
        check(retryHistoryModel.error == nil && reopenedHistoryModel.error == nil
            && retriedRecords.filter { $0.roundID == retryRound.id && $0.questionIndex == 0 }.count == 1
            && retriedRecords.count == mixedHistory.count + 1,
            "history retry and resumed-round reconciliation append exactly once")
        suite.set(Data("corrupt history".utf8), forKey: SentenceRoundHistoryRepository.key)
        rejects("corrupt history read", expected: .historyUnreadable) { _ = try historyStore.load() }
        rejects("corrupt history append", expected: .historyUnreadable) { try historyStore.append(historyRecord) }
        check(suite.data(forKey: SentenceRoundHistoryRepository.key) == Data("corrupt history".utf8),
            "corrupt history bytes are not overwritten")
        suite.removeObject(forKey: SentenceRoundHistoryRepository.key)
        var spaced = first
        spaced.pairs[0].english = " \n English sentence \n "
        spaced.pairs[0].vietnamese = " Translation \n "
        let cleaned = try spaced.validated()
        check(cleaned.pairs[0].english == "English sentence" && cleaned.pairs[0].vietnamese == "Translation", "trim both sentences")
        check(SentenceTopic.normalized("Stra\u{00DF}e") == SentenceTopic.normalized("STRASSE"), "Unicode case folding")
        check(suite.string(forKey: "selectedTopic") == "untouched", "word key untouched")
        var duplicate = first
        duplicate.pairs[1].english = " FIRST  English\n0 "
        rejects("English duplicates") { _ = try duplicate.validated() }
        duplicate = first
        duplicate.pairs[1].vietnamese = "first  VIETNAMESE 0"
        rejects("Vietnamese duplicates") { _ = try duplicate.validated() }
        duplicate.name = " \n "
        rejects("empty name") { _ = try duplicate.validated() }
        let baseline = suite.data(forKey: SentenceRepository.key)!
        rejects("stale save", expected: .stale) { try store.save([], expected: []) }
        check(suite.data(forKey: SentenceRepository.key) == baseline, "stale keeps bytes")
        var writes = 0
        let rejected = SentenceRepository(defaults: suite, writer: { bytes in
            writes += 1
            if writes == 1 { throw SentenceGameError.writeFailed }
            suite.set(bytes, forKey: SentenceRepository.key)
        })
        rejects("rejected write", expected: .writeFailed) { try rejected.save([], expected: saved) }
        check(try rejected.load() == saved && suite.data(forKey: SentenceRepository.key) == baseline, "rejection rollback")
        writes = 0
        let mismatch = SentenceRepository(defaults: suite, writer: { bytes in
            writes += 1
            suite.set(writes == 1 ? Data("bad".utf8) : bytes, forKey: SentenceRepository.key)
        })
        rejects("readback mismatch", expected: .writeFailed) { try mismatch.save([], expected: saved) }
        check(try mismatch.load() == saved && suite.data(forKey: SentenceRepository.key) == baseline, "readback rollback")
        writes = 0
        let modelStore = SentenceRepository(defaults: suite, writer: { bytes in
            writes += 1
            if writes == 1 { suite.set(Data("bad".utf8), forKey: SentenceRepository.key) }
            else { suite.set(bytes, forKey: SentenceRepository.key) }
        })
        let model = SentenceLibraryModel(repository: modelStore)
        rejects("caller observes rejected edit") { try model.upsert(topic("New"), expected: saved) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        check(model.topics == saved && model.canEdit && writes == 2, "caller restores actual saved list, no queued side effects")
        let lockedStore = SentenceRepository(defaults: suite, writer: { _ in throw SentenceGameError.writeFailed })
        let lockedModel = SentenceLibraryModel(repository: lockedStore)
        rejects("rollback failure reported", expected: .recoveryFailed) { try lockedModel.delete(first.id, expected: saved) }
        check(!lockedModel.canEdit && lockedModel.error != nil && lockedModel.recoveryBytes == baseline, "rollback failure locks editing with recovery bytes")
        rejects("locked writes refused") { try lockedStore.save([], expected: saved) }
        check(suite.data(forKey: SentenceRepository.key) == baseline, "failed writer keeps baseline")
        suite.set(Data("corrupt".utf8), forKey: SentenceRepository.key)
        rejects("corrupt read") { _ = try store.load() }
        rejects("corrupt save", expected: .unreadable) { try store.save([], expected: []) }
        check(suite.data(forKey: SentenceRepository.key) == Data("corrupt".utf8), "corrupt bytes preserved")
        let corruptModel = SentenceLibraryModel(repository: store)
        check(!corruptModel.canEdit && corruptModel.error != nil, "corrupt UI refuses editing")
        suite.set("wrong type", forKey: SentenceRepository.key)
        rejects("wrong-type save") { try store.save([], expected: []) }
        check(suite.string(forKey: SentenceRepository.key) == "wrong type", "wrong-type bytes untouched")
        suite.set(baseline, forKey: SentenceRepository.key)
        var invalidPair = first
        invalidPair.pairs[0].english = " \n "
        rejects("empty sentence") { _ = try invalidPair.validated() }
        let emptyPairs = SentenceTopic(name: "No pairs", pairs: [])
        rejects("empty pairs") { _ = try emptyPairs.validated() }
        rejects("duplicate topic name") { try store.save([first, SentenceTopic(name: " FIRST ", pairs: other.pairs)], expected: saved) }
        check(try SentenceTopic.parsePairs("English\tVietnamese\n\nOther\tTranslation").count == 2, "tab-separated parser")
          let linePairs = try SentenceTopic.parsePairs("First English\nNghĩa thứ nhất\n\nSecond English\nNghĩa thứ hai")
          check(linePairs.map(\.english) == ["First English", "Second English"]
              && linePairs.map(\.vietnamese) == ["Nghĩa thứ nhất", "Nghĩa thứ hai"], "paired-line parser preserves order across blanks")
          check(try SentenceTopic.parsePairs("English\nMeaning\n\n english \n MEANING ").count == 1,
              "identical normalized pairs are deduplicated")
          rejectsImport("odd pair reports original line", expected: .incompletePair(5),
                    text: "English\n\nVietnamese\n\nOrphan")
          rejectsImport("duplicate Vietnamese reports both lines", expected: .vietnameseConflict(firstLine: 2, secondLine: 5),
                    text: "First English\nShared meaning\n\nSecond English\nShared meaning")
        rejectsImport("duplicate English reports both lines", expected: .englishConflict(firstLine: 1, secondLine: 5),
                    text: "Shared English\nFirst meaning\n\n\nShared English\nSecond meaning")
          rejectsImport("malformed TSV reports original line", expected: .malformedLine(3),
                    text: "English\tVietnamese\n\nBad\trow\textra")
        rejects("malformed paste") { _ = try SentenceTopic.parsePairs("English|Vietnamese") }
        rejects("extra columns") { _ = try SentenceTopic.parsePairs("a\tb\tc") }
        for mode in SentenceMode.allCases {
            var round = try SentenceRound(topic: first, mode: mode)
            check(round.questions.count == (mode == .stage ? 8 : 5), "mode count")
            check(Set(round.questions.map(\.id)).count == round.questions.count, "no repeated question")
            for question in round.questions {
                check(question.options.count == 4 && Set(question.options.map(\.id)).count == 4, "four distinct options")
                check(question.options.filter { $0.id == question.id }.count == 1, "one correct option")
                check(question.options.allSatisfy { first.pairs.contains($0) && !other.pairs.contains($0) }, "same originating topic")
                let wrong = question.options.first { $0.id != question.id }!
                round.select(wrong.id)
                check(round.revealed == (mode == .quick), "mode reveal policy")
                round.confirm()
                let scored = round.answers.count
                round.select(question.id)
                round.confirm()
                check(round.answers.count == scored && round.score == 0, "score once; selection locked")
                round.advance()
            }
            check(round.finished && round.incorrectIDs.count == round.questions.count, "wrong does not end round")
            for retryCount in 1...3 {
                let ids = Set(first.pairs.prefix(retryCount).map(\.id))
                let retry = try SentenceRound(topic: first, mode: mode, retryIDs: ids)
                check(Set(retry.questions.map(\.id)) == ids, "wrong-only retry")
                check(retry.questions.allSatisfy { $0.options.count == 4 && $0.options.allSatisfy(first.pairs.contains) }, "retry uses full source")
            }
        }
        rejects("too few") { _ = try SentenceRound(topic: topic("Small", count: 3), mode: .stage) }
        var success = try SentenceRound(topic: first, mode: .stage)
        success.advance()
        check(success.index == 0, "cannot skip unanswered")
        success.select(UUID())
        success.confirm()
        check(success.answers.isEmpty, "foreign answer refused")
        while let question = success.current {
            success.select(question.id)
            check(!success.revealed, "Stage waits for confirmation")
            success.confirm()
            success.advance()
        }
        check(success.score == 8 && success.incorrectIDs.isEmpty, "all correct results")
        var generator = SeededGenerator(seed: 42)
        let ordered = try SentenceRound(topic: first, mode: .stage, using: &generator)
        check(ordered.questions.map(\.id) != first.pairs.map(\.id), "question order shuffled")
        check(Set(ordered.questions.compactMap { question in question.options.firstIndex { $0.id == question.id } }).count > 1, "correct option placement varies")
        let sourceSnapshot = first
        for question in ordered.questions {
            let plan = SentenceSpeechLine.plan(for: question)
            check(plan.count == 4, "narration contains only four English answer choices")
            check(plan.map(\.text) == zip(["A", "B", "C", "D"], question.options).map { "\($0.0). \($0.1.english)" }, "display shuffle and labels exact, no prompt or correctness hints")
        }
        check(SentenceNarrationProfile.voiceLanguage == "en-US", "game uses the Vocabulary English voice language")
        check(SentenceNarrationProfile.rate(defaultRate: 0.5) == 0.5, "game retains the default Vocabulary speech rate")
        check(first == sourceSnapshot, "speech plan does not mutate source")
        var narration = SentenceNarrationState()
        check(narration.shouldAutoRead, "new questions auto-read in every mode")
        narration.enabled = false
        check(!narration.shouldAutoRead, "disabled narrator prevents auto")
        narration.enabled = true
        let stale = narration.begin()
        narration.cancel()
        let fresh = narration.begin()
        var staleCallbacksDrained = false
        DispatchQueue.main.async {
            check(!narration.started(stale) && !narration.finished(stale), "queued old start/finish ignored")
            staleCallbacksDrained = true
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        check(staleCallbacksDrained, "queued stale work actually drained")
        check(narration.pending && !narration.speaking, "queuing is not speech start")
        check(narration.started(fresh) && narration.speaking, "fresh start accepted")
        check(narration.finished(fresh) && !narration.pending, "fresh finish accepted")
        check(!narration.finished(fresh) && !narration.started(fresh), "duplicate completion and late start ignored")
        for reason in ["select", "confirm", "advance", "retry", "exit", "background", "interruption", "route", "voice change", "stop"] {
            let old = narration.begin()
            check(narration.started(old), "\(reason): initial speech starts")
            narration.cancel()
            let replacement = narration.begin()
            var drained = false
            DispatchQueue.main.async {
                check(!narration.finished(old) && !narration.started(old), "\(reason): stale callbacks rejected after replay")
                drained = true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            check(drained && narration.pending && !narration.speaking && narration.generation == replacement, "\(reason): old work cannot change fresh read")
            narration.cancel()
            check(!narration.pending && !narration.speaking, "\(reason): immediate invalidation")
        }
        for size in 4...5 {
            check(try SentenceRound(topic: topic("Size", count: size), mode: .quick).questions.count == size, "Quick uses available pairs up to five")
        }
        var policy = SentenceAudioPolicy()
        check(!policy.permitsMusic && !policy.permitsEffects, "inactive audio blocked")
        policy.active = true
        policy.stage = true
        check(policy.permitsMusic && policy.permitsEffects, "active Stage audio")
        policy.narrating = true
        check(policy.musicVolume == 0.045 && policy.permitsNarration, "speech attenuates permitted music")
        policy.narrating = false
        check(policy.musicVolume == 0.22, "speech end restores active music")
        policy.musicEnabled = false
        check(!policy.permitsMusic && policy.permitsEffects, "independent music mute")
        check(policy.musicVolume == 0 && policy.permitsNarration, "music mute cannot be restored by speech end and allows narration")
        policy.musicEnabled = true
        policy.effectsEnabled = false
        check(policy.permitsMusic && !policy.permitsEffects, "independent effect mute")
        check(policy.permitsNarration, "effects mute leaves narration permitted")
        policy.interrupted = true
        check(!policy.permitsMusic && !policy.permitsEffects, "interruption blocks both")
        policy.narrating = false
        check(policy.musicVolume == 0 && !policy.permitsNarration, "interrupted speech end cannot restore music")
        policy.interrupted = false
        policy.stage = false
        policy.effectsEnabled = true
        check(!policy.permitsMusic && policy.permitsEffects, "Quick has effects but no music")
        policy.active = false
        check(!policy.permitsMusic && !policy.permitsEffects, "dismissal blocks effects after activation")
        policy.stage = true
        check(policy.musicVolume == 0 && !policy.permitsNarration, "background/exit speech end cannot resurrect music")
        let reveal = SentenceRevealController()
        var callbacks = 0
        reveal.begin(delay: 1_000_000) { callbacks += 1 }
        reveal.cancel()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        check(callbacks == 0 && !reveal.isRevealing, "dismiss/background cancels queued reveal")
        reveal.begin(delay: 1_000_000) { callbacks += 1 }
        reveal.begin(delay: 1_000_000) { callbacks += 100 }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        check(callbacks == 1 && !reveal.isRevealing, "single delayed reveal, repeated confirm ignored")
        reveal.begin(delay: 1_000_000) { callbacks += 100 }
        reveal.cancel()
        reveal.begin(delay: 1_000_000) { callbacks += 1 }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        check(callbacks == 2, "fresh question cannot receive stale reveal")
        for sound in SentenceSound.allCases {
            let bytes = sound.wave()
            check(String(data: bytes.prefix(4), encoding: .ascii) == "RIFF" && String(data: bytes.subdata(in: 8..<12), encoding: .ascii) == "WAVE", "original PCM WAV header")
            func unsigned(_ offset: Int, size: Int) -> Int {
                (0..<size).reduce(0) { $0 | (Int(bytes[offset + $1]) << ($1 * 8)) }
            }
            let samples = stride(from: 44, to: bytes.count, by: 2).map {
                Double(Int16(bitPattern: UInt16(unsigned($0, size: 2)))) / Double(Int16.max)
            }
            let expectedSamples = Int(22_050 * sound.noteDuration) * sound.notes.count
            check(unsigned(4, size: 4) == bytes.count - 8 && unsigned(40, size: 4) == samples.count * 2 && samples.count == expectedSamples, "RIFF and PCM data lengths match duration")
            check(String(data: bytes.subdata(in: 12..<16), encoding: .ascii) == "fmt " && unsigned(16, size: 4) == 16 && unsigned(20, size: 2) == 1 && unsigned(22, size: 2) == 1, "mono PCM format")
            check(unsigned(24, size: 4) == 22_050 && unsigned(28, size: 4) == 44_100 && unsigned(32, size: 2) == 2 && unsigned(34, size: 2) == 16 && String(data: bytes.subdata(in: 36..<40), encoding: .ascii) == "data", "sample rate, byte rate, alignment and depth")
            check(samples.allSatisfy { $0.isFinite && abs($0) < 0.5 }, "finite PCM with constant nonclipping headroom")
            let energy = samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count)
            check(energy > 0.0001 && samples.contains { $0 > 0.01 } && samples.contains { $0 < -0.01 }, "meaningful bipolar waveform energy")
            check(samples.first == 0 && samples.last == samples.first, "music loop joins at matching zero crossings")
            if sound == .music {
                func component(_ frequency: Double, note: Int, offset: Int = 0) -> Double {
                    let start = note * Int(22_050 * sound.noteDuration) + offset
                    let frameCount = 2_048
                    var real = 0.0
                    var imaginary = 0.0
                    for index in 0..<frameCount {
                        let phase = 2 * Double.pi * frequency * Double(index) / 22_050
                        let value = samples[start + index]
                        real += value * cos(phase)
                        imaginary += value * sin(phase)
                    }
                    return 2 * hypot(real, imaginary) / Double(frameCount)
                }
                let noteMidpoint = Int(22_050 * sound.noteDuration) / 2
                check(component(349.23, note: 2, offset: noteMidpoint) > 0.04
                    && component(523.25, note: 12, offset: noteMidpoint) > 0.04,
                    "melody moves through the midrange")
                check(component(174.61, note: 1) > 0.02 && component(164.81, note: 5) > 0.02,
                    "chord bed changes harmony")
                check(component(73.42, note: 2) > 0.015,
                    "low pulse is present beneath the melody")
                check(abs(samples[1] - samples[0]) < 0.02
                    && abs(samples.last! - samples[samples.count - 2]) < 0.02,
                    "music loop edge slopes stay click-safe")
            }
            check(bytes == sound.wave(), "deterministic original synthesis")
        }
        print("Passed \(count) sentence game checks")
    }

    struct SeededGenerator: RandomNumberGenerator {
        var seed: UInt64
        mutating func next() -> UInt64 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return seed
        }
    }
}