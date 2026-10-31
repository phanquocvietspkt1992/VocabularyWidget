# Project context

Before making changes, read [`CONVERSATION_HANDOFF.md`](CONVERSATION_HANDOFF.md). It records the product decisions and project history from the original ChatGPT conversation so work can continue in a new Codex thread.

Keep this native iOS vocabulary widget separate from the Unity `WordShooter` project unless the user asks to connect them.

For authorized physical-iPhone builds and installs, follow [the iPhone device build skill](.agents/skills/iphone-device-build/SKILL.md). Verify signing and device access each run; never treat an unsigned compile as an installation.

For user-reported bugs and feature feedback, use [the PM → BA → Dev → DevOps → QC workflow](.agents/skills/feature-feedback-workflow/SKILL.md). Keep the roles sequential; DevOps prepares the iOS Simulator, and QC verifies the actual user path.

## Workflow verification and improvement

- DevOps must check compilation separately from Simulator availability. First build `VocabularyWidgetApp` for a generic iOS destination with a fresh DerivedData directory outside the source tree and `CODE_SIGNING_ALLOWED=NO`; capture the complete log and require `BUILD SUCCEEDED`. Then attempt the Simulator build/install/launch. A CoreSimulatorService failure blocks runtime checks but does not replace or erase the generic build result.
- DevOps build logs must exist on disk outside the source tree. Run DevOps with an agent that can write files (not a read-only or output-restricted runner); if a log was not written, the build evidence is incomplete.
- When a build fails, classify the first actionable diagnostic as source, configuration, or toolchain/environment evidence. Do not call a nonzero build successful because source tests pass, and do not attribute Swift compiler/plugin errors to Simulator availability without evidence.
- After QC completes each workflow run, do a brief retrospective. If the run revealed a repeatable process gap, update this project guidance with the smallest reusable correction and validate the changed instructions. Keep one-off environment failures out of standing rules; if no reusable gap was found, leave the guidance unchanged.
- For bugs that only reproduce on a physical device (audio, App Intents, background execution), capture a persistent device-side log (for example a file in the app container read with `devicectl device copy from`) before changing behavior; base the fix on that evidence.
