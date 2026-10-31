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
- The intended interval is five minutes. iOS WidgetKit controls actual refresh timing, so exact five-minute refreshes cannot be guaranteed.
- The initial version should stay simple.
- Vocabulary should emphasize common, widely used words. The three original topics still contain 50 words each. Five IT/work topics were added, also with 50 words each: Giao tiếp công việc, Họp và phối hợp, Phát triển phần mềm, Quản lý dự án IT, and Hỗ trợ và xử lý sự cố. New installs default to Giao tiếp công việc. Existing topic IDs and data remain so saved progress stays available.
- The user asked whether account-wide ChatGPT history could be consulted for personalization. No history-search tool was available in that session, so only details explicitly present in the current conversation were used. Do not imply access to other chats unless a connected history source is available.
- Keep the iOS vocabulary project in its own `VocabularyWidget` folder, separate from the Unity game.
- The user previously approved building and testing with Xcode and the iPhone Simulator, and manually confirmed that the app and widget looked okay in the Simulator.

## Current implementation

- Native SwiftUI app and WidgetKit extension in `VocabularyWidget.xcodeproj`.
- Topics currently bundled in `Shared/VocabularyData.swift`: five IT/work topics and the three original general topics, 50 entries each.
- Progress is stored per topic using the shared App Group defaults in `Shared/WidgetProgressStore.swift`.
- The app lets the user select a topic, displays its current word and an approximate time-to-change, and offers a confirmed reset for each topic.
- The widget has a next-word action. The widget timeline is scheduled five minutes apart, subject to iOS refresh behavior.
- App Group identifier is still the placeholder `group.com.example.VocabularyWidget`; it must be replaced with an identifier registered for the user's Apple Developer team before signing for a physical device.

## Verification and limits previously observed

- The progress-check script is `sh Tests/run_progress_checks.sh`; the latest run after adding the IT topics passed 1,149 checks.
- An Xcode Release build for `iphoneos` / arm64 succeeded with code signing disabled after the IT topics were added.
- Command-line Simulator control was unavailable in the prior environment because CoreSimulatorService could not be reached. The user manually launched the app and added the widget in Simulator, then said it looked okay.
- Recheck the current code and run relevant checks before relying on these historical results.

## Product discussion to continue

The user wants common, popular vocabulary. The current expansion is a practical curation, not an exact frequency ranking. For future additions, prioritize topic relevance, common real-life use, and learner usefulness. Oxford describes its Oxford 3000 selection as corpus-informed and prioritizing both frequency and usefulness; use that as a selection principle, not as a claim that this app's entries are ranked or copied from that list ([Oxford 3000 methodology](https://www.oxfordlearnersdictionaries.com/about/oxford3000)).

## Workflow preference

The user wants an iterative product workflow: user feedback → analyst → developer → QA → user review. Keep each change small, explain what changed and how it was verified, and invite the user to evaluate the result before starting another iteration.
