# Vocabulary Widget

A small native iPhone app and Home Screen widget, kept separate from the Unity game. The app lets the learner choose one topic. The widget displays the current word, Vietnamese meaning, abbreviated part of speech, example sentence, and position in the topic. The catalog has five IT/work topics plus the three earlier general topics, with 50 entries per topic. The new-install default is **Giao tiếp công việc**. The lists are curated for learner usefulness and are not a strict frequency ranking or yet linked to the Unity game's vocabulary bank. Progress is stored per topic in an App Group shared defaults suite.

For the product decisions and context carried over from the original ChatGPT conversation, see [`CONVERSATION_HANDOFF.md`](CONVERSATION_HANDOFF.md).

## Open in Xcode

Open `VocabularyWidget.xcodeproj` and run the `VocabularyWidgetApp` scheme on an iPhone simulator or device. In the app, choose a topic; on the Home Screen, add **Từ vựng mỗi ngày** from the widget gallery. The topic list shows the active word and an approximate time until it changes. Long-press a topic row and choose **Bắt đầu lại từ đầu** to reset that topic after confirmation. The medium widget has a **Từ tiếp theo** button; the small widget has an arrow button. Both skip to the next word and restart its five-minute interval. The vocabulary is bundled locally in `Shared/VocabularyData.swift`.

For the repeatable physical-device signing/install workflow, see [the iPhone device build skill](.agents/skills/iphone-device-build/SKILL.md).

For changes driven by user feedback, see [the PM → BA → Dev → DevOps → QC workflow](.agents/skills/feature-feedback-workflow/SKILL.md).

The App Group identifier is currently `group.com.example.VocabularyWidget`; replace it with an App Group registered for your Apple Developer team in both entitlement files and `WidgetProgressStore.swift` before signing for a device. Keep the app and extension identifiers under the same app bundle identifier.

The timeline schedules words five minutes apart in advance. WidgetKit controls actual refresh timing and may display an entry later than its scheduled time, so an exact five-minute cadence cannot be guaranteed by iOS. The app refreshes the widget when the selected topic changes and when the app returns to the foreground.

## Local progress checks

Run `sh Tests/run_progress_checks.sh` to check the catalog entries, five-minute index changes, and per-topic save/resume behavior on macOS.

Run `sh Tests/run_next_word_intent_checks.sh` to exercise the production `NextWordIntent.perform()` on macOS with isolated defaults: first tap, a refreshed tap, five-minute timer restart, wrapping, and stale-topic protection. This is not a Home Screen interaction test.

After an iOS build, run `python3 Tests/check_next_word_intent_metadata.py /path/to/VocabularyWidgetExtension.appex /path/to/VocabularyWidget.swiftconstvalues` using the extension bundle in `Build/Products` and the constants file in its `Build/Intermediates.noindex` objects directory. Keep the intent module-visible (not `private`) to avoid a file-private dispatch identity. This checks extracted action discovery and its required topic/index payload; metadata presence alone does not verify system dispatch. Verify the first visible word change separately on both widget sizes.
