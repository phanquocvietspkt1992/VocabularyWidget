import Foundation

@main
struct ProgressStoreChecks {
    private static var checksPassed = 0

    static func main() {
        let testSuiteID = "VocabularyWidget.ProgressStoreChecks.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: testSuiteID)!
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
