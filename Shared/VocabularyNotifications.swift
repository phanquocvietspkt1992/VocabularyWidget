import Foundation

#if os(iOS)
import UserNotifications
import AVFoundation
import CryptoKit

@MainActor
private final class NotificationSpeechRenderer {
    private let synthesizer = AVSpeechSynthesizer()
    private var file: AVAudioFile?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeout: Task<Void, Never>?

    func render(word: String, to url: URL) async -> Bool {
        guard let text = PronunciationPolicy.speechText(word) else { return false }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let utterance = AVSpeechUtterance(string: text)
            let voices = AVSpeechSynthesisVoice.speechVoices()
            if let index = PronunciationPolicy.preferredVoiceIndex(languages: voices.map(\.language)) {
                utterance.voice = voices[index]
            }
            utterance.rate = PronunciationPolicy.speechRate(defaultRate: AVSpeechUtteranceDefaultSpeechRate)
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: PronunciationAudioSessionPolicy.renderTimeoutNanoseconds)
                guard !Task.isCancelled else { return }
                self?.finish(false)
            }
            synthesizer.write(utterance) { [weak self] buffer in
                Task { @MainActor in
                    guard let self, self.continuation != nil, let pcm = buffer as? AVAudioPCMBuffer else { return }
                    if pcm.frameLength == 0 { self.finish(self.file != nil); return }
                    do {
                        if self.file == nil {
                            self.file = try AVAudioFile(forWriting: url, settings: pcm.format.settings)
                        }
                        try self.file?.write(from: pcm)
                        if let file = self.file, Double(file.length) / file.fileFormat.sampleRate >= 29 {
                            self.finish(false)
                        }
                    } catch { self.finish(false) }
                }
            }
        }
    }

    private func finish(_ success: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        file = nil
        if !success { synthesizer.stopSpeaking(at: .immediate) }
        continuation.resume(returning: success)
    }
}

enum VocabularyNotifications {
    static let identifierPrefix = VocabularyNotificationPlan.identifierPrefix
    @MainActor private static var generation = 0

    @MainActor
    static func reschedule() async {
        generation += 1
        let generation = generation
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        guard generation == self.generation else { return }
        let authorization = await center.notificationSettings()
        guard generation == self.generation else { return }
        guard WidgetProgressStore.schedule.notificationsEnabled,
              authorization.authorizationStatus == .authorized || authorization.authorizationStatus == .provisional else {
            center.removePendingNotificationRequests(withIdentifiers: VocabularyNotificationPlan.obsoleteIdentifiers(pending.map(\.identifier), keeping: []))
            pronunciationLog("notifications cleared enabled=\(WidgetProgressStore.schedule.notificationsEnabled) authorization=\(authorization.authorizationStatus.rawValue)")
            return
        }
        let plan = VocabularyNotificationPlan.make()
        center.removePendingNotificationRequests(withIdentifiers: VocabularyNotificationPlan.obsoleteIdentifiers(pending.map(\.identifier), keeping: plan))
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetProgressStore.appGroupID)
        let sounds = container?.appendingPathComponent("Library/Sounds", isDirectory: true)
        if let sounds { try? FileManager.default.createDirectory(at: sounds, withIntermediateDirectories: true) }
        let canRender = Bundle.main.bundleURL.pathExtension != "appex"
        var soundNames: [String: String?] = [:]
        var added = 0
        pronunciationLog("notifications reschedule plan=\(plan.count) first=\(plan.map(\.date).min()?.description ?? "none") pendingBefore=\(pending.count)")
        // Schedule in time order, rendering each missing sound just before its request, so the nearest reminder is queued first.
        for point in plan.sorted(by: { $0.date < $1.date }) {
            guard generation == self.generation else { return }
            let word = point.word.text
            if soundNames[word] == nil {
                soundNames[word] = .some(await soundName(for: word, in: sounds, canRender: canRender))
                guard generation == self.generation else { return }
            }
            let content = UNMutableNotificationContent()
            content.title = "\(point.word.text) \(point.word.partOfSpeech)"
            content.subtitle = "\(point.word.meaning) · \(point.topicName)"
            content.body = point.word.examples.joined(separator: "\n")
            content.sound = (soundNames[word] ?? nil).map { UNNotificationSound(named: UNNotificationSoundName(rawValue: $0)) } ?? .default
            let delay = point.date.timeIntervalSinceNow
            guard delay > 0 else { continue }
            let request = UNNotificationRequest(identifier: VocabularyNotificationPlan.identifier(for: point.date), content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false))
            do { try await center.add(request); added += 1 }
            catch { pronunciationLog("notification add failure", error: error) }
            if added == 1 { pronunciationLog("notification first queued at=\(point.date) customSound=\(soundNames[word] != nil && soundNames[word]! != nil)") }
        }
        pronunciationLog("notifications reschedule done added=\(added)")
    }

    @MainActor
    private static func soundName(for word: String, in sounds: URL?, canRender: Bool) async -> String? {
        guard let sounds else { return nil }
        let digest = SHA256.hash(data: Data(word.utf8)).map { String(format: "%02x", $0) }.joined()
        let name = "word-\(digest).caf"
        let url = sounds.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return name }
        guard canRender else { return nil }
        // Publish only completed CAF files so the extension never reads partial audio.
        let staging = sounds.appendingPathComponent("\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: staging) }
        guard await NotificationSpeechRenderer().render(word: word, to: staging) else { return nil }
        do { try FileManager.default.moveItem(at: staging, to: url) } catch {}
        return FileManager.default.fileExists(atPath: url.path) ? name : nil
    }
}
#else
enum VocabularyNotifications {
    static func reschedule() async {}
}
#endif
