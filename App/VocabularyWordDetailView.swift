import SwiftUI
import WidgetKit
import AppIntents

@MainActor
final class VocabularyDetailRouter: ObservableObject {
    @Published private(set) var state = VocabularyDetailRoutingState()
    private var playbackOwner: UUID?
    private var cancelPlayback: (() -> Void)?

    func open(_ url: URL, blocked: Bool) {
        guard let route = WordDetailRoute.parse(url) else { return }
        state.receive(route, blocked: blocked, cancelPlayback: { self.cancelPlayback?() })
    }

    func drain(blocked: Bool) {
        state.drain(blocked: blocked, cancelPlayback: { self.cancelPlayback?() })
    }

    func close() { state.close(cancelPlayback: { self.cancelPlayback?() }) }

    func registerPlayback(owner: UUID, cancel: @escaping () -> Void) {
        playbackOwner = owner
        cancelPlayback = cancel
    }

    func unregisterPlayback(owner: UUID) {
        guard playbackOwner == owner else { return }
        cancelPlayback = nil
        playbackOwner = nil
    }
}

@MainActor
final class VocabularyDetailPlayback: ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var errorMessage: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    var isActive = false

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        isSpeaking = false
        errorMessage = nil
    }

    func speak(_ text: String, perform: @escaping (String) async throws -> Void = { text in
        _ = try await SpeakWordIntent(word: text).perform()
    }) {
        cancel()
        guard isActive else { return }
        let token = generation
        isSpeaking = true
        task = Task { @MainActor in
            guard self.isActive, !Task.isCancelled else { return }
            do {
                try await perform(text)
                guard self.generation == token, self.isActive, !Task.isCancelled else { return }
                self.isSpeaking = false
                self.task = nil
            } catch {
                guard self.generation == token, self.isActive, !Task.isCancelled else { return }
                self.isSpeaking = false
                self.errorMessage = error.localizedDescription
                self.task = nil
            }
        }
    }
}

struct VocabularyWordDetailView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var router: VocabularyDetailRouter
    @State private var session: VocabularyDetailSession
    @StateObject private var playback = VocabularyDetailPlayback()
    @State private var actionError: String?

    init(session: VocabularyDetailSession, router: VocabularyDetailRouter) {
        _session = State(initialValue: session)
        self.router = router
    }

    private var actionProblem: String? { session.actionProblem() }
    private var identityAvailable: Bool {
        guard let topics = try? VocabularyCatalog.detailTopics() else { return false }
        return session.identity.resolve(in: topics) != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let snapshot = session.snapshot {
                        Text(snapshot.topicName).font(.subheadline).foregroundStyle(.secondary)
                        Text(snapshot.word.text)
                            .font(.largeTitle.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .textSelection(.enabled)
                        Text(snapshot.word.partOfSpeech).font(.headline).foregroundStyle(.secondary)
                        Text(snapshot.word.meaning).font(.title3)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Divider()
                        Text("Examples").font(.headline).accessibilityAddTraits(.isHeader)
                        ForEach(Array(snapshot.word.examples.enumerated()), id: \.offset) { offset, example in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(offset + 1).")
                                    .font(.body.monospacedDigit()).foregroundStyle(.secondary)
                                Text(example).frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            }
                        }
                        Divider()
                        Button {
                            guard scenePhase == .active,
                                  let topics = try? VocabularyCatalog.detailTopics(),
                                  session.identity.resolve(in: topics) != nil else {
                                actionError = "This word is no longer available."
                                return
                            }
                            actionError = nil
                            playback.isActive = true
                            playback.speak(snapshot.word.text)
                        } label: {
                            HStack {
                                Image(systemName: "speaker.wave.2.fill")
                                if playback.isSpeaking { ProgressView() }
                            }
                            .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Pronounce \(snapshot.word.text)")
                        .accessibilityValue(playback.isSpeaking ? "Speaking" : "")
                        .disabled(scenePhase != .active || !identityAvailable)
                        Button { advance(markLearned: false) } label: {
                            Label("Next word", systemImage: "arrow.right.circle.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(actionProblem != nil)
                        Button { advance(markLearned: true) } label: {
                            Label("Mark as learned", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(actionProblem != nil)
                        if let problem = actionProblem { Text(problem).font(.footnote).foregroundStyle(.secondary) }
                    } else {
                        ContentUnavailableView("Word Unavailable", systemImage: "text.magnifyingglass",
                                               description: Text("The topic or displayed word has changed or cannot be read."))
                    }
                    if let error = actionError ?? playback.errorMessage {
                        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Word Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { playback.cancel(); session.cancelPlayback(); router.close() }
                        .frame(minHeight: 44)
                }
            }
        }
        .onAppear {
            playback.isActive = scenePhase == .active
            router.registerPlayback(owner: session.id) { playback.cancel() }
        }
        .onDisappear {
            playback.cancel()
            router.unregisterPlayback(owner: session.id)
        }
        .onChange(of: scenePhase) { _, phase in
            playback.isActive = phase == .active
            if phase != .active { playback.cancel(); session.cancelPlayback() }
        }
    }

    private func advance(markLearned: Bool) {
        playback.cancel()
        actionError = nil
        let date = Date.now
        let accepted = session.advance(markLearned: markLearned, at: date, onSuccess: {
            WidgetCenter.shared.reloadTimelines(ofKind: "VocabularyWidget")
            Task { await VocabularyNotifications.reschedule() }
        })
        if !accepted { actionError = session.actionProblem() ?? "Could not save progress. The displayed word has not changed." }
    }
}