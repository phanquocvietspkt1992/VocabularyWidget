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

private struct SentenceBuilderPlaySession: Identifiable {
    let id = UUID()
    let round: SentenceBuilderRound
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
    @StateObject private var sessionModel = SentenceRoundSessionModel()
    @StateObject private var builderSessionModel = SentenceBuilderSessionModel()
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
                    Button("Try Sample Sentences", systemImage: "text.badge.plus") {
                        editor = SentenceEditSession(topic: SentenceTopic.sample(), expected: model.topics)
                    }
                    .disabled(!model.canEdit)
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
                        SentenceTopicView(model: model, historyModel: historyModel,
                                          sessionModel: sessionModel, builderSessionModel: builderSessionModel,
                                          topicID: topic.id)
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
    @ObservedObject var sessionModel: SentenceRoundSessionModel
    @ObservedObject var builderSessionModel: SentenceBuilderSessionModel
    let topicID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var mode = SentenceMode.stage
    @State private var editor: SentenceEditSession?
    @State private var playSession: SentencePlaySession?
    @State private var error: String?
    @State private var deleting = false
    @State private var replacingRound = false
    @State private var replacingBuilderRound = false
    @State private var builderPlaySession: SentenceBuilderPlaySession?
    private var topic: SentenceTopic? { model.topics.first { $0.id == topicID } }
    private var savedRound: SentenceSavedRound? {
        mode == .builder ? nil : sessionModel.session(topicID: topicID, mode: mode)
    }
    private var savedBuilderRound: SentenceBuilderSavedRound? {
        mode == .builder ? builderSessionModel.session(topicID: topicID) : nil
    }

    var body: some View {
        List {
            if let topic {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(SentenceMode.allCases) {
                            Text($0.displayName).tag($0)
                        }
                    }
                        .pickerStyle(.segmented)
                    if mode == .builder {
                        Text("Use imported English sentences with 2–20 words. Up to five eligible sentences are shuffled into a round.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("Tiles omit capitalization and punctuation. The answer must match the imported sentence; other valid wording is not accepted.")
                            .font(.footnote).foregroundStyle(.secondary)
                        let eligibleCount = SentenceBuilderRound.eligiblePairs(in: topic).count
                        Text("\(eligibleCount) of \(topic.pairs.count) sentences eligible")
                            .font(.footnote).foregroundStyle(eligibleCount == 0 ? Color.red : Color.secondary)
                        if eligibleCount < topic.pairs.count {
                            Text("\(topic.pairs.count - eligibleCount) sentence(s) skipped: English must contain 2–20 words with at least two distinct words.")
                                .font(.footnote).foregroundStyle(.red)
                        }
                        if eligibleCount == 0 {
                            Text("No suitable sentences; add an English sentence with 2–20 words and at least two distinct words to play Word Order.")
                                .font(.footnote).foregroundStyle(.red)
                        }
                        if let savedBuilderRound {
                            Button {
                                do {
                                    builderPlaySession = SentenceBuilderPlaySession(
                                        round: try builderSessionModel.resume(topicID: topicID))
                                } catch { self.error = error.localizedDescription }
                            } label: {
                                Label(savedBuilderRound.round.finished ? "View Word Order Results" : "Resume Word Order Round",
                                      systemImage: savedBuilderRound.round.finished ? "flag.checkered" : "play.fill")
                            }
                            Text(savedBuilderRound.round.finished
                                 ? "Complete · \(savedBuilderRound.round.score) stars"
                                 : "Sentence \(savedBuilderRound.round.index + 1) of \(savedBuilderRound.round.questions.count)")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button {
                            if let savedBuilderRound, !savedBuilderRound.round.finished { replacingBuilderRound = true }
                            else { startBuilderRound() }
                        } label: {
                            Label("New Word Order Round", systemImage: "play.fill")
                        }
                        .disabled(eligibleCount == 0 || model.error != nil || builderSessionModel.error != nil)
                        if let error = builderSessionModel.error {
                            Text(error).font(.footnote).foregroundStyle(.red)
                            Button("Reload Word Order Rounds", systemImage: "arrow.clockwise") {
                                builderSessionModel.reload()
                            }
                        }
                    } else if let savedRound {
                        Button {
                            do {
                                playSession = SentencePlaySession(round: try sessionModel.resume(topicID: topicID, mode: mode))
                            } catch { self.error = error.localizedDescription }
                        } label: {
                            Label(savedRound.round.finished ? "View Results" : "Resume Round",
                                  systemImage: savedRound.round.finished ? "flag.checkered" : "play.fill")
                        }
                        Text(savedRound.round.finished
                             ? "Complete · \(savedRound.round.answers.filter(\.correct).count) / \(savedRound.round.questions.count) correct"
                             : "Question \(savedRound.round.index + 1) of \(savedRound.round.questions.count) · \(savedRound.round.answers.count) answered")
                            .font(.footnote).foregroundStyle(.secondary)
                        if !savedRound.round.finished {
                            Button("New Game", systemImage: "arrow.counterclockwise") { replacingRound = true }
                                .disabled(topic.pairs.count < 4 || model.error != nil)
                        }
                    } else {
                        Button {
                            do { playSession = SentencePlaySession(round: try sessionModel.start(topic: topic, mode: mode)) }
                            catch { self.error = error.localizedDescription }
                        } label: { Label("New Game", systemImage: "play.fill") }
                            .disabled(topic.pairs.count < 4 || model.error != nil)
                    }
                    if mode != .builder && topic.pairs.count < 4 {
                        Text(SentenceGameError.tooSmall.localizedDescription).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
                if let error = sessionModel.error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("Reload Saved Rounds", systemImage: "arrow.clockwise") { sessionModel.reload() }
                    }
                }
                ForEach(topic.pairs) { pair in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(pair.english).font(.headline)
                        Text(pair.vietnamese).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            } else {
                ContentUnavailableView("Topic Unavailable", systemImage: "text.bubble")
                if let error { Text(error).foregroundStyle(.red) }
                if let error = builderSessionModel.error { Text(error).foregroundStyle(.red) }
            }
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
        .fullScreenCover(item: $playSession) {
            SentenceGameView(initialRound: $0.round, historyModel: historyModel, sessionModel: sessionModel)
        }
        .fullScreenCover(item: $builderPlaySession) {
            SentenceBuilderGameView(initialRound: $0.round, sessionModel: builderSessionModel)
        }
        .confirmationDialog("Delete this sentence topic and all its pairs?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete Topic", role: .destructive) {
                do {
                    try model.delete(topicID, expected: model.topics)
                    try sessionModel.remove(topicID: topicID)
                    try builderSessionModel.remove(topicID: topicID)
                    dismiss()
                }
                catch { self.error = error.localizedDescription }
            }
        }
        .confirmationDialog("Replace this unfinished round?", isPresented: $replacingRound, titleVisibility: .visible) {
            Button("Replace Round", role: .destructive) {
                guard let topic else { return }
                do { playSession = SentencePlaySession(round: try sessionModel.start(topic: topic, mode: mode)) }
                catch { self.error = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved questions and answers for this topic and mode will be replaced.")
        }
        .confirmationDialog("Replace this unfinished Word Order round?", isPresented: $replacingBuilderRound,
                            titleVisibility: .visible) {
            Button("Replace Round", role: .destructive) { startBuilderRound() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current tile arrangement and results for this topic will be replaced.")
        }
    }

    private func startBuilderRound(retryIDs: Set<UUID>? = nil) {
        guard let topic else { return }
        do {
            builderPlaySession = SentenceBuilderPlaySession(
                round: try builderSessionModel.start(topic: topic, retryIDs: retryIDs))
            error = nil
        } catch { self.error = error.localizedDescription }
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
                        Text("\(record.topicName) · \(record.mode.displayName)")
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
    @ObservedObject private var sessionModel: SentenceRoundSessionModel
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

    init(initialRound: SentenceRound, historyModel: SentenceRoundHistoryModel,
         sessionModel: SentenceRoundSessionModel) {
        _round = State(initialValue: initialRound)
        _audio = StateObject(wrappedValue: SentenceAudio(stage: initialRound.mode == .stage))
        _historyModel = ObservedObject(initialValue: historyModel)
        _sessionModel = ObservedObject(initialValue: sessionModel)
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
                                Text(round.mode.displayName.uppercased()).font(.system(.caption, design: .rounded, weight: .bold))
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
                            if historyModel.error != nil {
                                Button("Retry History Save", systemImage: "arrow.clockwise") { historyModel.retryPending() }
                                    .buttonStyle(.bordered)
                            }
                            if let error = sessionModel.error { Text(error).font(.footnote).foregroundStyle(coral) }
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
                historyModel.reconcile(round)
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
                var candidate = round
                candidate.advance()
                guard persist(candidate) else { return }
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
            var candidate = round
            if let answer = candidate.select(option.id) {
                guard persist(candidate) else { return }
                historyModel.recordCommitted(answer, roundID: candidate.id, topic: candidate.topic, mode: candidate.mode,
                                             questionIndex: candidate.index)
                audio.readQuickResult(letter: letter, english: option.english, correct: answer.correct) {
                    audio.play(answer.correct ? .correct : .incorrect)
                }
            } else if round.mode == .stage {
                guard persist(candidate) else { return }
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
            var candidate = round
            if let answer = candidate.confirm() {
                guard persist(candidate) else { return }
                historyModel.recordCommitted(answer, roundID: candidate.id, topic: candidate.topic, mode: candidate.mode,
                                             questionIndex: candidate.index)
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
            let candidate = try SentenceRound(topic: round.topic, mode: round.mode,
                                              retryIDs: retry ? round.incorrectIDs : nil)
            try sessionModel.save(candidate)
            round = candidate
            error = nil
            audio.activate(stage: round.mode == .stage)
            audio.readNewQuestion(round.current)
        } catch { self.error = error.localizedDescription }
    }

    private func persist(_ candidate: SentenceRound) -> Bool {
        do {
            try sessionModel.save(candidate)
            round = candidate
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

private struct SentenceBuilderGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var audio: SentenceAudio
    @StateObject private var revealController = SentenceRevealController()
    @ObservedObject private var sessionModel: SentenceBuilderSessionModel
    @State private var round: SentenceBuilderRound
    @State private var error: String?
    @State private var checking = false
    @State private var successFeedback = 0
    @State private var moreExpanded = false

    private let cream = Color(red: 1.00, green: 0.97, blue: 0.89)
    private let mint = Color(red: 0.70, green: 0.89, blue: 0.79)
    private let leaf = Color(red: 0.14, green: 0.37, blue: 0.28)
    private let sky = Color(red: 0.56, green: 0.78, blue: 0.89)
    private let peach = Color(red: 0.96, green: 0.66, blue: 0.51)
    private let ink = Color(red: 0.16, green: 0.22, blue: 0.24)

    init(initialRound: SentenceBuilderRound, sessionModel: SentenceBuilderSessionModel) {
        _round = State(initialValue: initialRound)
        _audio = StateObject(wrappedValue: SentenceAudio(stage: true, theme: .gentle))
        _sessionModel = ObservedObject(initialValue: sessionModel)
    }

    private var question: SentenceBuilderQuestion? { round.current }

    var body: some View {
        NavigationStack {
            ZStack {
                cream.ignoresSafeArea()
                GeometryReader { geometry in
                    ViewThatFits(in: .vertical) {
                        gameContent(width: geometry.size.width)
                        ScrollView { gameContent(width: geometry.size.width) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                primaryAction.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
                    .background(.white.opacity(0.96))
                    .overlay(alignment: .top) { Rectangle().fill(sky.opacity(0.55)).frame(height: 1) }
                    .shadow(color: ink.opacity(0.08), radius: 10, x: 0, y: -3)
            }
            .foregroundStyle(ink)
            .tint(leaf)
            .navigationTitle(round.topic.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { revealController.cancel(); audio.stop(); dismiss() } label: {
                        Label("Exit Word Order", systemImage: "xmark").labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Toggle(isOn: $audio.musicEnabled) { Label("Music", systemImage: "music.note") }
                        Toggle(isOn: $audio.effectsEnabled) { Label("Sound Effects", systemImage: "speaker.wave.2") }
                        Toggle(isOn: $audio.narratorEnabled) { Label("System Narrator", systemImage: "person.wave.2") }
                        Button("Resume Audio", systemImage: "play.circle") {
                            if scenePhase == .active { audio.activate(stage: true) }
                        }
                    } label: {
                        Label("Audio", systemImage: "speaker.wave.2.circle").labelStyle(.iconOnly)
                    }
                }
            }
            .preferredColorScheme(.light)
            .transaction { transaction in
                if reduceMotion || scenePhase != .active {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .sensoryFeedback(.success, trigger: successFeedback)
            .onAppear { if scenePhase == .active { audio.activate(stage: true) } }
            .onDisappear { revealController.cancel(); audio.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { revealController.cancel(); checking = false; audio.stop() }
                else { audio.activate(stage: true) }
            }
        }
    }

    @ViewBuilder
    private func gameContent(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(round.index + 1)/\(round.questions.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .accessibilityLabel("Sentence \(round.index + 1) of \(round.questions.count)")
                Spacer()
                Label("\(round.score)", systemImage: "star.fill")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .accessibilityLabel("\(round.score) stars")
            }
            if round.finished {
                results
            } else if let question {
                Text(question.pair.vietnamese)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 60).padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(checking ? peach : sky.opacity(0.8), lineWidth: 1))
                    .shadow(color: ink.opacity(0.07), radius: 8, x: 0, y: 3)
                    .accessibilityAddTraits(.isHeader)
                Text("Answer").font(.caption.weight(.bold)).foregroundStyle(ink.opacity(0.76))
                arrangedTiles(question, availableWidth: width)
                if question.finished {
                    Label(question.viewed ? "Viewed · 0 stars"
                          : question.isCorrect ? "Nice work · \(question.stars ?? 0) stars"
                          : "Nice try · 0 stars",
                          systemImage: question.viewed ? "eye.fill" : question.isCorrect ? "checkmark.seal.fill" : "heart.fill")
                        .font(.headline).foregroundStyle(question.isCorrect ? leaf : ink)
                        .symbolEffect(.bounce, value: successFeedback)
                    Text(question.pair.english).font(.title3.weight(.semibold)).foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        guard scenePhase == .active else { return }
                        revealController.cancel()
                        audio.readSentence(question.pair.english, explicit: true)
                    } label: {
                        Label("Replay", systemImage: "speaker.wave.2").frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(scenePhase != .active)
                } else {
                    Text("Word bank").font(.caption.weight(.bold)).foregroundStyle(ink.opacity(0.76))
                    bankTiles(question)
                    DisclosureGroup("More", isExpanded: $moreExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tap a bank word to append it. Drag before a word or to the end to move it; tap a selected word to return it.")
                                .font(.footnote).foregroundStyle(ink.opacity(0.76))
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                Button {
                                    guard scenePhase == .active else { return }
                                    var candidate = round
                                    guard candidate.useHint() != nil else { return }
                                    if persist(candidate) { audio.playWordOrder(.select) }
                                } label: {
                                    Label("Hint", systemImage: "lightbulb").frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .disabled(question.finished || checking || question.hint == nil || scenePhase != .active)
                                Button {
                                    guard scenePhase == .active, !checking else { return }
                                    var candidate = round
                                    candidate.markHeard()
                                    _ = persist(candidate) {
                                        audio.readSentence(question.pair.english, explicit: true)
                                    }
                                } label: {
                                    Label("Listen", systemImage: "speaker.wave.2").frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .disabled(question.finished || checking || scenePhase != .active)
                            }
                            .buttonStyle(.bordered)
                            Button {
                                var candidate = round
                                candidate.reveal()
                                guard persist(candidate) else { return }
                                audio.playWordOrder(.select)
                            } label: {
                                Label("Reveal", systemImage: "eye").frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered).tint(leaf)
                            .disabled(checking || scenePhase != .active)
                            if question.hintShown, let hint = question.hint {
                                Label("Next word: \(hint)", systemImage: "lightbulb.fill")
                                    .font(.headline).foregroundStyle(ink).padding(8)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                                    .accessibilityAddTraits(.updatesFrequently)
                            }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                if let error {
                    Text(error).font(.footnote).fixedSize(horizontal: false, vertical: true)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(peach.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityAddTraits(.isStaticText)
                }
                if let error = audio.error { Text(error).font(.footnote).fixedSize(horizontal: false, vertical: true) }
                if let error = audio.narrationError { Text(error).font(.footnote).fixedSize(horizontal: false, vertical: true) }
                if let error = sessionModel.error { Text(error).font(.footnote).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: 850).frame(maxWidth: .infinity)
    }

    private func arrangedTiles(_ question: SentenceBuilderQuestion, availableWidth: CGFloat) -> some View {
        let columns = max(1, Int((max(0, availableWidth - 44) + 6) / 82))
        let rows = (question.expectedWords.count + columns - 1) / columns
        let reservedHeight = CGFloat(max(1, rows)) * 50 + (question.finished ? 20 : 68)
        return ScrollView {
        VStack(spacing: 8) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], spacing: 6) {
            ForEach(Array(question.arranged.enumerated()), id: \.element.id) { index, tile in
                Button {
                    guard !checking, scenePhase == .active else { return }
                    if mutate({ $0.tapArranged(tile.id) }) { audio.playWordOrder(.select) }
                } label: {
                    tileLabel(tile.text, accent: mint)
                }
                .buttonStyle(.plain)
                .draggable("arranged:\(tile.id.uuidString)")
                .dropDestination(for: String.self) { values, _ in
                    acceptDrop(values, before: tile.id)
                }
                .accessibilityLabel(tile.text)
                .accessibilityHint("Double-tap to return this word to the bank. Drag before another word or to the end to reorder, or use the Move left and Move right accessibility actions.")
                .accessibilityAction(named: Text("Move left")) {
                    guard !checking, scenePhase == .active, index > 0 else { return }
                    if mutate({ $0.moveArranged(from: index, to: index - 1) }) { audio.playWordOrder(.reorder) }
                }
                .accessibilityAction(named: Text("Move right")) {
                    guard !checking, scenePhase == .active, index + 1 < question.arranged.count else { return }
                    if mutate({ $0.moveArranged(from: index, to: index + 1) }) { audio.playWordOrder(.reorder) }
                }
                .disabled(question.finished || checking || scenePhase != .active)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78), value: question.arranged.map(\.id))
        if !question.finished {
            // A sibling target, not a parent destination: tile drops cannot route to append.
            Text("Drop to end")
                .font(.caption).foregroundStyle(ink.opacity(0.55))
                .frame(maxWidth: .infinity, minHeight: 46, maxHeight: .infinity)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { values, _ in
                    acceptDrop(values)
                }
                .accessibilityLabel("End of your sentence")
            }
        }
        .frame(minHeight: reservedHeight - 20, alignment: .top)
        }
        .padding(10)
        .frame(height: reservedHeight, alignment: .top)
        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(sky.opacity(0.65), lineWidth: 1))
        .shadow(color: ink.opacity(0.06), radius: 8, x: 0, y: 3)
        .accessibilityLabel("Your sentence, \(question.arranged.count) of \(question.expectedWords.count) words")
    }

    private func acceptDrop(_ values: [String], before target: UUID? = nil) -> Bool {
        guard !checking, scenePhase == .active, values.count == 1, let payload = values.first else { return false }
        let changed = mutate { $0.dropTile(payload, before: target) }
        if changed { audio.playWordOrder(payload.hasPrefix("bank:") ? .select : .reorder) }
        return changed
    }

    private func bankTiles(_ question: SentenceBuilderQuestion) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], spacing: 6) {
            ForEach(question.bankSlots) { tile in
                let available = question.bank.contains(where: { $0.id == tile.id })
                if available {
                Button {
                    guard !checking, scenePhase == .active else { return }
                    if mutate({ $0.tapBank(tile.id) }) { audio.playWordOrder(.select) }
                } label: {
                    tileLabel(tile.text, accent: sky)
                        .foregroundStyle(available ? ink : ink.opacity(0.8))
                }
                .buttonStyle(.plain)
                .draggable("bank:\(tile.id.uuidString)")
                .accessibilityLabel("Add \(tile.text)")
                .accessibilityHint("Double-tap to append, or drag before a selected word or to the end of your sentence.")
                .disabled(question.finished || checking || scenePhase != .active)
                } else {
                    tileLabel(tile.text, accent: sky)
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func tileLabel(_ text: String, accent: Color) -> some View {
        Text(text)
            .font(.system(.body, design: .rounded, weight: .semibold))
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(accent.opacity(0.72), lineWidth: 1))
            .shadow(color: ink.opacity(0.07), radius: 5, x: 0, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var primaryAction: some View {
        if round.finished {
            Button { dismiss() } label: {
                Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(ink)
        } else if question?.finished == true {
            Button {
                revealController.cancel()
                audio.stopNarration()
                var candidate = round
                candidate.advance()
                guard persist(candidate) else { return }
                moreExpanded = false
                if candidate.finished { audio.playWordOrder(.finish) } else { audio.playWordOrder(.select) }
            } label: {
                Label(round.index + 1 == round.questions.count ? "Results" : "Next",
                      systemImage: "arrow.right").frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(ink)
                .disabled(scenePhase != .active)
        } else {
            Button { beginCheck() } label: {
                Label(checking ? "Checking..." : "Check", systemImage: checking ? "hourglass" : "checkmark")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(ink)
                .disabled(question?.arranged.count != question?.expectedWords.count || checking || scenePhase != .active)
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Nice practice!", systemImage: "star.leadinghalf.filled").font(.title2.weight(.bold)).foregroundStyle(ink)
            Text("\(round.score) stars earned").font(.headline).foregroundStyle(leaf)
            Button { replayNonThreeStarSentences() } label: {
                Label("Replay non-3-star sentences", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).tint(mint).foregroundStyle(ink)
            .disabled(round.replayIDs.isEmpty || scenePhase != .active)
            ForEach(round.questions) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(item.viewed ? "Viewed" : "\(item.stars ?? 0) stars",
                              systemImage: item.viewed ? "eye.fill" : "star.fill")
                            .foregroundStyle(item.stars == 3 ? leaf : ink)
                        Spacer()
                        if item.stars != 3 { Text("Replay").font(.caption.weight(.bold)).foregroundStyle(leaf) }
                    }
                    Text(item.pair.vietnamese).font(.subheadline)
                    Text(item.pair.english).font(.headline)
                }
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: ink.opacity(0.06), radius: 6, x: 0, y: 3)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(ink) }
            if let error = sessionModel.error { Text(error).font(.footnote).foregroundStyle(ink) }
        }
    }

    private func beginCheck() {
        guard let question, !question.finished, question.arranged.count == question.expectedWords.count,
              !checking, scenePhase == .active else { return }
        audio.stopNarration()
        audio.playWordOrder(.check)
        checking = true
        let questionID = question.id
        var candidate = round
        let result = candidate.check()
        checking = false
        guard let result, persist(candidate, afterSave: {
            revealController.begin(delay: 140_000_000) {
                guard scenePhase == .active, round.current?.id == questionID,
                      round.current?.finished == true else { return }
                if result { successFeedback += 1; audio.playWordOrder(.correct) }
                else { audio.playWordOrder(.incorrect) }
                // This queued read is canceled by Next, replay, dismissal or backgrounding.
                revealController.begin(delay: 500_000_000) {
                    guard scenePhase == .active, round.current?.id == questionID,
                          round.current?.finished == true else { return }
                    audio.readSentence(question.pair.english)
                }
            }
        }) else { return }
    }

    private func replayNonThreeStarSentences() {
        revealController.cancel()
        audio.stopNarration()
        do {
            let candidate = try sessionModel.start(topic: round.topic, retryIDs: round.replayIDs)
            round = candidate
            error = nil
            audio.activate(stage: true)
        } catch { self.error = error.localizedDescription }
    }

    @discardableResult
    private func mutate(_ change: (inout SentenceBuilderRound) -> Void) -> Bool {
        var candidate = round
        change(&candidate)
        guard candidate != round else { return false }
        return persist(candidate)
    }

    @discardableResult
    private func persist(_ candidate: SentenceBuilderRound, afterSave: (() -> Void)? = nil) -> Bool {
        do {
            try sessionModel.save(candidate, afterSave: afterSave)
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78)) {
                round = candidate
            }
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
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