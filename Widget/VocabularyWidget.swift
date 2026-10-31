import SwiftUI
import WidgetKit
import AppIntents

private struct VocabularyEntry: TimelineEntry {
    let date: Date
    let topicID: String
    let topicName: String
    let word: VocabularyWord?
    let position: Int
    let total: Int
}

private struct VocabularyTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> VocabularyEntry {
        let topic = VocabularyCatalog.topics[0]
        return makeEntry(topic: topic, index: 0, date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (VocabularyEntry) -> Void) {
        WidgetProgressStore.ensureSelectedTopicInitialized()
        let topic = VocabularyCatalog.topic(for: WidgetProgressStore.selectedTopicID)
        completion(makeEntry(topic: topic, index: WidgetProgressStore.currentIndex(for: topic), date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VocabularyEntry>) -> Void) {
        WidgetProgressStore.ensureSelectedTopicInitialized()
        let topic = VocabularyCatalog.topic(for: WidgetProgressStore.selectedTopicID)
        let now = Date.now
        // Pre-schedule upcoming active-window ticks; iOS still decides when entries appear onscreen.
        let entries = VocabularyTimelineSchedule.make(for: topic, at: now).map {
            makeEntry(topic: topic, index: $0.index, date: $0.date)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func makeEntry(topic: VocabularyTopic, index: Int, date: Date) -> VocabularyEntry {
        guard !topic.words.isEmpty else {
            return VocabularyEntry(date: date, topicID: topic.id, topicName: topic.name, word: nil, position: 0, total: 0)
        }
        let safeIndex = index % topic.words.count
        return VocabularyEntry(date: date, topicID: topic.id, topicName: topic.name, word: topic.words[safeIndex],
                               position: safeIndex + 1, total: topic.words.count)
    }
}

private struct VocabularyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VocabularyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 8) {
            if let word = entry.word {
            HStack {
                Text(entry.topicName.uppercased())
                    .font(.caption2.weight(.bold)).tracking(1.1)
                    .foregroundStyle(Color(red: 0.58, green: 0.78, blue: 1))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if entry.total > 0 {
                    Text("\(entry.position)/\(entry.total)")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.65))
                        .accessibilityLabel("Từ \(entry.position) trên \(entry.total)")
                }
            }
            HStack(spacing: 6) {
                Text(word.text)
                    .font(family == .systemSmall ? .title2.bold() : .title.bold())
                    .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(intent: SpeakWordIntent(word: word.text)) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(family == .systemSmall ? .caption : .body)
                        .foregroundStyle(Color(red: 0.58, green: 0.84, blue: 1))
                }
                .accessibilityLabel("Phát âm \(word.text)")
            }
            Text("\(word.partOfSpeech)  \(word.meaning)")
                .font(family == .systemSmall ? .subheadline : .headline)
                .foregroundStyle(Color(red: 0.72, green: 0.87, blue: 1))
                .lineLimit(family == .systemSmall ? 2 : 1).minimumScaleFactor(0.7)
                .accessibilityLabel("\(word.partOfSpeech), \(word.meaning)")
            Text(word.example)
                .font(family == .systemSmall ? .caption : .subheadline)
                .italic().foregroundStyle(.white.opacity(0.86))
                .lineLimit(2).minimumScaleFactor(0.75)
                .accessibilityLabel("Ví dụ: \(word.example)")
            HStack {
                Spacer(minLength: 0)
                if family == .systemSmall {
                    Button(intent: StudiedWordIntent(topicID: entry.topicID, displayedIndex: entry.position - 1)) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3).foregroundStyle(Color(red: 0.58, green: 0.84, blue: 1))
                    }
                    .accessibilityLabel("Đã học")
                    Button(intent: NextWordIntent(topicID: entry.topicID, displayedIndex: entry.position - 1)) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3).foregroundStyle(Color(red: 0.58, green: 0.84, blue: 1))
                    }
                    .accessibilityLabel("Từ tiếp theo")
                } else {
                    Button(intent: NextWordIntent(topicID: entry.topicID, displayedIndex: entry.position - 1)) {
                        Label("Từ tiếp theo", systemImage: "arrow.right.circle.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .tint(Color(red: 0.58, green: 0.84, blue: 1))
                    Button(intent: StudiedWordIntent(topicID: entry.topicID, displayedIndex: entry.position - 1)) {
                        Label("Đã học", systemImage: "checkmark.circle.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .tint(Color(red: 0.58, green: 0.84, blue: 1))
                }
            }
            } else {
                Spacer(minLength: 0)
                Text("Chủ đề chưa có từ")
                    .font(family == .systemSmall ? .headline : .title3.bold())
                    .foregroundStyle(.white)
                Text("Mở app để thêm từ vựng")
                    .font(.caption).foregroundStyle(.white.opacity(0.78))
                Spacer(minLength: 0)
            }
        }
        .padding(family == .systemSmall ? 12 : 16)
        .containerBackground(
            LinearGradient(colors: [Color(red: 0.08, green: 0.16, blue: 0.31), Color(red: 0.12, green: 0.30, blue: 0.48)], startPoint: .topLeading, endPoint: .bottomTrailing),
            for: .widget
        )
    }
}

struct NextWordIntent: AppIntent {
    static var title: LocalizedStringResource = "Từ tiếp theo"
    @Parameter(title: "Chủ đề") var topicID: String
    @Parameter(title: "Vị trí từ đang hiển thị") var displayedIndex: Int

    init() {}

    init(topicID: String, displayedIndex: Int) {
        self.topicID = topicID
        self.displayedIndex = displayedIndex
    }

    func perform() async throws -> some IntentResult {
        let changed = WidgetProgressStore.advanceDisplayedWord(topicID: topicID, displayedIndex: displayedIndex)
        WidgetCenter.shared.reloadTimelines(ofKind: "VocabularyWidget")
        if changed { await VocabularyNotifications.reschedule() }
        return .result()
    }
}

struct StudiedWordIntent: AppIntent {
    static var title: LocalizedStringResource = "Đã học"
    @Parameter(title: "Chủ đề") var topicID: String
    @Parameter(title: "Vị trí từ đang hiển thị") var displayedIndex: Int

    init() {}

    init(topicID: String, displayedIndex: Int) {
        self.topicID = topicID
        self.displayedIndex = displayedIndex
    }

    func perform() async throws -> some IntentResult {
        let changed = WidgetProgressStore.markStudiedAndAdvance(topicID: topicID, displayedIndex: displayedIndex)
        WidgetCenter.shared.reloadTimelines(ofKind: "VocabularyWidget")
        if changed { await VocabularyNotifications.reschedule() }
        return .result()
    }
}

@main
struct VocabularyWidget: Widget {
    let kind = "VocabularyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VocabularyTimelineProvider()) { entry in
            VocabularyWidgetView(entry: entry)
        }
        .configurationDisplayName("Từ vựng mỗi ngày")
        .description("Học một từ theo chủ đề bạn chọn.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
