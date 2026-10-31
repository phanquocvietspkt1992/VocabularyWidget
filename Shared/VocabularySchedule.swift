import Foundation

struct VocabularySchedule: Codable, Equatable {
    var startMinute = 7 * 60 + 30
    var endMinute = 23 * 60 + 30
    var intervalMinutes = 5
    var notificationsEnabled = false

    var isValid: Bool {
        (0..<1440).contains(startMinute) && (0..<1440).contains(endMinute)
            && startMinute != endMinute && intervalMinutes > 0
    }
    var interval: TimeInterval { Double(intervalMinutes) * 60 }

    private func window(on day: Date, calendar: Calendar) -> DateInterval? {
        guard let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              let endDay = startMinute > endMinute ? calendar.date(byAdding: .day, value: 1, to: day) : day,
              let end = calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60, second: 0, of: endDay, matchingPolicy: .nextTime, repeatedTimePolicy: .last), end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    // Only day windows are visited, never individual elapsed ticks. Bound corrupt/extreme anchors.
    private func boundedAnchor(_ anchor: Date, at date: Date, calendar: Calendar) -> Date {
        let earliest = calendar.date(byAdding: .year, value: -100, to: date) ?? date
        return max(anchor, earliest)
    }

    private func activeElapsed(from anchor: Date, to date: Date, calendar: Calendar) -> (seconds: Double, atEnd: Bool) {
        guard date > anchor, date.timeIntervalSince1970.isFinite,
              abs(date.timeIntervalSince1970) < 1e12 else { return (0, false) }
        let anchor = boundedAnchor(anchor, at: date, calendar: calendar)
        var day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: anchor)) ?? anchor
        var seconds = 0.0
        var atEnd = false
        while day <= date {
            if let window = window(on: day, calendar: calendar) {
                let lower = max(anchor, window.start)
                let upper = min(date, window.end)
                if upper > lower { seconds += upper.timeIntervalSince(lower) }
                if date >= window.start && date < window.end { atEnd = false }
                if date >= window.end && upper > lower { atEnd = true }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return (seconds, atEnd)
    }

    func eligibleTickCount(anchor: Date, at date: Date, calendar: Calendar = .current) -> Int {
        let elapsed = activeElapsed(from: anchor, to: date, calendar: calendar)
        let count = Int(elapsed.seconds / interval)
        // A completed interval at the exclusive end is released at the next inclusive start.
        return elapsed.atEnd && elapsed.seconds > 0 && elapsed.seconds.truncatingRemainder(dividingBy: interval) == 0 ? max(0, count - 1) : count
    }

    func nextChange(anchor: Date, after date: Date, calendar: Calendar = .current) -> Date {
        let elapsed = activeElapsed(from: anchor, to: date, calendar: calendar)
        var remaining = Double(eligibleTickCount(anchor: anchor, at: date, calendar: calendar) + 1) * interval - elapsed.seconds
        var day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) ?? date
        for _ in 0..<36600 {
            if let window = window(on: day, calendar: calendar), window.end > date {
                let start = max(date, window.start)
                let capacity = window.end.timeIntervalSince(start)
                if remaining < capacity {
                    let tick = start.addingTimeInterval(max(0, remaining))
                    if tick > date { return tick }
                }
                remaining = max(0, remaining - capacity)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return date.addingTimeInterval(interval)
    }
}

struct VocabularyNotificationPoint {
    let date: Date
    let word: VocabularyWord
    let topicName: String
}

enum VocabularyNotificationPlan {
    static let identifierPrefix = "vocabulary.tick."

    static func identifier(for date: Date) -> String {
        identifierPrefix + String(Int64(date.timeIntervalSince1970.rounded(.down)))
    }

    static func obsoleteIdentifiers(_ pending: [String], keeping plan: [VocabularyNotificationPoint]) -> [String] {
        let desired = Set(plan.map { identifier(for: $0.date) })
        return pending.filter { $0.hasPrefix(identifierPrefix) && !desired.contains($0) }
    }

    static func make(at now: Date = .now, limit: Int = 64) -> [VocabularyNotificationPoint] {
        let topic = VocabularyCatalog.topic(for: WidgetProgressStore.selectedTopicID)
        guard !topic.words.isEmpty else { return [] }
        var date = now
        return (0..<max(0, min(64, limit))).map { _ in
            date = WidgetProgressStore.nextChange(after: date, for: topic)
            return VocabularyNotificationPoint(date: date, word: topic.words[WidgetProgressStore.currentIndex(for: topic, at: date)], topicName: topic.name)
        }
    }
}
