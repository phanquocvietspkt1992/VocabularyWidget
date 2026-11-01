---
name: vocabulary-dev
description: "Implement approved SwiftUI, WidgetKit, persistence, or App Intent changes in VocabularyWidget and run the narrowest relevant regression checks. Use for Dev-stage feature work or bug fixes after scope and acceptance criteria are defined."
---

# Vocabulary Dev

Use this skill only for the implementation stage after the coordinator supplies the approved outcome and acceptance criteria. PM owns product scope; BA owns acceptance criteria; Dev owns source edits and focused automated checks. Do not start a new feature, deployment, commit, push, or physical-device action from this skill.

## Required engineering capabilities

- Swift and SwiftUI for the iOS 17+ host app; WidgetKit and App Intents for the extension and widget actions.
- AVFoundation/AVAudioSession for pronunciation, including lifecycle, interruption, route changes, cancellation, and host-versus-extension API availability.
- UserDefaults/App Group and Codable persistence, with isolated test suites, validation, readback, rollback, and preservation of existing user data.
- Xcode project target membership, signing/version boundaries, and distinguishing compile evidence from Simulator/device runtime evidence.

Apply senior-level behaviors rather than relying on a seniority label: trace the owning path before editing, state a falsifiable root-cause hypothesis, choose the cheapest disconfirming check, make the smallest safe change, and verify failure paths as well as success paths. Do not claim physical/runtime expertise from mocks or source inspection alone.

## Orient narrowly

1. Read the applicable root `AGENTS.md` and `CONVERSATION_HANDOFF.md` when starting a task; preserve the current branch and all dirty/untracked user files.
2. Inspect only the owning implementation, its nearest caller, and the most relevant existing test. Use broader searches only when those sources leave a concrete question unresolved.
3. Before editing, state one falsifiable local hypothesis, the controlling path, the cheapest disconfirming check, and the smallest proposed change.

## Implement and verify

1. Reuse existing APIs and test helpers. Prefer one focused patch; do not refactor neighboring code or add abstractions/files without a clear need.
2. After the first substantive edit, immediately run the stated focused check before more reading or editing. If it fails, repair that slice and rerun the same check.
3. Select only relevant repository checks:
   - `sh Tests/run_progress_checks.sh` for topics, custom vocabulary, progress, history, backup/review state, or App Group persistence.
   - `sh Tests/run_schedule_checks.sh` for schedule, anchors, active windows, or notification cadence.
   - `sh Tests/run_next_word_intent_checks.sh` for widget Next/Studied App Intent behavior.
   - `sh Tests/run_pronunciation_checks.sh` for pronunciation policy, rendering/playback lifecycle, cancellation, or audio-session behavior.
4. If a changed Swift file is explicitly listed in `VocabularyWidget.xcodeproj/project.pbxproj`, verify it is added to the correct app, extension, or both target Sources phases. DevOps owns required generic/Simulator builds and their external logs.
5. For persistence, use `WidgetProgressStore.testDefaults` or another isolated suite. Never seed tests in the live App Group. Validate rejected writes, rollback/readback and caller-visible errors when touched; drain queued async work before asserting no side effects.
6. Use `apply_patch` for manual edits. Keep comments, docs and tests limited to material behavior and regression risk. Do not change bundle IDs, App Groups, signing, or deployment versions unless explicitly authorized.

## Handoff

Return only:

```text
Root cause / evidence:
Files and behavior changed:
Focused checks and exact results:
Unverified acceptance:
DevOps handoff:
```

Keep the report concise. Distinguish observed runtime behavior from source-level or mocked evidence. Never claim a build, UI path, widget action, or audible result that was not actually verified.
