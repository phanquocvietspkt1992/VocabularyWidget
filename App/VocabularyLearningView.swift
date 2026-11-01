import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

struct VocabularyBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw LearningStorageError.invalidBackup }
        _ = try VocabularyLearningStore.decodeBackup(data)
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct VocabularyBackupView: View {
    let onRestore: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var document: VocabularyBackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var pending: VocabularyBackup?
    @State private var confirming = false
    @State private var message: String?
    @State private var recovery: Data?
    @State private var restored = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { export() } label: { Label("Export Backup", systemImage: "square.and.arrow.up") }
                    Button { importing = true } label: { Label("Restore Backup", systemImage: "square.and.arrow.down") }
                }
                if let recovery {
                    Section {
                        Button {
                            document = VocabularyBackupDocument(data: recovery)
                            exporting = true
                        } label: { Label("Export Recovery Backup", systemImage: "externaldrive.badge.exclamationmark") }
                    }
                }
                if let message { Text(message).foregroundStyle(.red) }
                if restored { Label("Backup Restored", systemImage: "checkmark.circle").foregroundStyle(.green) }
            }
            .navigationTitle("Backup & Restore")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                          defaultFilename: "VocabularyBackup") { result in
                if case .failure(let error) = result { report(error) }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let backup = try VocabularyLearningStore.decodeBackup(Data(contentsOf: url))
                    _ = try VocabularyLearningStore.rawSnapshot()
                    pending = backup
                    message = nil
                    confirming = true
                } catch { report(error) }
            }
            .alert("Replace Saved Data?", isPresented: $confirming) {
                Button("Cancel", role: .cancel) { pending = nil }
                Button("Replace", role: .destructive) { restore() }
            } message: {
                Text("Custom topics, saved words, progress, study history, schedule, and review results will be replaced by this backup.")
            }
        }
    }

    private func export() {
        do {
            document = VocabularyBackupDocument(data: try VocabularyLearningStore.exportBackup())
            message = nil
            exporting = true
        } catch { report(error) }
    }

    private func restore() {
        guard let pending else { return }
        self.pending = nil
        do {
            try VocabularyLearningStore.restore(pending)
            message = nil
            restored = true
            recovery = nil
            onRestore()
            WidgetCenter.shared.reloadAllTimelines()
            Task { await VocabularyNotifications.reschedule() }
        } catch { report(error) }
    }

    private func report(_ error: Error) {
        if (error as NSError).code == NSUserCancelledError { return }
        if case LearningStorageError.rollbackFailed(let data) = error { recovery = data }
        restored = false
        message = error.localizedDescription
    }
}

struct VocabularyDailyReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = VocabularyReviewSession()
    @State private var message: String?
    @State private var recovery: VocabularyBackupDocument?
    @State private var exportingRecovery = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Label("\(session.dueCount) Due", systemImage: "calendar")
                        Spacer()
                        Label("\(session.reviewedToday) Reviewed Today", systemImage: "checkmark.circle")
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    if let word = session.currentWord {
                        let card = session.cardID
                        Text("\(session.completed + 1) of \(session.total)")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(word.text).font(.largeTitle.bold()).textSelection(.enabled)
                        Text(word.partOfSpeech).foregroundStyle(.secondary)
                        if session.revealed {
                            Text(word.meaning).font(.title3)
                            ForEach(Array(word.examples.enumerated()), id: \.offset) { _, example in
                                Text(example).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            Button { reveal(card) } label: {
                                Label("Reveal", systemImage: "eye")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        HStack(spacing: 16) {
                            Button { grade(.again, card: card) } label: {
                                Label("Again", systemImage: "arrow.counterclockwise")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            Button { grade(.remember, card: card) } label: {
                                Label("Remember", systemImage: "checkmark")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .disabled(!session.revealed)
                    } else {
                        ContentUnavailableView(session.completed > 0 ? "Review Complete" : "No Words to Review",
                                               systemImage: session.completed > 0 ? "checkmark.circle" : "calendar")
                        Button { start() } label: { Label("Start New Review", systemImage: "arrow.clockwise") }
                            .buttonStyle(.bordered)
                    }
                    if let message { Text(message).foregroundStyle(.red) }
                    if recovery != nil {
                        Button { exportingRecovery = true } label: {
                            Label("Export Recovery Backup", systemImage: "externaldrive.badge.exclamationmark")
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(session.topicName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .fileExporter(isPresented: $exportingRecovery, document: recovery, contentType: .json,
                          defaultFilename: "VocabularyRecoveryBackup") { result in
                if case .failure(let error) = result { report(error) }
            }
            .task {
                start()
                while !Task.isCancelled {
                    let now = Date.now
                    let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
                    let delay = min(30, max(0.1, midnight?.timeIntervalSince(now) ?? 30))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    guard !Task.isCancelled else { break }
                    refresh()
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refresh() }
        }
    }

    private func start() {
        do { try session.start(); message = nil } catch { report(error) }
    }

    private func refresh() {
        do { try session.refresh() } catch { report(error) }
    }

    private func reveal(_ card: UUID) {
        do { try session.reveal(card: card); message = nil } catch { report(error) }
    }

    private func grade(_ grade: ReviewGrade, card: UUID) {
        do { try session.grade(grade, card: card); message = nil } catch { report(error) }
    }

    private func report(_ error: Error) {
        if case LearningStorageError.rollbackFailed(let data) = error { recovery = VocabularyBackupDocument(data: data) }
        if case LearningStorageError.staleSession = error { try? session.refresh() }
        message = error.localizedDescription
    }
}