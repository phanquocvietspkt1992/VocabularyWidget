import Foundation

enum SentenceSound: CaseIterable {
    case music, select, suspense, correct, incorrect, finish

    var notes: [Double] {
        switch self {
        case .music: return [293.66, 0, 349.23, 392, 0, 440, 392, 349.23, 293.66, 0, 392, 440, 523.25, 440, 392, 293.66]
        case .select: return [405, 540]
        case .suspense: return [82, 82, 82, 98, 98, 123, 123, 164]
        case .correct: return [330, 495, 660]
        case .incorrect: return [180, 135, 90]
        case .finish: return [270, 405, 540, 810]
        }
    }

    var noteDuration: Double {
        switch self {
        case .music: return 0.32
        case .suspense: return 0.14
        case .select: return 0.07
        case .correct, .incorrect, .finish: return 0.16
        }
    }

    func wave() -> Data {
        let rate = 22_050
        let samplesPerNote = Int(Double(rate) * noteDuration)
        let sampleCount = samplesPerNote * notes.count
        var bytes = Data()
        func append16(_ value: UInt16) {
            bytes.append(UInt8(truncatingIfNeeded: value))
            bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func append32(_ value: UInt32) {
            append16(UInt16(truncatingIfNeeded: value))
            append16(UInt16(truncatingIfNeeded: value >> 16))
        }
        bytes.append(contentsOf: "RIFF".utf8)
        append32(UInt32(36 + sampleCount * 2))
        bytes.append(contentsOf: "WAVEfmt ".utf8)
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(rate))
        append32(UInt32(rate * 2))
        append16(2)
        append16(16)
        bytes.append(contentsOf: "data".utf8)
        append32(UInt32(sampleCount * 2))
        var samples: [Double] = []
        samples.reserveCapacity(sampleCount)
        let musicChords = [
            [146.83, 174.61, 220.00],
            [130.81, 164.81, 196.00],
            [116.54, 146.83, 174.61],
            [146.83, 174.61, 220.00]
        ]
        for (noteIndex, frequency) in notes.enumerated() {
            for sample in 0..<samplesPerNote {
                let time = Double(sample) / Double(rate)
                let position = noteIndex * samplesPerNote + sample
                let elapsed = Double(position) / Double(rate)
                let progress = Double(sample) / Double(samplesPerNote - 1)
                let duration = Double(sampleCount - 1) / Double(rate)
                let boundary = self == .music
                    ? min(1, elapsed / 0.012, (duration - elapsed) / 0.012)
                    : min(1, elapsed / 0.04, (duration - elapsed) / 0.08)
                let envelope = pow(sin(Double.pi * progress), 2)
                let phase = 2 * Double.pi * frequency * time
                let tone = frequency == 0 ? 0 : 0.46 * sin(phase) + 0.12 * sin(phase * 2) + 0.06 * sin(phase * 3)
                let layer: Double
                switch self {
                case .music:
                    let chordIndex = noteIndex / 4
                    let previousChord = musicChords[(chordIndex + musicChords.count - 1) % musicChords.count]
                    let chord = musicChords[chordIndex]
                    let transition = min(1, time / 0.08)
                    let blend = transition * transition * (3 - 2 * transition)
                    let previousPad = previousChord.reduce(0) { $0 + sin(2 * Double.pi * $1 * elapsed) }
                    let pad = chord.reduce(0) { $0 + sin(2 * Double.pi * $1 * elapsed) }
                    let pulse = noteIndex.isMultiple(of: 2) ? 0.09 * sin(2 * Double.pi * 73.42 * time) * exp(-time / 0.12) : 0
                    layer = 0.58 * tone * envelope + 0.075 * (previousPad * (1 - blend) + pad * blend) + pulse
                case .suspense:
                    let tension = Double(noteIndex + 1) / Double(notes.count)
                    let pulse = pow(sin(Double.pi * progress * Double(noteIndex < 4 ? 1 : 2)), 2)
                    layer = tone * pulse * (0.5 + 0.5 * tension) + 0.12 * sin(phase * 1.5) * envelope * tension
                case .select, .correct, .finish:
                    layer = (tone + 0.12 * sin(phase * 1.5)) * envelope
                case .incorrect:
                    layer = (tone + 0.12 * sin(phase * 1.06)) * envelope
                }
                let amplitude = layer * boundary * 0.45
                samples.append(amplitude)
            }
        }
        samples.forEach { append16(UInt16(bitPattern: Int16($0 * Double(Int16.max)))) }
        return bytes
    }
}

struct SentenceSpeechLine: Equatable {
    let text: String

    static func plan(for question: SentenceQuestion) -> [Self] {
        zip(["A", "B", "C", "D"], question.options).map {
            Self(text: "\($0.0). \($0.1.english)")
        }
    }
}

struct SentenceEnglishVoice: Identifiable, Equatable {
    let id: String
    let name: String

    static func supportsEnglish(_ language: String) -> Bool {
        let normalized = language.replacingOccurrences(of: "_", with: "-").lowercased()
        return normalized == "en" || normalized.hasPrefix("en-")
    }

    static func selected(_ id: String, installed: [Self]) -> Self? {
        installed.first { $0.id == id }
    }
}

struct SentenceNarrationState {
    var enabled = true
    private(set) var generation = UUID()
    private(set) var pending = false
    private(set) var speaking = false

    var shouldAutoRead: Bool { enabled }

    mutating func cancel() {
        generation = UUID()
        pending = false
        speaking = false
    }

    mutating func begin() -> UUID {
        cancel()
        pending = true
        return generation
    }

    @discardableResult
    mutating func started(_ token: UUID) -> Bool {
        guard token == generation, pending else { return false }
        speaking = true
        return true
    }

    @discardableResult
    mutating func finished(_ token: UUID) -> Bool {
        guard token == generation, pending else { return false }
        pending = false
        speaking = false
        return true
    }
}

struct SentenceAudioPolicy {
    var active = false
    var interrupted = false
    var stage = false
    var musicEnabled = true
    var effectsEnabled = true
    var narrating = false
    var permitsMusic: Bool { active && !interrupted && stage && musicEnabled }
    var permitsEffects: Bool { active && !interrupted && effectsEnabled }
    var permitsNarration: Bool { active && !interrupted }
    var musicVolume: Float { permitsMusic ? (narrating ? 0.045 : 0.22) : 0 }
}

#if os(iOS)
import AVFoundation
import Combine

@MainActor
final class SentenceAudio: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var error: String?
    @Published private(set) var narrationError: String?
    @Published private(set) var narration: SentenceNarrationState
    @Published var narratorEnabled = true {
        didSet { narration.enabled = narratorEnabled; if !narratorEnabled { stopNarration() } }
    }
    @Published var englishVoiceID: String { didSet { stopNarration() } }
    let installedEnglishVoices: [SentenceEnglishVoice]
    @Published var musicEnabled = true { didSet { policy.musicEnabled = musicEnabled; updateMusic() } }
    @Published var effectsEnabled = true { didSet { policy.effectsEnabled = effectsEnabled; if !effectsEnabled { effect?.stop() } } }
    private var policy = SentenceAudioPolicy()
    private var music: AVAudioPlayer?
    private var effect: AVAudioPlayer?
    private var observers: [NSObjectProtocol] = []
    private var synthesizer: AVSpeechSynthesizer?
    private var speechGeneration: UUID?
    private var utterances: [AVSpeechUtterance] = []
    private var startup: Task<Void, Never>?
    private var retired: [UUID: AVSpeechSynthesizer] = [:]
    private let waves = Dictionary(uniqueKeysWithValues: SentenceSound.allCases.map { ($0, $0.wave()) })

    init(stage: Bool = false) {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            SentenceEnglishVoice.supportsEnglish($0.language)
        }
        installedEnglishVoices = voices.map { SentenceEnglishVoice(id: $0.identifier, name: $0.name) }
        englishVoiceID = voices.first { $0.language == "en-US" }?.identifier ?? voices.first?.identifier ?? ""
        narration = SentenceNarrationState()
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue == AVAudioSession.InterruptionType.began.rawValue
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.policy.interrupted = began
                self.stopPlayers()
            }
        })
        for name in [AVAudioSession.routeChangeNotification, AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.policy.interrupted = true
                    self?.stopPlayers()
                }
            })
        }
    }

    deinit {
        startup?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func activate(stage: Bool) {
        policy.active = true
        policy.stage = stage
        policy.interrupted = false
        updateMusic()
    }

    func stop() {
        policy.active = false
        stopPlayers()
    }

    private func stopPlayers() {
        stopNarration()
        music?.stop()
        effect?.stop()
        music = nil
        effect = nil
    }

    private func player(_ sound: SentenceSound) throws -> AVAudioPlayer {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try session.setActive(true)
        return try AVAudioPlayer(data: waves[sound]!)
    }

    private func updateMusic() {
        guard policy.permitsMusic else { music?.stop(); music = nil; return }
        guard music == nil else { music?.volume = policy.musicVolume; return }
        do {
            let player = try player(.music)
            player.numberOfLoops = -1
            player.volume = policy.musicVolume
            guard player.play() else { throw SentenceAudioError.playback }
            music = player
            error = nil
        } catch { self.error = "Game audio unavailable: \(error.localizedDescription)" }
    }

    func play(_ sound: SentenceSound) {
        guard policy.permitsEffects, sound != .music else { return }
        effect?.stop()
        do {
            let player = try player(sound)
            player.volume = 0.55
            guard player.play() else { throw SentenceAudioError.playback }
            effect = player
            error = nil
        } catch { self.error = "Game audio unavailable: \(error.localizedDescription)" }
    }

    func stopEffect() { effect?.stop(); effect = nil }

    func readNewQuestion(_ question: SentenceQuestion?) {
        stopNarration()
        if narration.shouldAutoRead, let question { listen(question) }
    }

    func listen(_ question: SentenceQuestion) {
        stopNarration()
        guard narratorEnabled else { return }
        guard policy.permitsNarration else {
            narrationError = "Narrator unavailable: resume audio while the app is active."
            return
        }
        let available = AVSpeechSynthesisVoice.speechVoices()
            .filter { SentenceEnglishVoice.supportsEnglish($0.language) }
            .map { SentenceEnglishVoice(id: $0.identifier, name: $0.name) }
        guard let choice = SentenceEnglishVoice.selected(englishVoiceID, installed: available),
              let voice = AVSpeechSynthesisVoice(identifier: choice.id) else {
            narrationError = "Narrator unavailable: no selected installed English voice."
            return
        }
        let plan = SentenceSpeechLine.plan(for: question)
        let reading = plan.map { line in
            let utterance = AVSpeechUtterance(string: line.text)
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
            return utterance
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            narrationError = "Narrator unavailable: \(error.localizedDescription)"
            return
        }
        stopEffect()
        narrationError = nil
        let token = narration.begin()
        let speaker = AVSpeechSynthesizer()
        speaker.delegate = self
        synthesizer = speaker
        speechGeneration = token
        utterances = reading
        policy.narrating = true
        music?.volume = policy.musicVolume
        startup = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard let self, self.narration.generation == token, self.narration.pending, !self.narration.speaking else { return }
            self.stopNarration()
            self.narrationError = "Narrator unavailable: speech did not start."
        }
        reading.forEach { speaker.speak($0) }
    }

    func stopNarration() {
        narration.cancel()
        startup?.cancel()
        startup = nil
        let old = synthesizer
        synthesizer = nil
        speechGeneration = nil
        utterances = []
        policy.narrating = false
        music?.volume = policy.musicVolume
        if let old {
            let retirement = UUID()
            retired[retirement] = old
            old.stopSpeaking(at: .immediate)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.retired.removeValue(forKey: retirement)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.synthesizer === synthesizer,
                let token = self.speechGeneration, token == self.narration.generation,
                self.utterances.contains(where: { $0 === utterance }) else { return }
            if self.narration.started(token) {
                self.startup?.cancel()
                self.startup = nil
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.synthesizer === synthesizer,
                let token = self.speechGeneration, token == self.narration.generation,
                self.utterances.last === utterance else { return }
            if self.narration.finished(token) { self.stopNarration() }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.synthesizer === synthesizer,
                let token = self.speechGeneration, token == self.narration.generation,
                self.utterances.contains(where: { $0 === utterance }) else { return }
            self.stopNarration()
            self.narrationError = "Narrator stopped before completing the question."
        }
    }
}

private enum SentenceAudioError: LocalizedError {
    case playback
    var errorDescription: String? { "Playback could not start." }
}
#endif