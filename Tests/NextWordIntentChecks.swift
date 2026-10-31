import Foundation

@main
struct NextWordIntentChecks {
    static func main() async throws {
        let suiteID = "VocabularyWidget.NextWordIntentChecks.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteID)!
        WidgetProgressStore.testDefaults = suite
        defer {
            suite.removePersistentDomain(forName: suiteID)
            WidgetProgressStore.testDefaults = nil
        }

        let topic = VocabularyCatalog.topics[0]
        let otherTopic = VocabularyCatalog.topics[1]
        WidgetProgressStore.ensureSelectedTopicInitialized()
        WidgetProgressStore.resetProgress(for: topic)

        let firstTap = Date.now
        _ = try await NextWordIntent(topicID: topic.id, displayedIndex: 0).perform()
        check(suite.integer(forKey: "progress.\(topic.id)") == 1, "first action saves word two")
        check(WidgetProgressStore.currentIndex(for: topic) == 1, "first action changes the current word")
        check(WidgetProgressStore.hasVisited(topic), "first action marks the topic visited")
        check(WidgetProgressStore.allStudyHistory().isEmpty, "NextWordIntent must not record study history")
        checkTimer(suite, topic: topic, after: firstTap)
        check(VocabularyTimelineSchedule.make(for: topic, at: .now)[0].index == 1, "refreshed timeline starts with word two")

        let refreshedTap = Date.now
        _ = try await NextWordIntent(topicID: topic.id, displayedIndex: 1).perform()
        check(suite.integer(forKey: "progress.\(topic.id)") == 2, "refreshed action saves word three")
        checkTimer(suite, topic: topic, after: refreshedTap)
        check(VocabularyTimelineSchedule.make(for: topic, at: .now)[0].index == 2, "second refreshed timeline starts with word three")

        let wrapTap = Date.now
        _ = try await NextWordIntent(topicID: topic.id, displayedIndex: topic.words.count - 1).perform()
        check(suite.integer(forKey: "progress.\(topic.id)") == 0, "last displayed word wraps to word one")
        checkTimer(suite, topic: topic, after: wrapTap)

        WidgetProgressStore.selectTopic(otherTopic)
        let originalProgress = suite.integer(forKey: "progress.\(topic.id)")
        let otherProgress = suite.integer(forKey: "progress.\(otherTopic.id)")
        let otherAnchor = suite.object(forKey: "anchor.\(otherTopic.id)") as? Date
        _ = try await NextWordIntent(topicID: topic.id, displayedIndex: 0).perform()
        check(WidgetProgressStore.selectedTopicID == otherTopic.id, "stale topic action does not change selection")
        check(suite.integer(forKey: "progress.\(topic.id)") == originalProgress, "stale topic action preserves original progress")
        check(suite.integer(forKey: "progress.\(otherTopic.id)") == otherProgress, "stale topic action preserves selected progress")
        check(suite.object(forKey: "anchor.\(otherTopic.id)") as? Date == otherAnchor, "stale topic action does not restart selected timer")

        check(WidgetProgressStore.allStudyHistory().isEmpty, "all ordinary next actions must leave study history empty")

        let studyTap = Date.now
        WidgetProgressStore.resetProgress(for: otherTopic, at: studyTap)
        _ = try await StudiedWordIntent(topicID: otherTopic.id, displayedIndex: 0).perform()
        let studyRecords = WidgetProgressStore.allStudyHistory()
        check(studyRecords.count == 1, "StudiedWordIntent.perform() records the word")
        check(studyRecords[0].topicID == otherTopic.id && studyRecords[0].wordID == otherTopic.words[0].text, "StudiedWordIntent records the supplied topic and displayed word")
        check(studyRecords[0].day == WidgetProgressStore.dayKey(for: studyRecords[0].studiedAt), "StudiedWordIntent stores the local day key")
        check(suite.integer(forKey: "progress.\(otherTopic.id)") == 1, "StudiedWordIntent advances to the following word")
        checkTimer(suite, topic: otherTopic, after: studyTap)
        _ = try await StudiedWordIntent(topicID: otherTopic.id, displayedIndex: 0).perform()
        check(WidgetProgressStore.allStudyHistory().count == 1, "StudiedWordIntent deduplicates repeat taps on the same word and day")

        print("NextWordIntent perform checks passed (\(checksPassed) checks).")
        let dispatchType = _typeByName("25VocabularyWidgetExtension14NextWordIntentV")
        check(dispatchType == NextWordIntent.self, "intent resolves by its non-private mangled dispatch identity")
        let studiedDispatchType = _typeByName("25VocabularyWidgetExtension17StudiedWordIntentV")
        check(studiedDispatchType == StudiedWordIntent.self, "studied intent resolves by its non-private mangled dispatch identity")
        print("NextWordIntent and StudiedWordIntent checks passed (\(checksPassed) checks; actual perform(), not system widget dispatch).")
    }

    private static var checksPassed = 0

    private static func checkTimer(_ suite: UserDefaults, topic: VocabularyTopic, after tap: Date) {
        guard let anchor = suite.object(forKey: "anchor.\(topic.id)") as? Date else {
            fatalError("action must save its timer anchor")
        }
        check(anchor >= tap && anchor <= .now, "action restarts the timer at execution time")
        let index = WidgetProgressStore.currentIndex(for: topic, at: anchor)
        check(WidgetProgressStore.currentIndex(for: topic, at: anchor.addingTimeInterval(299)) == index, "action word remains for 299 seconds")
        check(WidgetProgressStore.currentIndex(for: topic, at: WidgetProgressStore.nextChange(after: anchor, for: topic)) == (index + 1) % topic.words.count, "action word advances at 300 seconds")
        check(WidgetProgressStore.nextChange(after: anchor, for: topic) == WidgetProgressStore.schedule.nextChange(anchor: anchor, after: anchor), "action schedules the next eligible full dwell")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checksPassed += 1
    }
}
