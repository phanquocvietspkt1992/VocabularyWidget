import Foundation

@main
struct ScheduleChecks {
    static var count = 0
    static func check(_ value: Bool, _ message: String) {
        guard value else { fatalError("FAIL: \(message)") }
        count += 1
    }
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        let schedule = VocabularySchedule()
        check(schedule.startMinute == 450 && schedule.endMinute == 1410 && schedule.intervalMinutes == 5 && !schedule.notificationsEnabled, "defaults")
        check(schedule.isValid, "default valid")
        check(VocabularySchedule(intervalMinutes: 1441).isValid, "positive whole minutes valid")
        check(!VocabularySchedule(startMinute: 10, endMinute: 10).isValid, "equal times invalid")
        check(!VocabularySchedule(startMinute: -1).isValid, "negative start invalid")
        check(!VocabularySchedule(endMinute: 1440).isValid, "end outside day invalid")
        check(!VocabularySchedule(intervalMinutes: 0).isValid, "zero interval invalid")
        check(!VocabularySchedule(intervalMinutes: -5).isValid, "negative interval invalid")
        let late = date(30, 23, 28)
        check(schedule.nextChange(anchor: late, after: late, calendar: calendar) == date(31, 7, 33), "carry 23:28 to 07:33")
        let edge = date(30, 23, 25)
        check(schedule.nextChange(anchor: edge, after: edge, calendar: calendar) == date(31, 7, 30), "end tick deferred to start")
        check(schedule.eligibleTickCount(anchor: edge, at: date(30, 23, 30), calendar: calendar) == 0, "exclusive end")
        check(schedule.eligibleTickCount(anchor: edge, at: date(31, 7, 29), calendar: calendar) == 0, "overnight freeze")
        check(schedule.eligibleTickCount(anchor: edge, at: date(31, 7, 30), calendar: calendar) == 1, "inclusive next start")
        check(schedule.nextChange(anchor: edge, after: date(31, 7, 30), calendar: calendar) == date(31, 7, 35), "strictly after tick")
        let crossing = VocabularySchedule(startMinute: 23 * 60, endMinute: 60, intervalMinutes: 5)
        check(crossing.isValid, "cross midnight valid")
        let crossingAnchor = date(30, 23, 58)
        check(crossing.nextChange(anchor: crossingAnchor, after: crossingAnchor, calendar: calendar) == date(31, 0, 3), "tick through midnight")
        check(crossing.nextChange(anchor: date(30, 0, 58), after: date(30, 0, 58), calendar: calendar) == date(30, 23, 3), "overnight end carry")
        let longInterval = VocabularySchedule(startMinute: 7 * 60, endMinute: 8 * 60, intervalMinutes: 120)
        check(longInterval.nextChange(anchor: date(29, 7, 0), after: date(29, 7, 0), calendar: calendar) == date(31, 7, 0), "carry interval across multiple days")
        var dstCalendar = calendar
        dstCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dst = VocabularySchedule(startMinute: 0, endMinute: 4 * 60, intervalMinutes: 120)
        let dstAnchor = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0))!
        let dstExpected = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3))!
        check(dst.nextChange(anchor: dstAnchor, after: dstAnchor, calendar: dstCalendar) == dstExpected, "DST real active seconds")
        let fallAnchor = dstCalendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0))!
        check(dst.nextChange(anchor: fallAnchor, after: fallAnchor, calendar: dstCalendar) == fallAnchor.addingTimeInterval(7200), "fall DST repeated hour")
        let repeatedEnd = VocabularySchedule(startMinute: 60, endMinute: 90, intervalMinutes: 60)
        let firstOne = fallAnchor.addingTimeInterval(3600)
        let secondOne = fallAnchor.addingTimeInterval(7200)
        let secondOneThirty = fallAnchor.addingTimeInterval(9000)
        check(repeatedEnd.nextChange(anchor: firstOne, after: firstOne, calendar: dstCalendar) == secondOne, "ambiguous start first and end last allow tick in second hour")
        check(repeatedEnd.eligibleTickCount(anchor: firstOne, at: secondOne, calendar: dstCalendar) == 1, "repeated-hour active seconds count")
        check(repeatedEnd.eligibleTickCount(anchor: firstOne, at: secondOneThirty, calendar: dstCalendar) == 1, "ambiguous exclusive end remains last occurrence")
        let gapStart = VocabularySchedule(startMinute: 150, endMinute: 240, intervalMinutes: 5)
        check(gapStart.nextChange(anchor: dstAnchor, after: dstAnchor, calendar: dstCalendar) == dstExpected.addingTimeInterval(300), "missing spring boundary advances to next valid time")
        let gapWindow = VocabularySchedule(startMinute: 130, endMinute: 150, intervalMinutes: 5)
        let gapTick = gapWindow.nextChange(anchor: dstAnchor, after: dstAnchor, calendar: dstCalendar)
        check(gapTick > dstAnchor && gapTick.timeIntervalSince(dstAnchor) < 2 * 86400, "collapsed spring window skips without crash or loop")
        // Independent minute-by-minute oracle for counts; production loops only over days.
        for testSchedule in [schedule, crossing, longInterval] {
            let anchor = date(29, 23, 28)
            var active = 0
            for minute in 1...3000 {
                let previous = anchor.addingTimeInterval(Double(minute - 1) * 60)
                let now = anchor.addingTimeInterval(Double(minute) * 60)
                let previousComponents = calendar.dateComponents([.hour, .minute], from: previous)
                let previousMinute = previousComponents.hour! * 60 + previousComponents.minute!
                let components = calendar.dateComponents([.hour, .minute], from: now)
                let nowMinute = components.hour! * 60 + components.minute!
                func inside(_ m: Int) -> Bool {
                    testSchedule.startMinute < testSchedule.endMinute
                        ? m >= testSchedule.startMinute && m < testSchedule.endMinute
                        : m >= testSchedule.startMinute || m < testSchedule.endMinute
                }
                if inside(previousMinute) { active += 1 }
                let deferred = !inside(nowMinute) && active > 0 && active % testSchedule.intervalMinutes == 0
                let expected = active / testSchedule.intervalMinutes - (deferred ? 1 : 0)
                check(testSchedule.eligibleTickCount(anchor: anchor, at: now, calendar: calendar) == expected, "oracle count \(minute)")
            }
        }
        let suiteID = "VocabularyWidget.ScheduleChecks.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteID)!
        WidgetProgressStore.testDefaults = suite
        defer { suite.removePersistentDomain(forName: suiteID); WidgetProgressStore.testDefaults = nil }
        let localAnchor = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        WidgetProgressStore.ensureSelectedTopicInitialized(at: localAnchor)
        let topic = VocabularyCatalog.topic(for: WidgetProgressStore.selectedTopicID)
        let now = localAnchor.addingTimeInterval(910)
        let before = WidgetProgressStore.currentIndex(for: topic, at: now)
        check(WidgetProgressStore.updateSchedule(VocabularySchedule(intervalMinutes: 10), at: now), "save settings")
        check(WidgetProgressStore.currentIndex(for: topic, at: now) == before, "settings preserve current word")
        check(!WidgetProgressStore.updateSchedule(VocabularySchedule(startMinute: 20, endMinute: 20), at: now), "reject invalid settings")
        check(WidgetProgressStore.schedule.intervalMinutes == 10, "invalid keeps stored schedule")
        let anchorBeforeToggle = suite.object(forKey: "anchor.\(topic.id)") as? Date
        check(WidgetProgressStore.updateSchedule(VocabularySchedule(intervalMinutes: 10, notificationsEnabled: true), at: now.addingTimeInterval(120)), "toggle notifications")
        check(WidgetProgressStore.schedule.notificationsEnabled, "notification toggle persists")
        check(suite.object(forKey: "anchor.\(topic.id)") as? Date == anchorBeforeToggle, "notification toggle keeps anchor")
        let anchorBefore = suite.object(forKey: "anchor.\(topic.id)") as? Date
        WidgetProgressStore.selectTopic(topic, at: now.addingTimeInterval(10))
        check(suite.object(forKey: "anchor.\(topic.id)") as? Date == anchorBefore, "same topic no op")
        let dataBefore = suite.dictionaryRepresentation()
        _ = WidgetProgressStore.currentIndex(for: topic, at: now)
        _ = WidgetProgressStore.nextChange(after: now, for: topic)
        check(NSDictionary(dictionary: dataBefore).isEqual(to: suite.dictionaryRepresentation()), "reads do not mutate")
        let plan = VocabularyNotificationPlan.make(at: now, limit: 1000)
        check(plan.count == 64, "notification cap")
        var previous = now
        for point in plan {
            check(point.date > previous && point.date > now, "future ticks")
            check(point.date == WidgetProgressStore.nextChange(after: previous, for: topic), "plan tick function")
            check(point.word == topic.words[WidgetProgressStore.currentIndex(for: topic, at: point.date)], "plan word at tick")
            check(point.topicName == topic.name, "selected topic content")
            previous = point.date
        }
        let ids = plan.map { VocabularyNotificationPlan.identifier(for: $0.date) }
        let concurrentPlan = VocabularyNotificationPlan.make(at: now, limit: 64)
        check(ids == concurrentPlan.map { VocabularyNotificationPlan.identifier(for: $0.date) }, "concurrent tick requests share stable IDs")
        check(Set(ids).count == 64, "one identifier per tick")
        let obsolete = VocabularyNotificationPlan.obsoleteIdentifiers(ids + ["vocabulary.tick.old-batch.0", "other.app.request"], keeping: concurrentPlan)
        check(obsolete == ["vocabulary.tick.old-batch.0"], "remove only obsolete app ticks, retain overlapping and unrelated requests")
        var replacedRequests = Dictionary(uniqueKeysWithValues: zip(ids, plan.map { $0.word }))
        for point in concurrentPlan { replacedRequests[VocabularyNotificationPlan.identifier(for: point.date)] = point.word }
        check(replacedRequests.count == 64, "overlapping process plans replace rather than duplicate")
        let anchorKey = "anchor.\(topic.id)"
        suite.removeObject(forKey: anchorKey)
        let missingBefore = suite.dictionaryRepresentation()
        check(WidgetProgressStore.currentIndex(for: topic, at: now) == before, "missing-anchor index uses saved progress")
        check(WidgetProgressStore.nextChange(after: now, for: topic) == WidgetProgressStore.schedule.nextChange(anchor: now, after: now), "missing-anchor next tick uses in-memory fallback")
        _ = WidgetProgressStore.schedule
        check(NSDictionary(dictionary: missingBefore).isEqual(to: suite.dictionaryRepresentation()), "missing-anchor reads never persist")
        suite.set(now.addingTimeInterval(3600), forKey: anchorKey)
        let futureBefore = suite.dictionaryRepresentation()
        check(WidgetProgressStore.currentIndex(for: topic, at: now) == before, "future-anchor index ignores future date")
        check(WidgetProgressStore.nextChange(after: now, for: topic) == WidgetProgressStore.schedule.nextChange(anchor: now, after: now), "future-anchor next tick uses in-memory fallback")
        _ = WidgetProgressStore.schedule
        check(NSDictionary(dictionary: futureBefore).isEqual(to: suite.dictionaryRepresentation()), "future-anchor reads never persist")
        WidgetProgressStore.ensureSelectedTopicInitialized(at: now)
        check(suite.object(forKey: anchorKey) as? Date == now, "explicit initialization repairs future anchor")
        print("Schedule checks passed (\(count) checks).")
    }
}
