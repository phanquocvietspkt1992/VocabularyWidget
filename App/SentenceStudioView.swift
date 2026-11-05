import SwiftUI
import UniformTypeIdentifiers

private struct SentenceEditSession: Identifiable {
    let id = UUID()
    let topic: SentenceTopic
    let expected: [SentenceTopic]
}

private struct SentencePlaySession: Identifiable {
    let id = UUID()
    let round: SentenceRound
}

private struct SentenceRecoveryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws { bytes = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}

struct SentenceStudioView: View {
    @StateObject private var model = SentenceLibraryModel()
    @StateObject private var historyModel = SentenceRoundHistoryModel()
    @State private var editor: SentenceEditSession?
    @State private var exportingRecovery = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SentenceRoundHistoryView(model: historyModel)
                    } label: {
                        Label("Answer History", systemImage: "clock.arrow.circlepath")
                    }
                }
                if let error = model.error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("Reload", systemImage: "arrow.clockwise") { model.reload() }
                        if model.recoveryBytes != nil {
                            Button("Export Recovery Data", systemImage: "square.and.arrow.up") { exportingRecovery = true }
                        }
                    }
                }
                if let exportError { Text(exportError).foregroundStyle(.red) }
                if model.topics.isEmpty && model.error == nil {
                    ContentUnavailableView("No Sentence Topics", systemImage: "text.bubble")
                }
                ForEach(model.topics) { topic in
                    NavigationLink {
                        SentenceTopicView(model: model, historyModel: historyModel, topicID: topic.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(topic.name).font(.headline)
                            Text("\(topic.pairs.count) sentence pairs").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Sentence Game")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = SentenceEditSession(topic: SentenceTopic(name: "", pairs: [SentencePair(english: "", vietnamese: "")]), expected: model.topics)
                    } label: { Label("New Sentence Topic", systemImage: "plus") }
                    .disabled(!model.canEdit)
                }
            }
            .sheet(item: $editor) { session in
                SentenceTopicEditor(model: model, session: session)
            }
            .fileExporter(isPresented: $exportingRecovery, document: SentenceRecoveryDocument(bytes: model.recoveryBytes ?? Data()), contentType: .json,
                          defaultFilename: "sentence-recovery") { result in
                if case .failure(let error) = result { exportError = error.localizedDescription }
            }
        }
    }
}

private struct SentenceTopicEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: SentenceLibraryModel
    let session: SentenceEditSession
    @State private var draft: SentenceTopic
    @State private var error: String?
    @State private var pasted = ""
    @State private var showingPaste = false

    init(model: SentenceLibraryModel, session: SentenceEditSession) {
        self.model = model
        self.session = session
        _draft = State(initialValue: session.topic)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Topic Name") { TextField("Topic name", text: $draft.name) }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if let message = model.error { Section { Text(message).foregroundStyle(.red) } }
                ForEach($draft.pairs) { $pair in
                    Section("Sentence Pair") {
                        TextField("English", text: $pair.english, axis: .vertical)
                            .textInputAutocapitalization(.sentences)
                        TextField("Vietnamese", text: $pair.vietnamese, axis: .vertical)
                            .textInputAutocapitalization(.sentences)
                        Button(role: .destructive) {
                            let id = pair.id
                            draft.pairs.removeAll { $0.id == id }
                        } label: {
                            Label("Remove Pair", systemImage: "trash")
                        }
                    }
                }
                Section {
                    Button("Add Pair", systemImage: "plus") { draft.pairs.append(SentencePair(english: "", vietnamese: "")) }
                    Button("Paste Tab-Separated Pairs", systemImage: "doc.on.clipboard") { showingPaste = true }
                }
            }
            .navigationTitle(session.expected.contains(where: { $0.id == draft.id }) ? "Edit Sentence Topic" : "New Sentence Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try model.upsert(draft, expected: session.expected); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(!model.canEdit)
                }
            }
            .sheet(isPresented: $showingPaste) {
                NavigationStack {
                    Form {
                        Section("English, then Vietnamese") {
                            Text("Put the English sentence on one line and its Vietnamese meaning on the next. Leave a blank line between pairs. Tab-separated rows still work.")
                                .font(.footnote).foregroundStyle(.secondary)
                            TextEditor(text: $pasted).frame(minHeight: 240)
                                .autocorrectionDisabled().textInputAutocapitalization(.never)
                        }
                        if let error { Text(error).foregroundStyle(.red) }
                    }
                    .navigationTitle("Paste Pairs")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingPaste = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                do {
                                    let additions = try SentenceTopic.parsePairs(pasted)
                                    var candidate = draft
                                    candidate.pairs.removeAll { $0.english.isEmpty && $0.vietnamese.isEmpty }
                                    candidate.pairs += additions
                                    _ = try candidate.validated()
                                    draft = candidate
                                    pasted = ""
                                    error = nil
                                    showingPaste = false
                                } catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct SentenceTopicView: View {
    @ObservedObject var model: SentenceLibraryModel
    @ObservedObject var historyModel: SentenceRoundHistoryModel
    let topicID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var mode = SentenceMode.stage
    @State private var editor: SentenceEditSession?
    @State private var playSession: SentencePlaySession?
    @State private var error: String?
    @State private var deleting = false
    private var topic: SentenceTopic? { model.topics.first { $0.id == topicID } }

    var body: some View {
        List {
            if let topic {
                Section {
                    Picker("Mode", selection: $mode) { ForEach(SentenceMode.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                    Button {
                        do { playSession = SentencePlaySession(round: try SentenceRound(topic: topic, mode: mode)) }
                        catch { self.error = error.localizedDescription }
                    } label: { Label("Play \(mode.rawValue)", systemImage: "play.fill") }
                        .disabled(topic.pairs.count < 4 || model.error != nil)
                    if topic.pairs.count < 4 {
                        Text(SentenceGameError.tooSmall.localizedDescription).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
                ForEach(topic.pairs) { pair in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(pair.english).font(.headline)
                        Text(pair.vietnamese).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            } else { ContentUnavailableView("Topic Unavailable", systemImage: "text.bubble") }
        }
        .navigationTitle(topic?.name ?? "Sentence Topic")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil") {
                        if let topic { editor = SentenceEditSession(topic: topic, expected: model.topics) }
                    }
                    Button("Delete Topic", systemImage: "trash", role: .destructive) { deleting = true }
                } label: { Label("Topic Actions", systemImage: "ellipsis.circle") }
                    .disabled(!model.canEdit || topic == nil)
            }
        }
        .sheet(item: $editor) { SentenceTopicEditor(model: model, session: $0) }
        .fullScreenCover(item: $playSession) { SentenceGameView(initialRound: $0.round, historyModel: historyModel) }
        .confirmationDialog("Delete this sentence topic and all its pairs?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete Topic", role: .destructive) {
                do { try model.delete(topicID, expected: model.topics); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}

private struct SentenceRoundHistoryView: View {
    @ObservedObject var model: SentenceRoundHistoryModel

    var body: some View {
        List {
            if let error = model.error {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("Reload", systemImage: "arrow.clockwise") { model.reload() }
                }
            }
            if model.newestFirst.isEmpty && model.error == nil {
                ContentUnavailableView("No Answer History", systemImage: "clock.arrow.circlepath")
            }
            ForEach(model.newestFirst) { record in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.questionVietnamese).font(.headline)
                        Text("Chosen: \(record.selectedLetter). \(record.selectedEnglish)")
                        Text("Correct: \(record.correctEnglish)").foregroundStyle(.secondary)
                        Label(record.isCorrect ? "Correct" : "Incorrect",
                              systemImage: record.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(record.isCorrect ? .green : .red)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(record.topicName) · \(record.mode.rawValue)")
                        Text(record.answeredAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
        }
        .navigationTitle("Answer History")
        .onAppear { model.reload() }
    }
}

private struct SentenceGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var audio = SentenceAudio()
    @StateObject private var revealController = SentenceRevealController()
    @ObservedObject private var historyModel: SentenceRoundHistoryModel
    @State private var round: SentenceRound
    @State private var exiting = false
    @State private var initialReadRequested = false
    @State private var error: String?
    private var mint: Color {
        round.mode == .stage ? Color(red: 0.35, green: 0.95, blue: 0.71) : Color(red: 0.04, green: 0.42, blue: 0.24)
    }
    private var coral: Color {
        round.mode == .stage ? Color(red: 1, green: 0.42, blue: 0.37) : Color(red: 0.76, green: 0.12, blue: 0.12)
    }
    private var revealing: Bool { revealController.isRevealing }
    private let amber = Color(red: 1, green: 0.74, blue: 0.28)

    init(initialRound: SentenceRound, historyModel: SentenceRoundHistoryModel) {
        _round = State(initialValue: initialRound)
        _audio = StateObject(wrappedValue: SentenceAudio(stage: initialRound.mode == .stage))
        _historyModel = ObservedObject(initialValue: historyModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if round.mode == .stage {
                    SentenceStageBackdrop(animated: scenePhase == .active && !reduceMotion, suspense: revealing)
                } else { Color(.systemBackground).ignoresSafeArea() }
                GeometryReader { geometry in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(round.mode.rawValue.uppercased()).font(.system(.caption, design: .rounded, weight: .bold))
                                    .foregroundStyle(round.mode == .stage ? amber : Color.primary)
                                Spacer()
                                Text("\(round.score) / \(round.questions.count)").font(.headline.monospacedDigit())
                            }
                            if round.finished { results }
                            else if let question = round.current {
                                ProgressView(value: Double(round.index), total: Double(round.questions.count)).tint(mint)
                                Text("Question \(round.index + 1) of \(round.questions.count)").font(.subheadline)
                                questionPrompt(question.pair.vietnamese)
                                narrationControls(question)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: round.mode == .stage && geometry.size.width >= 760 && !dynamicTypeSize.isAccessibilitySize ? 2 : 1), spacing: 12) {
                                    ForEach(Array(question.options.enumerated()), id: \.element.id) { index, option in
                                        optionButton(option, index: index)
                                    }
                                }
                                if revealing {
                                    Label("Answer Locked", systemImage: "hourglass")
                                        .font(.system(.headline, design: .rounded)).foregroundStyle(amber)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .accessibilityAddTraits(.updatesFrequently)
                                }
                                if round.revealed {
                                    Label(round.answers.last?.correct == true ? "Correct" : "Incorrect", systemImage: round.answers.last?.correct == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.headline).foregroundStyle(round.answers.last?.correct == true ? mint : coral)
                                    Text(question.pair.english).font(.headline)
                                }
                            }
                            if let error { Text(error).foregroundStyle(coral) }
                            if let error = audio.error { Text(error).font(.footnote).foregroundStyle(coral) }
                            if let error = audio.narrationError { Text(error).font(.footnote).foregroundStyle(coral) }
                            if let error = historyModel.error { Text(error).font(.footnote).foregroundStyle(coral) }
                        }
                        .padding(round.mode == .stage ? 12 : 16)
                        .frame(maxWidth: round.mode == .stage ? 960 : 700).frame(maxWidth: .infinity)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                primaryAction
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .background(round.mode == .stage ? Color.black.opacity(0.9) : Color(.systemBackground))
            }
            .foregroundStyle(round.mode == .stage ? .white : Color.primary)
            .navigationTitle(round.topic.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { audio.stopNarration(); exiting = true } label: { Label("Exit Round", systemImage: "xmark") }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).help("Exit Round")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if round.mode == .stage {
                            Toggle(isOn: $audio.musicEnabled) { Label("Music", systemImage: "music.note") }
                        }
                        Toggle(isOn: $audio.effectsEnabled) { Label("Sound Effects", systemImage: "speaker.wave.2") }
                        Toggle(isOn: $audio.narratorEnabled) { Label("System Narrator", systemImage: "person.wave.2") }
                        englishVoiceMenu
                        Button("Resume Audio", systemImage: "play.circle") {
                            if scenePhase == .active { audio.activate(stage: round.mode == .stage) }
                        }
                    } label: { Label("Audio", systemImage: "speaker.wave.2.circle") }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).help("Audio")
                }
            }
            .preferredColorScheme(round.mode == .stage ? .dark : nil)
            .transaction { transaction in
                if reduceMotion || scenePhase != .active { transaction.animation = nil; transaction.disablesAnimations = true }
            }
            .confirmationDialog("Exit this round?", isPresented: $exiting, titleVisibility: .visible) {
                Button("Exit Round", role: .destructive) { stop(); dismiss() }
            }
            .onAppear {
                if scenePhase == .active {
                    audio.activate(stage: round.mode == .stage)
                    if !initialReadRequested {
                        initialReadRequested = true
                        audio.readNewQuestion(round.current)
                    }
                }
            }
            .onDisappear { stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { stop() }
            }
        }
    }

    private func narrationControls(_ question: SentenceQuestion) -> some View {
        HStack(spacing: 12) {
            Button { audio.listen(question) } label: {
                Label("Listen", systemImage: "speaker.wave.2.fill")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .help("Replay English Answer Choices")
            .disabled(!audio.narratorEnabled || revealing || scenePhase != .active)
            Button { audio.stopNarration() } label: {
                Label("Stop", systemImage: "stop.fill").frame(minWidth: 44, minHeight: 44)
            }
            .help("Stop Narrator").disabled(!audio.narration.pending)
            if audio.narration.pending {
                Text(audio.narration.speaking ? "Reading" : "Starting...").font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .buttonStyle(.bordered)
    }

    private var englishVoiceMenu: some View {
        return Menu {
            if audio.installedEnglishVoices.isEmpty { Text("No Installed English Voice") }
            else {
                Picker("English Voice", selection: $audio.englishVoiceID) {
                    ForEach(audio.installedEnglishVoices) { voice in
                        Text(voice.name).tag(voice.id)
                    }
                }
            }
        } label: { Label("English Voice", systemImage: "waveform") }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if round.finished {
            Button { stop(); dismiss() } label: {
                Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
        } else if round.revealed {
            Button {
                audio.stopNarration()
                audio.stopEffect()
                round.advance()
                if round.finished { audio.play(.finish) }
                else { audio.readNewQuestion(round.current) }
            } label: {
                Label(round.index + 1 == round.questions.count ? "Results" : "Next", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent).tint(round.mode == .stage ? mint : .accentColor)
            .disabled(scenePhase != .active)
        } else if round.mode == .stage {
            Button { confirmWithSuspense() } label: {
                Label(revealing ? "Revealing..." : "Confirm Answer", systemImage: revealing ? "hourglass" : "checkmark")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent).tint(amber).foregroundStyle(.black)
            .disabled(round.selectedID == nil || revealing || scenePhase != .active
                || (audio.narratorEnabled && audio.narration.pending))
        } else {
            Button {} label: {
                Label("Choose an Answer", systemImage: "hand.tap")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered).disabled(true)
        }
    }

    @ViewBuilder
    private func questionPrompt(_ text: String) -> some View {
        if round.mode == .stage {
            Text(text)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 60).padding(24)
                .background(Color(white: 0.075), in: SentenceStagePanel())
                .overlay(SentenceStagePanel().stroke(revealing ? amber : Color.cyan.opacity(0.65), lineWidth: revealing ? 2 : 1))
                .animation(reduceMotion || scenePhase != .active ? nil : .easeInOut(duration: 0.6), value: revealing)
                .accessibilityAddTraits(.isHeader)
        } else {
            Text(text).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func optionButton(_ option: SentencePair, index: Int) -> some View {
        let selected = round.selectedID == option.id
        let correct = round.revealed && option.id == round.current?.id
        let wrong = round.revealed && selected && !correct
        let stage = round.mode == .stage
        let accent = correct ? mint : wrong ? coral : selected ? (stage ? amber : mint) : Color.cyan.opacity(0.5)
        return Button {
            guard !revealing, scenePhase == .active else { return }
            audio.stopNarration()
            let letter = ["A", "B", "C", "D"][index]
            if let answer = round.select(option.id) {
                historyModel.append(answer, roundID: round.id, topic: round.topic, mode: round.mode,
                                    questionIndex: round.index)
                audio.readQuickResult(letter: letter, english: option.english, correct: answer.correct) {
                    audio.play(answer.correct ? .correct : .incorrect)
                }
            } else if round.mode == .stage {
                if audio.narratorEnabled { audio.readStageSelection(letter: letter, english: option.english) }
                else { audio.play(.select) }
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Text(["A", "B", "C", "D"][index]).font(.headline.monospaced()).frame(width: 22)
                    .foregroundStyle(stage ? accent : Color.primary)
                Text(option.english).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                Image(systemName: correct ? "checkmark.circle.fill" : wrong ? "xmark.circle.fill" : "circle.inset.filled")
                    .foregroundStyle(accent).opacity(correct || wrong || selected ? 1 : 0)
                    .frame(width: 22, height: 22).accessibilityHidden(true)
            }
            .padding(.horizontal, stage ? 18 : 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background {
                if stage {
                    SentenceStagePanel().fill(Color(white: 0.065))
                    SentenceStagePanel().fill(accent.opacity(correct || wrong || selected ? 0.19 : 0.025))
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(correct ? mint.opacity(0.22) : wrong ? coral.opacity(0.22) : selected ? mint.opacity(0.12) : Color.primary.opacity(0.07))
                }
            }
            .overlay {
                if stage { SentenceStagePanel().stroke(accent, lineWidth: selected || correct ? 2 : 1) }
                else { RoundedRectangle(cornerRadius: 8).stroke(correct || selected ? mint : wrong ? coral : Color.primary.opacity(0.2), lineWidth: selected ? 2 : 1) }
            }
            .contentShape(stage ? AnyShape(SentenceStagePanel()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
        }
        .buttonStyle(.plain).disabled(round.revealed || revealing)
        .accessibilityValue(correct ? "Correct answer" : wrong ? "Your answer, incorrect" : selected ? "Selected" : "Not selected")
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Round Complete", systemImage: "flag.checkered").font(.title2.weight(.bold))
            Text("\(round.score) correct / \(round.questions.count - round.score) incorrect").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                Button { restart(retry: true) } label: { Label("Retry Incorrect", systemImage: "arrow.counterclockwise").frame(minHeight: 44) }
                    .disabled(round.incorrectIDs.isEmpty)
                Button { restart(retry: false) } label: { Label("Play Again", systemImage: "play.fill").frame(minHeight: 44) }
            }.buttonStyle(.bordered).controlSize(.regular)
            ForEach(round.answers, id: \.question.id) { answer in
                VStack(alignment: .leading, spacing: 8) {
                    Label(answer.question.pair.vietnamese, systemImage: answer.correct ? "checkmark.circle" : "xmark.circle")
                    Text(answer.question.pair.english).font(.headline)
                    if !answer.correct, let selected = answer.question.options.first(where: { $0.id == answer.selectedID }) {
                        Text("Your answer: \(selected.english)").foregroundStyle(coral)
                    }
                }.padding(.vertical, 8)
                Divider()
            }
        }
    }

    private func confirmWithSuspense() {
        guard round.selectedID != nil, !revealing else { return }
        audio.stopNarration()
        audio.play(.suspense)
        let questionID = round.current?.id
        revealController.begin {
            guard scenePhase == .active, round.current?.id == questionID else { return }
            if let answer = round.confirm() {
                historyModel.append(answer, roundID: round.id, topic: round.topic, mode: round.mode,
                                    questionIndex: round.index)
                audio.readResult(correct: answer.correct) {
                    audio.play(answer.correct ? .correct : .incorrect)
                }
            }
        }
    }

    private func stop() {
        revealController.cancel()
        audio.stop()
    }

    private func restart(retry: Bool) {
        stop()
        do {
            round = try SentenceRound(topic: round.topic, mode: round.mode, retryIDs: retry ? round.incorrectIDs : nil)
            audio.activate(stage: round.mode == .stage)
            audio.readNewQuestion(round.current)
        } catch { self.error = error.localizedDescription }
    }
}

private struct SentenceStagePanel: Shape {
    func path(in rect: CGRect) -> Path {
        let bevel = min(16, rect.height * 0.2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + bevel, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - bevel, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - bevel, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bevel, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct SentenceStageBackdrop: View {
    let animated: Bool
    let suspense: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animated)) { context in
            Canvas { drawing, size in
                drawing.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.025)))
                let time = animated ? context.date.timeIntervalSinceReferenceDate : 0
                for beam in 0..<6 {
                    let origin = CGPoint(x: size.width * Double(beam) / 5, y: 0)
                    let sway = sin(time * 0.25 + Double(beam)) * size.width * (suspense ? 0.08 : 0.18)
                    let target = suspense ? size.width * 0.5 : size.width - origin.x
                    let spread = size.width * (suspense ? 0.05 : 0.12)
                    var path = Path()
                    path.move(to: origin)
                    path.addLine(to: CGPoint(x: target + sway - spread, y: size.height))
                    path.addLine(to: CGPoint(x: target + sway + spread, y: size.height))
                    path.closeSubpath()
                    drawing.fill(path, with: .color((beam.isMultiple(of: 2) ? Color.cyan : Color.blue).opacity(suspense ? 0.1 : 0.065)))
                }
                let horizon = size.height * 0.72
                for rail in 0..<7 {
                    var path = Path()
                    path.move(to: CGPoint(x: size.width * 0.5, y: horizon))
                    path.addLine(to: CGPoint(x: size.width * Double(rail) / 6, y: size.height))
                    drawing.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 1)
                }
                for step in 0..<5 {
                    let depth = pow(Double(step + 1) / 5, 2)
                    let height = horizon + (size.height - horizon) * depth
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: CGPoint(x: size.width, y: height))
                    drawing.stroke(path, with: .color(Color(white: 0.25)), lineWidth: 1)
                }
                for side in [0.035, 0.965] {
                    let position = size.width * side
                    let rail = CGRect(x: position - 2, y: 0, width: 4, height: horizon)
                    drawing.fill(Path(rail), with: .color(Color(white: 0.18)))
                    for lamp in 0..<4 {
                        let fixture = CGRect(x: position - 3, y: horizon * Double(lamp + 1) / 5, width: 6, height: 20)
                        drawing.fill(Path(fixture), with: .color(Color(red: 1, green: 0.74, blue: 0.28).opacity(suspense ? 0.8 : 0.35)))
                    }
                }
            }
        }.ignoresSafeArea().accessibilityHidden(true).allowsHitTesting(false)
    }
}