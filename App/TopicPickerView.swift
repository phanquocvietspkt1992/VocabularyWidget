import SwiftUI
import WidgetKit

final class TopicSelectionModel: ObservableObject {
    @Published var showingSchedule = false
    @Published var showingBackup = false
    @Published var showingReview = false
    @Published var selectedID = WidgetProgressStore.selectedTopicID
    @Published var now = Date.now
    @Published var showingResetConfirmation = false {
        didSet {
            if showingResetConfirmation { presentedSheets.insert("reset") }
        }
    }
    @Published var showingDeleteTopicConfirmation = false {
        didSet {
            if showingDeleteTopicConfirmation { presentedSheets.insert("delete-topic") }
        }
    }
    @Published var resetTopicID: String?
    @Published var deleteTopicID: String?
    @Published var deleteTopicName: String?
    @Published var deleteTopicError: String?
    @Published var showingVocabulary = false
    @Published var showingCreateTopic = false
    @Published var topicName = ""
    @Published var topicCreationError: String?
    @Published var refreshID = UUID()
    @Published var presentedSheets: Set<String> = []

    var blocksWordDetail: Bool {
        !presentedSheets.isEmpty || showingSchedule || showingBackup || showingReview || showingVocabulary || showingCreateTopic
            || showingResetConfirmation || showingDeleteTopicConfirmation
    }

    func trackPresentedSheets() {
        for (name, showing) in [("schedule", showingSchedule), ("backup", showingBackup), ("review", showingReview),
                                ("vocabulary", showingVocabulary), ("create", showingCreateTopic),
                                ("reset", showingResetConfirmation)] where showing {
            presentedSheets.insert(name)
        }
    }

    init() {
        WidgetProgressStore.ensureSelectedTopicInitialized()
        selectedID = WidgetProgressStore.selectedTopicID
    }
}

struct TopicPickerView: View {
    @ObservedObject var model: TopicSelectionModel
    @ObservedObject var detailRouter: VocabularyDetailRouter

    var body: some View {
        NavigationStack {
            List(VocabularyCatalog.topics) { topic in
                Button {
                    guard WidgetProgressStore.selectedTopicID != topic.id else { return }
                    WidgetProgressStore.selectTopic(topic)
                    model.selectedID = topic.id
                    model.now = .now
                    WidgetCenter.shared.reloadAllTimelines()
                    Task { await VocabularyNotifications.reschedule() }
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(topic.name).font(.headline).foregroundStyle(.primary)
                            Text(subtitle(for: topic))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.selectedID == topic.id {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3).foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(topic.name). \(subtitle(for: topic))")
                .accessibilityValue(model.selectedID == topic.id ? "Selected" : "Not selected")
                .accessibilityHint("Tap to study this topic")
                .contextMenu {
                    Button(role: .destructive) {
                        model.resetTopicID = topic.id
                        model.showingResetConfirmation = true
                    } label: {
                        Label("Restart Progress", systemImage: "arrow.counterclockwise")
                    }
                    if !VocabularyCatalog.builtInTopicIDs.contains(topic.id) {
                        Divider()
                        Button(role: .destructive) {
                            model.deleteTopicID = topic.id
                            model.deleteTopicName = topic.name
                            model.deleteTopicError = nil
                            model.showingDeleteTopicConfirmation = true
                        } label: {
                            Label("Delete Topic", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Choose a Topic")
            .sheet(isPresented: $model.showingSchedule, onDismiss: { model.refreshID = UUID(); model.now = .now; drainWordDetail(after: "schedule") }) {
                VocabularyScheduleSettingsView()
            }
            .sheet(isPresented: $model.showingBackup, onDismiss: { drainWordDetail(after: "backup") }) {
                VocabularyBackupView {
                    model.selectedID = WidgetProgressStore.selectedTopicID
                    model.now = .now
                    model.refreshID = UUID()
                }
            }
            .sheet(isPresented: $model.showingReview, onDismiss: { drainWordDetail(after: "review") }) { VocabularyDailyReviewView() }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button { model.showingSchedule = true } label: { Label("Study Schedule & Notifications", systemImage: "clock") }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { model.showingReview = true } label: { Label("Daily Review", systemImage: "rectangle.on.rectangle") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.showingCreateTopic = true } label: { Label("Create Topic", systemImage: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { model.showingVocabulary = true } label: { Label("My Vocabulary", systemImage: "text.badge.plus") }
                        Button { model.showingBackup = true } label: { Label("Backup & Restore", systemImage: "externaldrive") }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $model.showingVocabulary, onDismiss: { model.refreshID = UUID(); model.now = .now; drainWordDetail(after: "vocabulary") }) {
                CustomVocabularyView(topicID: model.selectedID)
            }
            .sheet(isPresented: $model.showingCreateTopic, onDismiss: { drainWordDetail(after: "create") }) {
                NavigationStack {
                    Form {
                        Section("Topic Name") {
                            TextField("e.g. System Design", text: $model.topicName)
                                .textInputAutocapitalization(.words)
                        }
                        if let message = model.topicCreationError {
                            Text(message).foregroundStyle(.red)
                        }
                    }
                    .navigationTitle("New Topic")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { model.showingCreateTopic = false; model.topicName = ""; model.topicCreationError = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Create") { createTopic() }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .id(model.refreshID)
            .sheet(isPresented: $model.showingResetConfirmation, onDismiss: {
                model.resetTopicID = nil
                drainWordDetail(after: "reset")
            }) {
                VStack(spacing: 20) {
                    Text("Restart this topic?").font(.headline).accessibilityAddTraits(.isHeader)
                    Text("Saved progress for this topic will be reset to the beginning.")
                        .multilineTextAlignment(.center)
                    Button("Restart", role: .destructive) {
                        if let topicID = model.resetTopicID {
                            WidgetProgressStore.resetProgress(for: VocabularyCatalog.topic(for: topicID))
                            model.now = .now
                            WidgetCenter.shared.reloadAllTimelines()
                            Task { await VocabularyNotifications.reschedule() }
                        }
                        model.resetTopicID = nil
                        model.showingResetConfirmation = false
                    }
                    Button("Cancel", role: .cancel) {
                        model.resetTopicID = nil
                        model.showingResetConfirmation = false
                    }
                }
                .padding()
                .presentationDetents([.height(260)])
            }
            .sheet(isPresented: $model.showingDeleteTopicConfirmation, onDismiss: {
                model.deleteTopicID = nil
                model.deleteTopicName = nil
                model.deleteTopicError = nil
                model.now = .now
                drainWordDetail(after: "delete-topic")
            }) {
                NavigationStack {
                    VStack(spacing: 20) {
                        Text("Delete \(model.deleteTopicName ?? "this topic")?")
                            .font(.headline).accessibilityAddTraits(.isHeader)
                        Text("This permanently deletes the topic, its words, progress, study history, and review data. This cannot be undone.")
                            .multilineTextAlignment(.center)
                        if let error = model.deleteTopicError {
                            Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                        }
                        Button("Delete Topic", role: .destructive) { deleteCustomTopic() }
                            .buttonStyle(.borderedProminent)
                        Button("Cancel", role: .cancel) { model.showingDeleteTopicConfirmation = false }
                    }
                    .padding()
                    .navigationTitle("Delete Topic")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { model.showingDeleteTopicConfirmation = false }
                        }
                    }
                }
                .presentationDetents([.height(310)])
            }
            .onChange(of: [model.showingSchedule, model.showingBackup, model.showingReview,
                           model.showingVocabulary, model.showingCreateTopic, model.showingResetConfirmation]) { _, _ in
                model.trackPresentedSheets()
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    guard !Task.isCancelled else { break }
                    model.now = .now
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    Text(versionLabel)
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("The widget advances to the next word about every \(WidgetProgressStore.schedule.intervalMinutes) minutes during study hours. iOS may refresh it later.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center).padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
        }
    }

    private func drainWordDetail(after sheet: String? = nil) {
        if let sheet { model.presentedSheets.remove(sheet) }
        detailRouter.drain(blocked: model.blocksWordDetail)
    }

    private var versionLabel: String {
        guard let version = Self.formattedVersion(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        ) else { return "Version unavailable" }
        return "Version \(version)"
    }

    private static func formattedVersion(_ version: String?, build: String?) -> String? {
        guard let version, let build else { return nil }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, (1...2).contains(parts[1].count), (1...2).contains(parts[2].count),
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              !build.isEmpty, build.utf8.allSatisfy({ (48...57).contains($0) }),
              let year = Int(parts[0]), year > 0,
              let month = Int(parts[1]), (1...12).contains(month),
              let day = Int(parts[2]), day > 0,
              let deployment = Int(build), deployment > 0 else { return nil }
        let isLeapYear = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
        let daysInMonth = [31, isLeapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard day <= daysInMonth[month - 1] else { return nil }
        return String(format: "%02d.%02d.%04d", day, month, year) + ".\(deployment)"
    }

    private func subtitle(for topic: VocabularyTopic) -> String {
        let index = WidgetProgressStore.currentIndex(for: topic, at: model.now)
        guard !topic.words.isEmpty else { return model.selectedID == topic.id ? "Selected · no words yet · use “My Vocabulary” to add some" : "No words yet · select this topic, then add words" }
        if model.selectedID == topic.id {
            let seconds = WidgetProgressStore.secondsUntilNextChange(for: topic, at: model.now)
            let minutes = max(1, Int(ceil(Double(seconds) / 60)))
            return "Selected · word \(index + 1) of \(topic.words.count) · \(topic.words[index].text) · changes in ~\(minutes) min"
        }
        if WidgetProgressStore.hasVisited(topic) {
            return "Continue at \(index + 1) of \(topic.words.count) · \(topic.words[index].text)"
        }
        return "\(topic.words.count) words · Not started"
    }

    private func createTopic() {
        do {
            let topic = try CustomTopicStore.create(name: model.topicName)
            WidgetProgressStore.selectTopic(VocabularyCatalog.topic(for: topic.id))
            model.selectedID = topic.id
            model.topicName = ""
            model.topicCreationError = nil
            model.now = .now
            model.refreshID = UUID()
            model.showingCreateTopic = false
            WidgetCenter.shared.reloadAllTimelines()
            Task { await VocabularyNotifications.reschedule() }
        } catch CustomTopicStore.CreateError.emptyName {
            model.topicCreationError = "Enter a topic name."
        } catch CustomTopicStore.CreateError.duplicateName {
            model.topicCreationError = "This topic name already exists. Choose another name."
        } catch {
            model.topicCreationError = "Could not save the topic. Try again."
        }
    }

    private func deleteCustomTopic() {
        guard let topicID = model.deleteTopicID else { return }
        do {
            model.selectedID = try CustomTopicStore.delete(id: topicID)
            model.now = .now
            model.deleteTopicError = nil
            model.showingDeleteTopicConfirmation = false
            WidgetCenter.shared.reloadAllTimelines()
            Task { await VocabularyNotifications.reschedule() }
        } catch {
            model.deleteTopicError = error.localizedDescription
        }
    }
}

private struct CustomVocabularyView: View {
    let topicID: String
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdd = false
    @State private var refreshID = UUID()

    private var topic: VocabularyTopic { VocabularyCatalog.topic(for: topicID) }

    var body: some View {
        NavigationStack {
            List {
                Section("Words in Topic · \(topic.name)") {
                    if topic.words.isEmpty {
                        ContentUnavailableView("No Words in This Topic", systemImage: "text.badge.plus", description: Text("Tap + to add a word or paste a vocabulary list."))
                    }
                    ForEach(topic.words) { word in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(word.text).font(.headline); Text(word.partOfSpeech).foregroundStyle(.secondary) }
                            Text(word.meaning).foregroundStyle(.secondary)
                            ForEach(Array(word.examples.enumerated()), id: \.offset) { index, example in
                                Text("\(index + 1). \(example)").font(.subheadline)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
            .id(refreshID)
            .navigationTitle("Vocabulary")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button { showingAdd = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showingAdd, onDismiss: {
                refreshID = UUID()
                WidgetCenter.shared.reloadAllTimelines()
                Task { await VocabularyNotifications.reschedule() }
            }) {
                AddCustomWordView(topicID: topicID)
            }
        }
    }
}

private struct AddCustomWordView: View {
    let topicID: String
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var partOfSpeech = "(n)"
    @State private var meaning = ""
    @State private var examples = Array(repeating: "", count: 5)
    @State private var mode = "Single Word"
    @State private var batchText = ""
    @State private var errorMessage: String?
    @State private var dismissAfterMessage = false

    private let partsOfSpeech = ["(n)", "(v)", "(adj)", "(adv)", "(prep)", "(conj)", "(pron)", "(interj)"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Add Method", selection: $mode) {
                    Text("Single Word").tag("Single Word")
                    Text("List").tag("List")
                }.pickerStyle(.segmented)
                if mode == "List" {
                    Section {
                        Text("Each word uses 8 lines: word, part of speech, Vietnamese meaning, then 5 example sentences. Separate words with a blank line.")
                            .font(.footnote).foregroundStyle(.secondary)
                        TextEditor(text: $batchText).frame(minHeight: 240).font(.body.monospaced())
                    } header: { Text("Paste a List") } footer: {
                        Text("Example:\nalignment\n(n)\nđồng thuận\nWe need alignment on the plan.\nWe reached alignment yesterday.\nThe team is aligned.\nCan we align on this?\nI agree with that alignment.")
                    }
                } else {
                Section("New Word") {
                    TextField("English Word", text: $text)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Part of Speech", selection: $partOfSpeech) {
                        ForEach(partsOfSpeech, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Meaning (Vietnamese)", text: $meaning)
                }
                Section("5 Example Sentences") {
                    ForEach(0..<5, id: \.self) { index in
                        TextField("Example \(index + 1)", text: $examples[index], axis: .vertical)
                            .lineLimit(2...4).textInputAutocapitalization(.sentences)
                    }
                }
                }
            }
            .navigationTitle("Add Vocabulary")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(mode == "List" ? "Import" : "Save") { mode == "List" ? saveBatch() : save() } }
            }
            .alert("Unable to Save Word", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil; if dismissAfterMessage { dismiss() }; dismissAfterMessage = false }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        do {
            try CustomVocabularyStore.add(text: text, partOfSpeech: partOfSpeech, meaning: meaning, examples: examples, to: topicID)
            WidgetCenter.shared.reloadAllTimelines()
            Task { await VocabularyNotifications.reschedule() }
            dismiss()
        } catch CustomVocabularyStore.AddError.duplicate {
            errorMessage = "This word is already in the topic."
        } catch CustomVocabularyStore.AddError.invalidExamples {
            errorMessage = "Enter all five example sentences."
        } catch CustomVocabularyStore.AddError.invalidWord {
            errorMessage = "Enter an English word."
        } catch CustomVocabularyStore.AddError.invalidMeaning {
            errorMessage = "Enter the Vietnamese meaning."
        } catch {
            errorMessage = "Could not save this word."
        }
    }

    private func saveBatch() {
        do {
            let result = try CustomVocabularyStore.addBatch(batchText, to: topicID)
            guard !result.added.isEmpty else {
                errorMessage = result.issues.isEmpty ? "No words to import." : result.issues.map { "Item \($0.block): \($0.message)." }.joined(separator: "\n")
                return
            }
            WidgetCenter.shared.reloadAllTimelines()
            Task { await VocabularyNotifications.reschedule() }
            var summary = "Added \(result.added.count) word(s)."
            if !result.issues.isEmpty {
                summary += "\n" + result.issues.map { "Item \($0.block): \($0.message)." }.joined(separator: "\n")
                let failedBlocks = Set(result.issues.map(\.block))
                batchText = Self.blocks(in: batchText)
                    .enumerated()
                    .filter { failedBlocks.contains($0.offset + 1) }
                    .map(\.element)
                    .joined(separator: "\n\n")
            } else {
                batchText = ""
                dismissAfterMessage = true
            }
            errorMessage = summary
        } catch {
            errorMessage = "Could not import the list. Try again."
        }
    }

    private static func blocks(in source: String) -> [String] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var blocks: [String] = []
        var current: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !current.isEmpty {
                    blocks.append(current.joined(separator: "\n"))
                    current = []
                }
            } else {
                current.append(trimmed)
            }
        }
        if !current.isEmpty { blocks.append(current.joined(separator: "\n")) }
        return blocks
    }
}
