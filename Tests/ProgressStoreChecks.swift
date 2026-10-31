import Foundation

@main
struct ProgressStoreChecks {
    private static var checksPassed = 0

    static func main() {
        let testSuiteID = "VocabularyWidget.ProgressStoreChecks.\(UUID().uuidString)"
        let suite = HistoryTrackingDefaults(suiteName: testSuiteID)!
        let realAppGroupDefaults = UserDefaults(suiteName: WidgetProgressStore.appGroupID)!
        let protectedKey = "VocabularyWidget.ProgressStoreChecks.protected.\(UUID().uuidString)"
        realAppGroupDefaults.set("keep", forKey: protectedKey)
        WidgetProgressStore.testDefaults = suite
        suite.removePersistentDomain(forName: testSuiteID)
        defer {
            suite.removePersistentDomain(forName: testSuiteID)
            WidgetProgressStore.testDefaults = nil
            realAppGroupDefaults.removeObject(forKey: protectedKey)
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
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        WidgetProgressStore.ensureSelectedTopicInitialized(at: start)
        check(WidgetProgressStore.selectedTopicID == workCommunication.id, "a new install should default to the first IT topic")
        check(!WidgetProgressStore.hasVisited(workCommunication), "initial default should not imply that the learner visited the topic")
        check(WidgetProgressStore.currentIndex(for: workCommunication, at: start) == 0, "the default topic should start at its first word")

        var emptyNameRejected = false
        do { _ = try CustomTopicStore.create(name: "  \n") } catch CustomTopicStore.CreateError.emptyName { emptyNameRejected = true } catch {}
        check(emptyNameRejected, "a custom topic should reject an empty name")
        var duplicateNameRejected = false
        do { _ = try CustomTopicStore.create(name: "  GIAO TIẾP CÔNG VIỆC ") } catch CustomTopicStore.CreateError.duplicateName { duplicateNameRejected = true } catch {}
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
        let firstSelection = start.addingTimeInterval(900)
        WidgetProgressStore.selectTopic(travel, at: firstSelection)
        check(WidgetProgressStore.currentIndex(for: travel, at: firstSelection) == 0, "first explicit selection should start at word one")
        check(WidgetProgressStore.currentIndex(for: travel, at: firstSelection.addingTimeInterval(299)) == 0, "first selected word should remain for five minutes")
        check(WidgetProgressStore.currentIndex(for: travel, at: firstSelection.addingTimeInterval(300)) == 1, "the first selected word should advance after five minutes")
        check(WidgetProgressStore.secondsUntilNextChange(for: travel, at: firstSelection.addingTimeInterval(299)) == 1, "the app countdown should show one second at the interval boundary")
        check(WidgetProgressStore.secondsUntilNextChange(for: travel, at: firstSelection.addingTimeInterval(300)) == 300, "the app countdown should restart after the word advances")
        WidgetProgressStore.selectTopic(travel, at: firstSelection.addingTimeInterval(100))
        check(WidgetProgressStore.nextChange(after: firstSelection.addingTimeInterval(100), for: travel) == firstSelection.addingTimeInterval(300), "reselecting an active topic should not reset its timer")
        let nearBoundary = firstSelection.addingTimeInterval(299)
        check(WidgetProgressStore.nextChange(after: nearBoundary, for: travel).timeIntervalSince(WidgetProgressStore.currentEntryDate(for: travel, at: nearBoundary)) == WidgetProgressStore.interval, "timeline entries should stay at least five minutes apart near a boundary")
        let schedule = VocabularyTimelineSchedule.make(for: travel, at: nearBoundary)
        check(schedule.count == VocabularyTimelineSchedule.futureEntryCount + 1, "the timeline should contain the current word and a day of future entries")
        check(schedule[0].index == 0 && schedule[1].index == 1, "the schedule should begin with the current word then advance")
        for pair in zip(schedule, schedule.dropFirst()) {
            check(pair.1.date.timeIntervalSince(pair.0.date) == WidgetProgressStore.interval, "scheduled entries should be exactly five minutes apart")
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

        print("Progress checks passed (\(checksPassed) checks).")
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
