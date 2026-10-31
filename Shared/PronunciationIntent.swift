import Foundation

// Kept platform-independent so the pronunciation policy can be checked with swiftc.
enum PronunciationPolicy {
    static func speechText(_ word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func preferredVoiceIndex(languages: [String]) -> Int? {
        let normalized = languages.map { $0.replacingOccurrences(of: "_", with: "-").lowercased() }
        return normalized.firstIndex(of: "en-us")
            ?? normalized.firstIndex { $0 == "en" || $0.hasPrefix("en-") }
    }

    static func speechRate(defaultRate: Float) -> Float {
        defaultRate * 0.9
    }
}

enum PronunciationAudioSessionPolicy {
    enum Category { case playback }
    enum Mode { case spokenAudio }
    enum Option: Hashable { case mixWithOthers }
    enum Completion: CaseIterable { case finish, cancel, timeout, renderTimeout, startFailure, replacement }

    static let renderTimeoutNanoseconds: UInt64 = 5_000_000_000
    static let playbackTimeoutNanoseconds: UInt64 = 30_000_000_000
    static let activationRetryDelayNanoseconds: UInt64 = 150_000_000
    static let debounceNanoseconds: UInt64 = 300_000_000
    static let cannotStartPlayingCode = 561_015_905
    static let ioStartDeniedCode = 2_003_329_396
    static let category = Category.playback
    static let mode = Mode.spokenAudio
    static let options: Set<Option> = [.mixWithOthers]

    static func shouldRetryActivation(errorCode: Int, attempt: Int) -> Bool {
        errorCode == cannotStartPlayingCode && attempt == 0
    }

    // A suspended app process woken in background cannot regain audio IO; only an intent cold launch can.
    static func shouldRecycleProcess(errorCode: Int, isBackground: Bool) -> Bool {
        isBackground && (errorCode == ioStartDeniedCode || errorCode == cannotStartPlayingCode)
    }

    static func shouldDebounce(existingWord: String, incomingWord: String, elapsedNanoseconds: UInt64) -> Bool {
        existingWord == incomingWord && elapsedNanoseconds < debounceNanoseconds
    }

    static func shouldDeactivate(after completion: Completion) -> Bool {
        false
    }

    struct Ownership {
        private(set) var isOwned = false

        mutating func begin() {
            isOwned = true
        }

        mutating func complete(_ completion: Completion) -> Bool {
            false
        }

        mutating func reset() {
            isOwned = false
        }
    }
}

#if os(iOS)
import AppIntents
import AVFoundation
import os
#if APP_PROCESS_DIAGNOSTICS
import UIKit
#endif

func pronunciationLog(_ message: String, error: Error? = nil) {
    var details = message
    if let error {
        let value = error as NSError
        details += " errorDomain=\(value.domain) errorCode=\(value.code)"
        let code = UInt32(truncatingIfNeeded: value.code)
        let bytes = [UInt8(code >> 24), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        if bytes.allSatisfy({ (0x20...0x7E).contains($0) }),
           let fourCC = String(bytes: bytes, encoding: .ascii) {
            details += " fourCC=\(fourCC)"
        }
    }
    let wallClockMilliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
    let uptimeMilliseconds = Int64(ProcessInfo.processInfo.systemUptime * 1_000)
    let line = "[Pronunciation wallMs=\(wallClockMilliseconds) uptimeMs=\(uptimeMilliseconds)] \(details)"
    let logger = Logger(subsystem: "com.phanquocviet.VocabularyWidget", category: "Pronunciation")
    logger.log(level: error == nil ? .info : .error, "\(line, privacy: .public)")
    print(line)
    PronunciationLogFile.append(line)
}

// Survives console detachment; fetch with `devicectl device copy from --domain-type appDataContainer`.
private enum PronunciationLogFile {
    private static let queue = DispatchQueue(label: "com.phanquocviet.VocabularyWidget.pronunciation-log")
    private static let maxBytes = 512 * 1024
    private static let url: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("pronunciation.log")

    static func append(_ line: String) {
        guard let url else { return }
        let process = "pid=\(ProcessInfo.processInfo.processIdentifier) proc=\(ProcessInfo.processInfo.processName) "
        let data = Data((process + line + "\n").utf8)
        queue.async {
            let manager = FileManager.default
            if let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? Int), size > maxBytes {
                try? manager.removeItem(at: url)
            }
            if !manager.fileExists(atPath: url.path) {
                manager.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}

private extension PronunciationAudioSessionPolicy {
    static var audioCategory: AVAudioSession.Category {
        switch category { case .playback: return .playback }
    }

    static var audioMode: AVAudioSession.Mode {
        switch mode { case .spokenAudio: return .spokenAudio }
    }

    static var audioOptions: AVAudioSession.CategoryOptions {
        options.reduce(into: AVAudioSession.CategoryOptions()) { result, option in
            switch option { case .mixWithOthers: result.insert(.mixWithOthers) }
        }
    }
}

enum PronunciationAudioWarmup {
    @MainActor static func prepareInForeground() {
        WordPronunciationPlayer.shared.prepareForegroundSession()
    }
}

struct SpeakWordIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Phát âm"
    @Parameter(title: "Từ") var word: String

    init() {}

    init(word: String) {
        self.word = word
    }

    func perform() async throws -> some IntentResult {
        let requestID = UUID()
        let startedAt = ProcessInfo.processInfo.systemUptime
        pronunciationLog("perform begin request=\(requestID.uuidString) wordLength=\(word.count) bundleID=\(Bundle.main.bundleIdentifier ?? "nil") processName=\(ProcessInfo.processInfo.processName)")
        do {
            try await WordPronunciationPlayer.shared.speak(word, requestID: requestID)
            let reason = PronunciationPolicy.speechText(word) == nil ? "empty-word" : "completed"
            pronunciationLog("perform end request=\(requestID.uuidString) elapsedMs=\(Int64((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)) exitReason=\(reason)")
            return .result()
        } catch {
            pronunciationLog("perform end request=\(requestID.uuidString) elapsedMs=\(Int64((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)) exitReason=error", error: error)
            throw error
        }
    }
}

@MainActor
private final class WordPronunciationPlayer: NSObject {
    static let shared = WordPronunciationPlayer()

    private enum Stage: Equatable { case rendering, playing }

    private struct Playback {
        let id: UUID
        let text: String
        let startedAt: TimeInterval
        let continuation: CheckedContinuation<Void, Error>
        var stage: Stage
        var timeout: Task<Void, Never>?
        var buffers: [AVAudioPCMBuffer] = []
        var collector: RenderCollector?
        var groupStartIndex = 0
        var scheduleGeneration = 0
    }

    private final class RenderCallbackCounter {
        private let lock = NSLock()
        private var value = 0

        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            defer { value += 1 }
            return value
        }
    }

    private final class RenderCollector {
        private let lock = NSLock()
        private var values: [AVAudioPCMBuffer] = []
        private var finished = false

        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            finished = true
            values.removeAll()
        }

        func append(_ buffer: AVAudioPCMBuffer) -> [AVAudioPCMBuffer]? {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return nil }
            if buffer.frameLength == 0 {
                finished = true
                return values
            }
            values.append(buffer)
            return nil
        }
    }

    private var playback: Playback?
    private var audioOwnership = PronunciationAudioSessionPolicy.Ownership()
    private var synthesizer = AVSpeechSynthesizer()
    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var connectedFormat: AVAudioFormat?
    private var notificationObservers: [NSObjectProtocol] = []
    private var engineConfigurationObserver: NSObjectProtocol?
    private var completedRequestCount = 0
    private static let processStartUptime = ProcessInfo.processInfo.systemUptime

    private override init() {
        super.init()
        engine.attach(playerNode)
        observeAudioSessionNotifications()
        observeApplicationLifecycle()
        pronunciationLog("renderer created synthesizerID=\(ObjectIdentifier(synthesizer).hashValue) processUptimeMs=\(Int64((ProcessInfo.processInfo.systemUptime - Self.processStartUptime) * 1_000)) appState=\(applicationStateDescription())")
    }

    func speak(_ word: String, requestID: UUID) async throws {
        pronunciationLog("request start request=\(requestID.uuidString) wordLength=\(word.count) appState=\(applicationStateDescription())")
        guard let text = PronunciationPolicy.speechText(word) else { return }
        let id = requestID
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let now = ProcessInfo.processInfo.systemUptime
                if let current = playback,
                   PronunciationAudioSessionPolicy.shouldDebounce(
                    existingWord: current.text,
                    incomingWord: text,
                    elapsedNanoseconds: UInt64(max(0, now - current.startedAt) * 1_000_000_000)) {
                    pronunciationLog("request debounced request=\(id.uuidString) currentRequest=\(current.id.uuidString) wordLength=\(text.count)")
                    continuation.resume()
                    return
                }
                if let current = playback {
                    pronunciationLog("replacement begin previousRequest=\(current.id.uuidString) request=\(id.uuidString)")
                    complete(id: current.id, reason: .replacement, error: nil, stop: true)
                }

                playback = Playback(id: id, text: text, startedAt: now, continuation: continuation, stage: .rendering)
                armTimeout(id: id, duration: PronunciationAudioSessionPolicy.renderTimeoutNanoseconds, reason: .renderTimeout)
                Task { @MainActor [weak self] in await self?.activateAndRender(id: id) }
            }
        } onCancel: {
            pronunciationLog("request cancellation requested request=\(id.uuidString)")
            Task { @MainActor in
                self.complete(id: id, reason: .cancel, error: CancellationError(), stop: true)
            }
        }
    }

    func prepareForegroundSession() {
        guard playback == nil else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(PronunciationAudioSessionPolicy.audioCategory,
                                    mode: PronunciationAudioSessionPolicy.audioMode,
                                    options: PronunciationAudioSessionPolicy.audioOptions)
            try session.setActive(true)
            audioOwnership.begin()
            pronunciationLog("foreground session prepared appState=\(applicationStateDescription())")
        } catch {
            pronunciationLog("foreground session prepare failure appState=\(applicationStateDescription())", error: error)
        }
    }

    private func recycleProcessIfAudioDenied(_ error: Error, requestID: UUID) {
        #if APP_PROCESS_DIAGNOSTICS
        let code = (error as NSError).code
        guard PronunciationAudioSessionPolicy.shouldRecycleProcess(errorCode: code,
                                                                   isBackground: applicationStateDescription() == "background") else { return }
        pronunciationLog("process recycle scheduled request=\(requestID.uuidString) delayMs=500", error: error)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard UIApplication.shared.applicationState == .background, self?.playback == nil else {
                pronunciationLog("process recycle skipped appState=\(self?.applicationStateDescription() ?? "unknown")")
                return
            }
            pronunciationLog("process recycle exit")
            exit(0)
        }
        #endif
    }

    private func applicationStateDescription() -> String {
        #if APP_PROCESS_DIAGNOSTICS
        guard Bundle.main.bundleURL.pathExtension != "appex",
              Bundle.main.bundleIdentifier == "com.phanquocviet.VocabularyWidget" else { return "unavailable" }
        switch UIApplication.shared.applicationState {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
        #else
        return "unavailable"
        #endif
    }

    private func logAudioSessionState(_ session: AVAudioSession, requestID: UUID) {
        let outputs = session.currentRoute.outputs.map { "\($0.portType.rawValue)/\($0.portName)" }.joined(separator: ",")
        pronunciationLog("setActive(true) success request=\(requestID.uuidString) category=\(session.category.rawValue) mode=\(session.mode.rawValue) outputVolume=\(session.outputVolume) outputs=[\(outputs)] secondaryAudioShouldBeSilencedHint=\(session.secondaryAudioShouldBeSilencedHint)")
    }

    private func logActivationFailure(_ error: Error, requestID: UUID, attempt: Int) {
        let code = (error as NSError).code
        if code == PronunciationAudioSessionPolicy.cannotStartPlayingCode,
           applicationStateDescription() == "background" {
            pronunciationLog("activation denied in background request=\(requestID.uuidString) attempt=\(attempt)", error: error)
        } else {
            pronunciationLog("setActive(true) failure request=\(requestID.uuidString) attempt=\(attempt)", error: error)
        }
    }

    private func activateAndRender(id: UUID) async {
        guard playback?.id == id else { return }
        let session = AVAudioSession.sharedInstance()
        if !audioOwnership.isOwned {
            do {
                try session.setCategory(PronunciationAudioSessionPolicy.audioCategory,
                                        mode: PronunciationAudioSessionPolicy.audioMode,
                                        options: PronunciationAudioSessionPolicy.audioOptions)
                pronunciationLog("setCategory success request=\(id.uuidString)")
            } catch {
                pronunciationLog("setCategory failure request=\(id.uuidString)", error: error)
                complete(id: id, reason: .startFailure, error: error, stop: false)
                return
            }
            do {
                try session.setActive(true)
            } catch {
                logActivationFailure(error, requestID: id, attempt: 1)
                guard PronunciationAudioSessionPolicy.shouldRetryActivation(errorCode: (error as NSError).code, attempt: 0) else {
                    complete(id: id, reason: .startFailure, error: error, stop: false)
                    return
                }
                pronunciationLog("setActive(true) retry scheduled request=\(id.uuidString) delayMs=150")
                do {
                    try await Task.sleep(nanoseconds: PronunciationAudioSessionPolicy.activationRetryDelayNanoseconds)
                } catch {
                    complete(id: id, reason: .cancel, error: CancellationError(), stop: false)
                    return
                }
                guard playback?.id == id else { return }
                do {
                    try session.setActive(true)
                } catch {
                    logActivationFailure(error, requestID: id, attempt: 2)
                    complete(id: id, reason: .startFailure, error: error, stop: false)
                    recycleProcessIfAudioDenied(error, requestID: id)
                    return
                }
            }
            audioOwnership.begin()
        } else {
            pronunciationLog("audio session reuse request=\(id.uuidString) active=true")
        }
        guard playback?.id == id else { return }
        logAudioSessionState(session, requestID: id)

        let utterance = AVSpeechUtterance(string: playback?.text ?? "")
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let index = PronunciationPolicy.preferredVoiceIndex(languages: voices.map(\.language)) {
            utterance.voice = voices[index]
        }
        utterance.rate = PronunciationPolicy.speechRate(defaultRate: AVSpeechUtteranceDefaultSpeechRate)
        let collector = RenderCollector()
        playback?.collector = collector
        armTimeout(id: id, duration: PronunciationAudioSessionPolicy.renderTimeoutNanoseconds, reason: .renderTimeout)
        pronunciationLog("render begin request=\(id.uuidString) synthesizerID=\(ObjectIdentifier(synthesizer).hashValue) priorCompletedRequests=\(completedRequestCount) synthIsSpeaking=\(synthesizer.isSpeaking) synthIsPaused=\(synthesizer.isPaused) voice=\(utterance.voice?.identifier ?? "default") engineRunning=\(engine.isRunning) playerPlaying=\(playerNode.isPlaying) otherAudioPlaying=\(session.isOtherAudioPlaying) appState=\(applicationStateDescription())")
        let callbackCounter = RenderCallbackCounter()
        synthesizer.write(utterance) { [weak self] buffer in
            let callbackIndex = callbackCounter.next()
            guard let pcm = buffer as? AVAudioPCMBuffer else {
                pronunciationLog("render callback non-PCM request=\(id.uuidString) index=\(callbackIndex) type=\(String(describing: type(of: buffer)))")
                return
            }
            if callbackIndex < 3 || pcm.frameLength == 0 {
                pronunciationLog("render callback request=\(id.uuidString) index=\(callbackIndex) frames=\(pcm.frameLength) sampleRate=\(pcm.format.sampleRate) channels=\(pcm.format.channelCount) commonFormat=\(pcm.format.commonFormat.rawValue) interleaved=\(pcm.format.isInterleaved)")
            }
            // The synthesizer owns callback storage; retain an independent copy for deferred playback.
            guard let copy = AVAudioPCMBuffer(pcmFormat: pcm.format, frameCapacity: max(1, pcm.frameLength)) else {
                Task { @MainActor [weak self] in
                    self?.complete(id: id, reason: .startFailure, error: PronunciationPlaybackError.emptyRender, stop: true)
                }
                return
            }
            copy.frameLength = pcm.frameLength
            if pcm.frameLength > 0 {
                let source = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
                let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
                for index in source.indices {
                    if let sourceData = source[index].mData, let destinationData = destination[index].mData {
                        memcpy(destinationData, sourceData, Int(source[index].mDataByteSize))
                    }
                }
            }
            guard let buffers = collector.append(copy) else { return }
            Task { @MainActor [weak self] in self?.renderCompleted(id: id, buffers: buffers) }
        }
    }

    private func renderCompleted(id: UUID, buffers: [AVAudioPCMBuffer]) {
        guard var current = playback, current.id == id, current.stage == .rendering else { return }
        current.timeout?.cancel()
        guard !buffers.isEmpty else {
            complete(id: id, reason: .startFailure, error: PronunciationPlaybackError.emptyRender, stop: false)
            return
        }
        current.stage = .playing
        current.buffers = buffers
        current.groupStartIndex = 0
        playback = current
        pronunciationLog("render complete request=\(id.uuidString) bufferCount=\(buffers.count) frameCount=\(buffers.reduce(UInt64(0)) { $0 + UInt64($1.frameLength) }) peakAmplitude=\(Self.peakAmplitude(buffers)) renderMs=\(Int64((ProcessInfo.processInfo.systemUptime - current.startedAt) * 1_000))")
        armTimeout(id: id, duration: PronunciationAudioSessionPolicy.playbackTimeoutNanoseconds, reason: .timeout)
        scheduleNextFormatGroup(id: id)
    }

    private func scheduleNextFormatGroup(id: UUID) {
        guard var current = playback, current.id == id, current.stage == .playing else { return }
        guard current.groupStartIndex < current.buffers.count else {
            complete(id: id, reason: .finish, error: nil, stop: false)
            return
        }
        let start = current.groupStartIndex
        let format = current.buffers[start].format
        var end = start + 1
        while end < current.buffers.count && formatsMatch(current.buffers[end].format, format) {
            end += 1
        }
        current.groupStartIndex = end
        current.scheduleGeneration += 1
        let generation = current.scheduleGeneration
        playback = current

        do {
            try connectAndStartEngine(format: format, requestID: id)
        } catch {
            complete(id: id, reason: .startFailure, error: error, stop: true)
            recycleProcessIfAudioDenied(error, requestID: id)
            return
        }
        for index in start..<end {
            let isLast = index == end - 1
            let buffer = current.buffers[index]
            if isLast {
                playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    pronunciationLog("playback dataPlayedBack request=\(id.uuidString) generation=\(generation)")
                    Task { @MainActor [weak self] in self?.formatGroupPlayed(id: id, generation: generation) }
                }
            } else {
                playerNode.scheduleBuffer(buffer)
            }
        }
        playerNode.play()
        let session = AVAudioSession.sharedInstance()
        let output = engine.outputNode.outputFormat(forBus: 0)
        let outputs = session.currentRoute.outputs.map { "\($0.portType.rawValue)/\($0.portName)" }.joined(separator: ",")
        pronunciationLog("playback scheduled request=\(id.uuidString) bufferStart=\(start) bufferEnd=\(end) sampleRate=\(format.sampleRate) channels=\(format.channelCount) engineRunning=\(engine.isRunning) playerPlaying=\(playerNode.isPlaying) playerVolume=\(playerNode.volume) mixerVolume=\(engine.mainMixerNode.outputVolume) outputSampleRate=\(output.sampleRate) outputChannels=\(output.channelCount) sessionOutputVolume=\(session.outputVolume) outputs=[\(outputs)] appState=\(applicationStateDescription())")
    }

    private func formatGroupPlayed(id: UUID, generation: Int) {
        guard let current = playback, current.id == id, current.stage == .playing,
              current.scheduleGeneration == generation else { return }
        scheduleNextFormatGroup(id: id)
    }

    private func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate && lhs.channelCount == rhs.channelCount &&
            lhs.commonFormat == rhs.commonFormat && lhs.isInterleaved == rhs.isInterleaved
    }

    private func connectAndStartEngine(format: AVAudioFormat, requestID: UUID) throws {
        if let connectedFormat, !formatsMatch(connectedFormat, format) {
            playerNode.stop()
            engine.stop()
            engine.disconnectNodeOutput(playerNode)
            self.connectedFormat = nil
            pronunciationLog("engine reconnect request=\(requestID.uuidString) sampleRate=\(format.sampleRate) channels=\(format.channelCount)")
        }
        if connectedFormat == nil {
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            connectedFormat = format
        }
        engine.prepare()
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            pronunciationLog("engine started request=\(requestID.uuidString)")
            return
        } catch {
            let session = AVAudioSession.sharedInstance()
            let outputs = session.currentRoute.outputs.map { "\($0.portType.rawValue)/\($0.portName)" }.joined(separator: ",")
            pronunciationLog("engine start failure request=\(requestID.uuidString) otherAudioPlaying=\(session.isOtherAudioPlaying) sessionSampleRate=\(session.sampleRate) outputs=[\(outputs)] appState=\(applicationStateDescription())", error: error)
        }
        // A stale output unit (e.g. after a route or hardware change) can refuse to start; rebuild it once.
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            pronunciationLog("engine recovery setActive(true) success request=\(requestID.uuidString)")
        } catch {
            pronunciationLog("engine recovery setActive(true) failure request=\(requestID.uuidString)", error: error)
        }
        recreateEngine()
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        connectedFormat = format
        engine.prepare()
        do {
            try engine.start()
            pronunciationLog("engine started after recovery request=\(requestID.uuidString)")
        } catch {
            pronunciationLog("engine start failure after recovery request=\(requestID.uuidString)", error: error)
            throw error
        }
    }

    private func armTimeout(id: UUID, duration: UInt64, reason: PronunciationAudioSessionPolicy.Completion) {
        guard var current = playback, current.id == id else { return }
        current.timeout?.cancel()
        current.timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: duration) } catch { return }
            guard let self, self.playback?.id == id else { return }
            pronunciationLog("timeout request=\(id.uuidString) reason=\(reason)")
            let error: Error = reason == .renderTimeout ? PronunciationPlaybackError.renderTimeout : PronunciationPlaybackError.playbackTimeout
            self.complete(id: id, reason: reason, error: error, stop: true)
        }
        playback = current
    }

    private func complete(id: UUID, reason: PronunciationAudioSessionPolicy.Completion, error: Error?, stop: Bool) {
        guard let current = playback, current.id == id else { return }
        playback = nil
        current.timeout?.cancel()
        current.collector?.cancel()
        if stop {
            playerNode.stop()
            synthesizer.stopSpeaking(at: .immediate)
        }
        completedRequestCount += 1
        pronunciationLog("request completed request=\(id.uuidString) reason=\(reason) stage=\(current.stage) elapsedMs=\(Int64((ProcessInfo.processInfo.systemUptime - current.startedAt) * 1_000)) stop=\(stop) error=\(error.map { String(describing: $0) } ?? "nil") synthIsSpeaking=\(synthesizer.isSpeaking) engineRunning=\(engine.isRunning)")
        playerNode.stop()
        engine.pause()
        pronunciationLog("engine paused request=\(id.uuidString) reason=\(reason) engineRunning=\(engine.isRunning)")
        if let error { current.continuation.resume(throwing: error) }
        else { current.continuation.resume() }
    }

    private func observeAudioSessionNotifications() {
        let center = NotificationCenter.default
        notificationObservers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: nil) { notification in
            let values = notification.userInfo ?? [:]
            let type = (values[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue ?? 0
            let options = (values[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            Task { @MainActor [weak self] in self?.handleAudioInterruption(type: type, options: options) }
        })
        notificationObservers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), queue: nil) { notification in
            let rawReason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue ?? 0
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map { "\($0.portType.rawValue)/\($0.portName)" }.joined(separator: ",")
            Task { @MainActor in pronunciationLog("audio route change reason=\(rawReason) outputs=[\(outputs)]") }
        })
        notificationObservers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: AVAudioSession.sharedInstance(), queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleMediaServicesReset() }
        })
        observeEngineConfigurationChanges()
    }

    private func handleAudioInterruption(type: UInt, options: UInt) {
        pronunciationLog("audio interruption type=\(type) options=\(options)")
        if type == AVAudioSession.InterruptionType.began.rawValue, let current = playback {
            complete(id: current.id, reason: .cancel, error: CancellationError(), stop: true)
        }
        guard type == AVAudioSession.InterruptionType.ended.rawValue else { return }
        audioOwnership.reset()
        pronunciationLog("audio session active flag reset after interruption ended")
    }

    private func observeApplicationLifecycle() {
        #if APP_PROCESS_DIAGNOSTICS
        let center = NotificationCenter.default
        let names: [(Notification.Name, String)] = [
            (UIApplication.didEnterBackgroundNotification, "didEnterBackground"),
            (UIApplication.willEnterForegroundNotification, "willEnterForeground"),
            (UIApplication.didBecomeActiveNotification, "didBecomeActive"),
            (UIApplication.willResignActiveNotification, "willResignActive"),
            (UIApplication.didReceiveMemoryWarningNotification, "memoryWarning"),
            (UIApplication.willTerminateNotification, "willTerminate"),
        ]
        for (name, label) in names {
            notificationObservers.append(center.addObserver(forName: name, object: nil, queue: nil) { _ in
                pronunciationLog("app lifecycle \(label)")
            })
        }
        #endif
        notificationObservers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: AVAudioSession.sharedInstance(), queue: nil) { notification in
            let type = (notification.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? NSNumber)?.uintValue ?? 0
            pronunciationLog("audio silenceSecondaryAudioHint type=\(type)")
        })
    }

    private static func peakAmplitude(_ buffers: [AVAudioPCMBuffer]) -> String {
        var peak: Float = 0
        for buffer in buffers {
            let frames = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
            if let data = buffer.floatChannelData {
                for channel in 0..<channels { for frame in 0..<frames { peak = max(peak, abs(data[channel][frame])) } }
            } else if let data = buffer.int16ChannelData {
                for channel in 0..<channels { for frame in 0..<frames { peak = max(peak, abs(Float(data[channel][frame]) / Float(Int16.max))) } }
            } else if let data = buffer.int32ChannelData {
                for channel in 0..<channels { for frame in 0..<frames { peak = max(peak, abs(Float(data[channel][frame]) / Float(Int32.max))) } }
            } else {
                return "unknown-format"
            }
        }
        return String(format: "%.4f", peak)
    }

    private func observeEngineConfigurationChanges() {
        if let engineConfigurationObserver {
            NotificationCenter.default.removeObserver(engineConfigurationObserver)
        }
        let observedEngineID = ObjectIdentifier(engine)
        engineConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, ObjectIdentifier(self.engine) == observedEngineID else { return }
                self.handleEngineConfigurationChange()
            }
        }
    }

    private func handleEngineConfigurationChange() {
        pronunciationLog("audio engine configuration changed")
        engine.stop()
        playerNode.stop()
        engine.disconnectNodeOutput(playerNode)
        connectedFormat = nil
        guard let current = playback, current.stage == .playing,
              current.groupStartIndex > 0 else { return }
        playerNode.stop()
        currentScheduleRestart(id: current.id, index: current.groupStartIndex)
    }

    private func currentScheduleRestart(id: UUID, index: Int) {
        guard var current = playback, current.id == id else { return }
        var start = index - 1
        while start > 0 && formatsMatch(current.buffers[start - 1].format, current.buffers[index - 1].format) {
            start -= 1
        }
        current.groupStartIndex = start
        playback = current
        scheduleNextFormatGroup(id: id)
    }

    private func handleMediaServicesReset() {
        pronunciationLog("media services reset")
        if let current = playback {
            complete(id: current.id, reason: .startFailure, error: PronunciationPlaybackError.mediaServicesReset, stop: true)
        }
        audioOwnership.reset()
        pronunciationLog("audio session active flag reset after media services reset")
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer = AVSpeechSynthesizer()
        recreateEngine()
        pronunciationLog("renderer recreated after media services reset synthesizerID=\(ObjectIdentifier(synthesizer).hashValue)")
    }

    private func recreateEngine() {
        engine.stop()
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        connectedFormat = nil
        observeEngineConfigurationChanges()
    }
}

private enum PronunciationPlaybackError: LocalizedError {
    case emptyRender
    case renderTimeout
    case playbackTimeout
    case mediaServicesReset

    var errorDescription: String? {
        switch self {
        case .emptyRender: return "Speech synthesis produced no audio buffers."
        case .renderTimeout: return "Speech synthesis did not finish rendering in time."
        case .playbackTimeout: return "Speech playback did not finish in time."
        case .mediaServicesReset: return "Audio services were reset during pronunciation."
        }
    }
}
#endif
