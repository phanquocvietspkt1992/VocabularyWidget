import Foundation

@main
struct PronunciationChecks {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            count += 1
        }
        check(PronunciationPolicy.speechText("") == nil, "empty words do not speak")
        check(PronunciationPolicy.speechText(" \n\t\r") == nil, "whitespace words do not speak")
        check(PronunciationPolicy.speechText("\u{00A0}\u{2003}") == nil, "Unicode whitespace does not speak")
        check(PronunciationPolicy.speechText("  deployment\n") == "deployment", "trim only boundary whitespace")
        check(PronunciationPolicy.speechText("pull request") == "pull request", "preserve multiword vocabulary")
        check(PronunciationPolicy.speechText("CI/CD") == "CI/CD", "preserve exact word punctuation and case")
        check(PronunciationPolicy.preferredVoiceIndex(languages: []) == nil, "no voices")
        check(PronunciationPolicy.preferredVoiceIndex(languages: ["vi-VN", "fr-FR"]) == nil, "do not select non-English voice")
        check(PronunciationPolicy.preferredVoiceIndex(languages: ["en-GB", "en-US", "en-AU"]) == 1, "prefer US English")
        check(PronunciationPolicy.preferredVoiceIndex(languages: ["vi-VN", "en-AU", "en-GB"]) == 1, "fall back to available English")
        check(PronunciationPolicy.preferredVoiceIndex(languages: ["en"]) == 0, "accept generic English")
        check(PronunciationPolicy.preferredVoiceIndex(languages: ["en-GB", "EN_us"]) == 1, "normalize language identifiers")
        check(PronunciationPolicy.preferredVoiceIndex(languages: ["eng", "english"]) == nil, "match English language boundaries")
        check(PronunciationPolicy.preferredVoiceIndex(languages: ["en-US", "en-US"]) == 0, "choose one voice deterministically")
        check(abs(PronunciationPolicy.speechRate(defaultRate: 0.5) - 0.45) < 0.00001, "use default speech rate times 0.9")
        check(PronunciationAudioSessionPolicy.category == .playback, "playback remains audible in silent mode")
        check(PronunciationAudioSessionPolicy.mode == .spokenAudio, "use spoken-audio mode")
        check(PronunciationAudioSessionPolicy.options == [.mixWithOthers], "mix with other audio without ducking")
        check(PronunciationAudioSessionPolicy.renderTimeoutNanoseconds == 5_000_000_000, "speech rendering is bounded to five seconds")
        check(PronunciationAudioSessionPolicy.playbackTimeoutNanoseconds == 30_000_000_000, "buffer playback is bounded to thirty seconds")
        check(PronunciationAudioSessionPolicy.activationRetryDelayNanoseconds == 150_000_000, "audio activation retry waits 150 ms")
        check(PronunciationAudioSessionPolicy.debounceNanoseconds == 300_000_000, "same-word debounce is 300 ms")
        check(PronunciationAudioSessionPolicy.shouldRetryActivation(errorCode: 561_015_905, attempt: 0), "retry cannotStartPlaying once")
        check(!PronunciationAudioSessionPolicy.shouldRetryActivation(errorCode: 561_015_905, attempt: 1), "do not retry activation more than once")
        check(!PronunciationAudioSessionPolicy.shouldRetryActivation(errorCode: 561_015_905, attempt: 2), "no further activation attempts")
        check(!PronunciationAudioSessionPolicy.shouldRetryActivation(errorCode: 561_015_905, attempt: -1), "only initial activation is retryable")
        check(!PronunciationAudioSessionPolicy.shouldRetryActivation(errorCode: -1, attempt: 0), "do not retry other activation errors")
        check(PronunciationAudioSessionPolicy.shouldDebounce(existingWord: "deploy", incomingWord: "deploy", elapsedNanoseconds: 0), "debounce same word immediately")
        check(PronunciationAudioSessionPolicy.shouldDebounce(existingWord: "deploy", incomingWord: "deploy", elapsedNanoseconds: 299_999_999), "debounce same word below 300 ms")
        check(!PronunciationAudioSessionPolicy.shouldDebounce(existingWord: "deploy", incomingWord: "deploy", elapsedNanoseconds: 300_000_000), "allow same word at 300 ms")
        check(!PronunciationAudioSessionPolicy.shouldDebounce(existingWord: "deploy", incomingWord: "release", elapsedNanoseconds: 1), "different word replaces immediately")
        for completion in PronunciationAudioSessionPolicy.Completion.allCases {
            check(!PronunciationAudioSessionPolicy.shouldDeactivate(after: completion),
                  "never deactivate after completion: \(completion)")
            var ownership = PronunciationAudioSessionPolicy.Ownership()
            check(!ownership.complete(completion), "no session ownership before activation: \(completion)")
            ownership.begin()
            check(!ownership.complete(completion), "completion keeps process session active: \(completion)")
            check(ownership.isOwned, "session ownership survives completion: \(completion)")
            check(!ownership.complete(completion), "completion never deactivates twice: \(completion)")
        }
        for terminal in PronunciationAudioSessionPolicy.Completion.allCases where terminal != .replacement {
            var ownership = PronunciationAudioSessionPolicy.Ownership()
            ownership.begin()
            for _ in 0..<3 {
                check(!ownership.complete(.replacement), "rapid replacement must not deactivate")
                check(ownership.isOwned, "rapid replacement keeps session ownership")
                ownership.begin()
            }
            check(!ownership.complete(terminal), "replacement followed by completion keeps session active: \(terminal)")
            check(ownership.isOwned, "replacement completion keeps session ownership: \(terminal)")
            ownership.reset()
            check(!ownership.isOwned, "interruption/reset can clear active session ownership: \(terminal)")
            check(!ownership.complete(terminal), "reset ownership cannot deactivate: \(terminal)")
        }
        print("Pronunciation checks passed (\(count) checks).")
    }
}
