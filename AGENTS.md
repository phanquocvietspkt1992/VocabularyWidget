# Project context

Before making changes, read [`CONVERSATION_HANDOFF.md`](CONVERSATION_HANDOFF.md). It records the product decisions and project history from the original ChatGPT conversation so work can continue in a new Codex thread.

Keep this native iOS vocabulary widget separate from the Unity `WordShooter` project unless the user asks to connect them.

For authorized physical-iPhone builds and installs, follow [the iPhone device build skill](.agents/skills/iphone-device-build/SKILL.md). Verify signing and device access each run; never treat an unsigned compile as an installation.

For user-reported bugs and feature feedback, use [the PM → BA → Dev → DevOps → QC workflow](.agents/skills/feature-feedback-workflow/SKILL.md). Keep the roles sequential; DevOps prepares the iOS Simulator, and QC verifies the actual user path.

## Workflow verification and improvement

### Feedback to apply in future iterations

- Review the affected screen's UX before coding: remove redundant information and spacing, shorten labels, and prioritize essential actions fitting one screen. Do not substitute clipping, unreadably small text, or disabling Dynamic Type for a compact design; retain accessible overflow for genuinely long content.
- Preserve each game's identity. Word Order uses a gentle pastel interface and cheerful, soft audio; Stage/Quick retain their existing Millionaire-style presentation and sounds. Shared helper changes must not leak a new theme or behavior into another mode.
- Respect rejected controls: Word Order uses drag insertion, not visible Left/Right buttons. Keep word-bank slots and position stable while selecting; check before/after states, not just an empty screen.
- Carry approved decisions and rejected approaches through every role handoff. Do not ask the user to repeat settled choices or require them to discover avoidable layout problems after implementation.
- Communicate evidence precisely: distinguish model tests, rendered layout, live gestures, and audible playback. State what remains unverified, and provide the Simulator model and exact route for user testing.

### Verification gates

- DevOps must check compilation separately from Simulator availability. First build `VocabularyWidgetApp` for a generic iOS destination with a fresh DerivedData directory outside the source tree and `CODE_SIGNING_ALLOWED=NO`; capture the complete log and require `BUILD SUCCEEDED`. Then attempt the Simulator build/install/launch. A CoreSimulatorService failure blocks runtime checks but does not replace or erase the generic build result.
- DevOps build logs must exist on disk outside the source tree. Run DevOps with an agent that can write files (not a read-only or output-restricted runner); if a log was not written, the build evidence is incomplete.
- When a build fails, classify the first actionable diagnostic as source, configuration, or toolchain/environment evidence. Do not call a nonzero build successful because source tests pass, and do not attribute Swift compiler/plugin errors to Simulator availability without evidence.
- After QC completes each workflow run, do a brief retrospective. If the run revealed a repeatable process gap, update this project guidance with the smallest reusable correction and validate the changed instructions. Keep one-off environment failures out of standing rules; if no reusable gap was found, leave the guidance unchanged.
- When persistence mutations can reject writes, verify callers restore the effective UI state and report the actual failure. Run queued asynchronous work before asserting that rejected writes have no side effects.
- For topic-scoped counters, test mixed-topic fixtures against the acceptance criteria; activity in one topic must not affect another topic's count.
- For randomized puzzles, assert the player-visible invariant across deterministic seeds and duplicate-token fixtures using the same normalization as scoring; an empty answer or changed token IDs does not prove a scrambled puzzle.
- For layout acceptance, retain the rendering harness, production source hashes, and raw frame measurements outside the repository alongside screenshots. Compare the same seeded question across interaction states; screenshots alone do not prove stable positions or current-source equivalence.
- For bugs that only reproduce on a physical device (audio, App Intents, background execution), capture a persistent device-side log (for example a file in the app container read with `devicectl device copy from`) before changing behavior; base the fix on that evidence.
- Group device logs by `pid` and note how each process was launched (widget intent cold launch, user open, or `devicectl` launch); audio/App Intent behavior differs by launch path, so test widget audio after installing without `devicectl process launch`.
