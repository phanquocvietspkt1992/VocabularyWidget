# Conversation handoff: Vocabulary Widget

This file carries the important product decisions and implementation context from the original ChatGPT conversation into future Codex project threads. It is a concise handoff, not a verbatim transcript. The original chat remains in ChatGPT history; Codex chat history is separate according to [OpenAI's ChatGPT Work and Codex guide](https://help.openai.com/en/articles/20001275-chatgpt-work-and-codex).

## Product goal

Build a simple native iPhone app with a Home Screen widget that helps the user learn English vocabulary.

## Decisions from the user

- The learner chooses a vocabulary topic.
- The user's stated learning goal is English for IT work: communicating with coworkers and colleagues, participating in meetings, and discussing work. Keep examples useful for day-to-day software/IT teams without assuming the user's exact IT role.
- Stay on one topic until the learner explicitly changes the selection.
- Remember the learner's current position in each topic's word list.
- Show one word at a time on the widget, with the word, Vietnamese meaning, part of speech, and an example sentence.
- Abbreviate parts of speech as `(n)`, `(v)`, `(adj)`, etc.
- The learner edits the active start/end times and interval in Study Schedule. Defaults are 07:30–23:30, every five minutes; the start is inclusive, the end exclusive, and a later start crosses midnight. Only active-window seconds accumulate, with unfinished intervals carried to the next window. iOS WidgetKit controls actual display timing, so exact refreshes cannot be guaranteed.
- The initial version should stay simple.
- Vocabulary should emphasize common, widely used words. The three original topics still contain 50 words each. Five IT/work topics were added, also with 50 words each: Work Communication, Meetings & Collaboration, Software Development, IT Project Management, and IT Support & Troubleshooting. New installs default to Work Communication. Existing topic IDs and vocabulary data remain so saved progress stays available.
- The user asked whether account-wide ChatGPT history could be consulted for personalization. No history-search tool was available in that session, so only details explicitly present in the current conversation were used. Do not imply access to other chats unless a connected history source is available.
- The app title and app-authored UI labels are in English. Built-in topic display names are English; preserve Vietnamese vocabulary meanings, stable topic IDs, saved progress, and user-authored custom topic names.
- Keep the iOS vocabulary project in its own `VocabularyWidget` folder, separate from the Unity game.
- The user previously approved building and testing with Xcode and the iPhone Simulator, and manually confirmed that the app and widget looked okay in the Simulator.
- The user's iPhone and MacBook are connected over Wi-Fi for device testing. Prefer the existing wireless pairing; verify `devicectl` availability each run instead of assuming USB is required.

## Current implementation

- Native SwiftUI app and WidgetKit extension in `VocabularyWidget.xcodeproj`.
- Topics currently bundled in `Shared/VocabularyData.swift`: five IT/work topics and the three original general topics, 50 entries each.
- Progress is stored per topic using the shared App Group defaults in `Shared/WidgetProgressStore.swift`.
- The app lets the user select a topic, displays its current word and an approximate time-to-change, and offers a confirmed reset for each topic.
- The widget has a **Next word** action and a **Mark as learned** action. Marking studied records the topic, displayed word text, local day, and tap time in versioned App Group defaults history; it advances and re-anchors the configured interval. History is deduplicated per topic/word/local day and is not removed by progress reset. The widget timeline uses the same active-window tick function as notifications, subject to iOS refresh behavior.
- Bundle ID `com.phanquocviet.VocabularyWidget` (+ `.WidgetKit`), App Group `group.com.phanquocviet.VocabularyWidget`, team `PD2729ZJNT`; installed and launched on the user's iPhone on 2026-10-31.

- Optional local notifications request alert/sound authorization when enabled. Up to 64 future ticks are scheduled with the word, part of speech, Vietnamese meaning, topic and examples. Notifications replenish on launch/foreground, schedule/topic/custom-vocabulary/reset changes, and successful widget Next word/Mark as learned actions. No BGAppRefreshTask is registered: reminders stop when the pending horizon is exhausted until one of those replenishment paths runs.
- Notification request identifiers are deterministic per tick so overlapping host/extension reschedules replace the same reminder. Only obsolete app-prefixed requests are removed; the app retains a notification delegate to present banners, lists and sound while foreground. Cadence reads never persist fallback anchors; explicit app initialization and progress/settings mutations own anchor writes. DST boundaries use the first repeated start and last repeated end, counting actual elapsed active seconds.
- Accepted limitations (QC cycle 2, user rejected lock-based redesigns): (1) in time zones with DST, a window that overlaps the repeated fall-back hour is treated as one continuous span, so ticks/notifications can be miscounted that night; Vietnam has no DST. (2) If the app and the widget extension reschedule at the same moment with different settings, both plans can be added and obsolete ticks may remain pending until the next reschedule (app open/foreground, settings/topic change, Next/Studied).
- Notification audio is rendered only for pending words via the shared pronunciation voice/rate policy, cached as stable CAF filenames in the App Group’s Library/Sounds. The extension uses completed cached files only; render failures or unavailable files use the default sound. Actual delivery/audio still needs device verification.
- Built-in extra examples come from `Shared/VocabularyExtraExamples.swift` (topic ID → word text → four extra examples). The catalog keeps each original first example and appends extras; custom words keep their five user-entered examples.

## Verification and limits previously observed

- The progress-check script is `sh Tests/run_progress_checks.sh`; the latest run after adding the IT topics passed 1,149 checks.
- An Xcode Release build for `iphoneos` / arm64 succeeded with code signing disabled after the IT topics were added.
- Command-line Simulator control was unavailable in the prior environment because CoreSimulatorService could not be reached. The user manually launched the app and added the widget in Simulator, then said it looked okay.
- Recheck the current code and run relevant checks before relying on these historical results.

## Product discussion to continue

The user wants common, popular vocabulary. The current expansion is a practical curation, not an exact frequency ranking. For future additions, prioritize topic relevance, common real-life use, and learner usefulness. Oxford describes its Oxford 3000 selection as corpus-informed and prioritizing both frequency and usefulness; use that as a selection principle, not as a claim that this app's entries are ranked or copied from that list ([Oxford 3000 methodology](https://www.oxfordlearnersdictionaries.com/about/oxford3000)).

## Workflow preference

The user wants an iterative product workflow: user feedback → analyst → developer → QA → user review. Keep each change small, explain what changed and how it was verified, and invite the user to evaluate the result before starting another iteration.
