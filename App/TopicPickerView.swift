import SwiftUI
import WidgetKit

private final class TopicSelectionModel: ObservableObject {
    @Published var showingSchedule = false
    @Published var selectedID = WidgetProgressStore.selectedTopicID
    @Published var now = Date.now
    @Published var showingResetConfirmation = false
    @Published var resetTopicID: String?
    @Published var showingVocabulary = false
    @Published var showingCreateTopic = false
    @Published var topicName = ""
    @Published var topicCreationError: String?
    @Published var refreshID = UUID()

    init() {
        WidgetProgressStore.ensureSelectedTopicInitialized()
        selectedID = WidgetProgressStore.selectedTopicID
    }
}

struct TopicPickerView: View {
    @StateObject private var model = TopicSelectionModel()

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
                .accessibilityValue(model.selectedID == topic.id ? "Đang chọn" : "Chưa chọn")
                .accessibilityHint("Chạm để học chủ đề này")
                .contextMenu {
                    Button(role: .destructive) {
                        model.resetTopicID = topic.id
                        model.showingResetConfirmation = true
                    } label: {
                        Label("Bắt đầu lại từ đầu", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Chọn chủ đề")
            .sheet(isPresented: $model.showingSchedule, onDismiss: { model.refreshID = UUID(); model.now = .now }) {
                VocabularyScheduleSettingsView()
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button { model.showingSchedule = true } label: { Label("Lịch học và thông báo", systemImage: "clock") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.showingCreateTopic = true } label: { Label("Tạo chủ đề", systemImage: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.showingVocabulary = true } label: {
                        Label("Từ của tao", systemImage: "text.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $model.showingVocabulary, onDismiss: { model.refreshID = UUID(); model.now = .now }) {
                CustomVocabularyView(topicID: model.selectedID)
            }
            .sheet(isPresented: $model.showingCreateTopic) {
                NavigationStack {
                    Form {
                        Section("Tên chủ đề") {
                            TextField("Ví dụ: Mô tả hệ thống", text: $model.topicName)
                                .textInputAutocapitalization(.words)
                        }
                        if let message = model.topicCreationError {
                            Text(message).foregroundStyle(.red)
                        }
                    }
                    .navigationTitle("Chủ đề mới")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Huỷ") { model.showingCreateTopic = false; model.topicName = ""; model.topicCreationError = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Tạo") { createTopic() }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .id(model.refreshID)
            .alert("Bắt đầu lại chủ đề này?", isPresented: $model.showingResetConfirmation) {
                Button("Huỷ", role: .cancel) { model.resetTopicID = nil }
                Button("Bắt đầu lại", role: .destructive) {
                    guard let topicID = model.resetTopicID else { return }
                    WidgetProgressStore.resetProgress(for: VocabularyCatalog.topic(for: topicID))
                    model.now = .now
                    WidgetCenter.shared.reloadAllTimelines()
                    Task { await VocabularyNotifications.reschedule() }
                    model.resetTopicID = nil
                }
            } message: {
                Text("Tiến độ đã lưu của chủ đề này sẽ được đưa về từ đầu.")
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    guard !Task.isCancelled else { break }
                    model.now = .now
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Widget lần lượt đổi từ sau khoảng \(WidgetProgressStore.schedule.intervalMinutes) phút trong giờ học. iOS có thể làm mới trễ hơn.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding()
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }

    private func subtitle(for topic: VocabularyTopic) -> String {
        let index = WidgetProgressStore.currentIndex(for: topic, at: model.now)
        guard !topic.words.isEmpty else { return model.selectedID == topic.id ? "Đang chọn · chưa có từ · dùng ‘Từ của tao’ để thêm" : "Chưa có từ · chọn chủ đề rồi thêm từ" }
        if model.selectedID == topic.id {
            let seconds = WidgetProgressStore.secondsUntilNextChange(for: topic, at: model.now)
            let minutes = max(1, Int(ceil(Double(seconds) / 60)))
            return "Đang chọn · từ \(index + 1)/\(topic.words.count) · \(topic.words[index].text) · đổi sau ~\(minutes) phút"
        }
        if WidgetProgressStore.hasVisited(topic) {
            return "Tiếp tục từ \(index + 1)/\(topic.words.count) · \(topic.words[index].text)"
        }
        return "\(topic.words.count) từ · Chưa bắt đầu"
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
            model.topicCreationError = "Nhập tên chủ đề trước đã."
        } catch CustomTopicStore.CreateError.duplicateName {
            model.topicCreationError = "Tên chủ đề này đã tồn tại. Hãy chọn tên khác."
        } catch {
            model.topicCreationError = "Không lưu được chủ đề. Hãy thử lại."
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
                Section("Từ trong chủ đề · \(topic.name)") {
                    if topic.words.isEmpty {
                        ContentUnavailableView("Chủ đề chưa có từ", systemImage: "text.badge.plus", description: Text("Nhấn + để thêm từ hoặc dán danh sách từ vựng."))
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
            .navigationTitle("Từ vựng")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Đóng") { dismiss() } }
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
    @State private var mode = "Một từ"
    @State private var batchText = ""
    @State private var errorMessage: String?
    @State private var dismissAfterMessage = false

    private let partsOfSpeech = ["(n)", "(v)", "(adj)", "(adv)", "(prep)", "(conj)", "(pron)", "(interj)"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Cách thêm", selection: $mode) {
                    Text("Một từ").tag("Một từ")
                    Text("Danh sách").tag("Danh sách")
                }.pickerStyle(.segmented)
                if mode == "Danh sách" {
                    Section {
                        Text("Mỗi từ gồm 8 dòng: từ, loại từ, nghĩa tiếng Việt, rồi 5 câu ví dụ. Ngăn cách các từ bằng dòng trống.")
                            .font(.footnote).foregroundStyle(.secondary)
                        TextEditor(text: $batchText).frame(minHeight: 240).font(.body.monospaced())
                    } header: { Text("Dán danh sách") } footer: {
                        Text("Ví dụ:\nalignment\n(n)\nđồng thuận\nWe need alignment on the plan.\nWe reached alignment yesterday.\nThe team is aligned.\nCan we align on this?\nI agree with that alignment.")
                    }
                } else {
                Section("Từ mới") {
                    TextField("Từ tiếng Anh", text: $text)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Loại từ", selection: $partOfSpeech) {
                        ForEach(partsOfSpeech, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Nghĩa tiếng Việt", text: $meaning)
                }
                Section("5 câu ví dụ") {
                    ForEach(0..<5, id: \.self) { index in
                        TextField("Ví dụ \(index + 1)", text: $examples[index], axis: .vertical)
                            .lineLimit(2...4).textInputAutocapitalization(.sentences)
                    }
                }
                }
            }
            .navigationTitle("Thêm từ")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(mode == "Danh sách" ? "Nhập" : "Lưu") { mode == "Danh sách" ? saveBatch() : save() } }
            }
            .alert("Chưa lưu được từ", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
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
            errorMessage = "Từ này đã có trong chủ đề."
        } catch CustomVocabularyStore.AddError.invalidExamples {
            errorMessage = "Hãy nhập đủ 5 câu ví dụ."
        } catch CustomVocabularyStore.AddError.invalidWord {
            errorMessage = "Hãy nhập từ tiếng Anh."
        } catch CustomVocabularyStore.AddError.invalidMeaning {
            errorMessage = "Hãy nhập nghĩa tiếng Việt."
        } catch {
            errorMessage = "Không thể lưu từ này."
        }
    }

    private func saveBatch() {
        do {
            let result = try CustomVocabularyStore.addBatch(batchText, to: topicID)
            guard !result.added.isEmpty else {
                errorMessage = result.issues.isEmpty ? "Chưa có mục từ nào để nhập." : result.issues.map { "Mục \($0.block): \($0.message)." }.joined(separator: "\n")
                return
            }
            WidgetCenter.shared.reloadAllTimelines()
            Task { await VocabularyNotifications.reschedule() }
            var summary = "Đã thêm \(result.added.count) từ."
            if !result.issues.isEmpty {
                summary += "\n" + result.issues.map { "Mục \($0.block): \($0.message)." }.joined(separator: "\n")
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
            errorMessage = "Không thể lưu danh sách. Hãy thử lại."
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
