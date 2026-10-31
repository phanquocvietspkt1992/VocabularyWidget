---
name: feature-feedback-workflow
description: "Turn user feedback or a reported app bug into a scoped product change using four distinct PM, BA, Dev, and QC agents with explicit handoffs. Use for feature requests, UX changes, or bugs in VocabularyWidget."
---

# PM → BA → Dev → DevOps → QC workflow

Use five role agents: **PM, BA, Dev, DevOps, QC**. The root Codex agent coordinates handoffs and reports to the user; it is not a role. Run the roles in order because each stage depends on the previous one. Do not have agents edit the same app files concurrently.

## 1. PM — understand the user problem

Give the PM agent the user's feedback and enough project context to reason about the actual product. Ask it to return:

- The user's stated need and observed problem, separated from assumptions.
- Who is affected, impact, and likely frequency, based only on evidence available.
- The smallest useful outcome and out-of-scope changes.
- Open questions that materially affect behavior. Ask the user only when a decision cannot be inferred; continue independent work meanwhile.

The PM does not edit code or redefine an explicit user preference.

## 2. BA — make it testable

Pass the PM handoff to the BA agent. Ask it to inspect relevant product behavior and write concise acceptance criteria in Given/When/Then form, including:

- The normal path and meaningful edge cases.
- Persisted state and interactions with topic selection, saved progress, and the five-minute cadence when relevant.
- Which checks can be automated and which require an actual iPhone/widget interaction.

The BA does not edit app code. If the user's desired behavior is already clear, do not delay implementation for unnecessary approval.

## 3. Dev — implement the approved behavior

Pass the PM problem statement and BA criteria to the Dev agent. Have it inspect the current implementation, identify a plausible root cause before changing code, make the smallest focused fix, and report:

- Root cause evidence, files changed, and implementation summary.
- Tests/builds run and their exact results.
- Any acceptance criterion it could not verify.

The Dev owns source changes. It may add/update focused tests when they cover a real regression risk. Do not change signing, bundle IDs, App Groups, or unrelated product behavior for a UI bug.

## 4. DevOps — build and prepare the iOS Simulator

Pass the Dev handoff and BA criteria to the DevOps agent. Its scope is build and runtime preparation, not product-code fixes or acceptance decisions:

- Check Xcode scheme and available iOS Simulator devices; select an available iPhone simulator.
- Build the `VocabularyWidgetApp` scheme for that simulator using a fresh DerivedData directory outside the source tree and `CODE_SIGNING_ALLOWED=NO`.
- Require a successful build, then install and launch the app on the selected simulator. Record the simulator name/UDID, build command, and artifact/log paths.
- Confirm the widget extension is embedded in the built host app. Do not claim the widget is on the Home Screen unless it was actually added.
- If CoreSimulatorService is unavailable, report **BLOCKED** with the exact command/error. Do not switch to a physical-device signing flow or alter bundle IDs/App Groups as a workaround.

For the native widget, booting and launching the host app alone does not verify the Home Screen button. If adding the widget requires UI interaction unavailable to the agent, hand the ready simulator state to QC and state that limitation.

## 5. QC — independently challenge the result

Pass the acceptance criteria, Dev handoff, and DevOps simulator/build report to a fresh QC agent. QC reviews the diff and runs relevant existing checks independently. It must test the user's reported path, not merely check that the project compiles or launches.

For widget interactions, verify the actual AppIntent/button path, visible word change, per-topic saved index, and timer restart. Cover small and medium widget variants when they expose the action. Simulator/source-level checks are not evidence of physical-iPhone behavior; report each verification surface separately. If the phone or simulator is unavailable, mark that criterion **unverified**, not passed.

QC returns **PASS**, **FAIL** with a reproduction, or **BLOCKED** with the exact missing environment. QC is read-only; a product-behavior failure returns to Dev for a fix, a build/deployment failure returns to DevOps, and QC reruns the failed criteria after the responsible role reports a fix.

## Exit gate and user review

The coordinator may call the change ready only when all acceptance criteria pass, or when remaining unverified criteria are clearly identified and the user explicitly accepts that limitation. Summarize the user problem, what changed, test/build evidence, simulator/device coverage, and any remaining check. Then let the user evaluate the result before starting a new iteration.

## Handoff format

Each role returns only its role's findings in this format:

```text
Role:
Findings:
Decision / handoff:
Open risks:
```
