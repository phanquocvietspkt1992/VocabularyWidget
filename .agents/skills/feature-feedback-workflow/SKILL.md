---
name: feature-feedback-workflow
description: "Coordinate PM, BA, Dev, DevOps, and QC for feature requests or reported behavior issues in VocabularyWidget using concise handoffs and focused evidence."
---

# Vocabulary Feedback Workflow

Coordinate the role agents in [`.github/agents/`](../../../.github/agents/). Their individual files own role instructions and tool permissions; this skill owns routing, handoffs, and completion gates. Read only the role files needed for the current task.

## Route by task

- **Question or brainstorming only:** answer directly; do not start the implementation workflow.
- **Bug report or feature feedback:** run PM → BA → Dev → DevOps → QC in order, as required by repository policy. For explicit requests, PM and BA should make concise confirmations without reopening settled decisions; keep every gate, not repeated prose.
- **PM:** separate facts from assumptions; state minimum outcome, non-goals, and only material questions.
- **BA:** translate the PM handoff into at most seven testable Given/When/Then criteria and label automated versus runtime checks.
- **Dev:** load [`vocabulary-dev`](../../../.github/skills/vocabulary-dev/SKILL.md), implement the approved scope, and run the cheapest behavior check immediately after the first edit.
- **DevOps:** for iOS changes, build generic iOS first, then prepare Simulator. If user acceptance includes physical installation, use the separate `iphone-device-build` skill only when requested.
- **QC:** independently challenge each criterion using focused checks and the actual user path. Mark inaccessible UI/device criteria `BLOCKED` or `UNVERIFIED`; never infer them from compilation or app launch.

## Complexity, impact, and model routing

- The coordinator records **effort** and **risk/impact** separately. Use `small / medium / large / unknown` for estimated effort and `low / medium / high / unknown` for risk; a small edit can still be high-risk when it affects persistence, shared app/extension state, concurrency, audio/App Intents, or irreversible user-visible behavior.
- Build an evidence-backed impact map incrementally: relevant paths/symbols, callers, stored state, app/extension targets, and user paths. Label entries `suspected`, `confirmed`, or `ruled out`; include evidence and confidence. Keep the map narrow and expand only when a nearby check or dependency requires it.
- Role ownership: PM describes user impact and criticality, not code impact; BA maps acceptance criteria to likely behaviors and technical surfaces; Dev confirms actual code/caller/data/target impact; DevOps selects required build and runtime surfaces from that map; QC independently challenges the map and checks direct behavior plus material adjacent regressions.
- The coordinator chooses the model/capability **before** invoking each role, using models actually available in the host. Prefer an efficient model for clear low-risk framing and routine work, a balanced model for multi-path changes, and the strongest available reasoning/coding model for high-risk implementation and QC. For high-impact work, use an independent QC model when available and worth the extra cost. Keep PM/BA on efficient models unless product ambiguity demands more reasoning.
- Do not hard-code model names in role instructions or imply a model switch occurred when the host does not expose that control. If selection is unavailable, state the limitation and use the active model. Save tokens with narrow context, concise handoffs, and risk-based focused checks; never skip required build/deployment gates or acceptance criteria to save tokens.

## Autonomy and learning

- When the user explicitly requests implementation or approves a defined outcome, the coordinator owns the sequential workflow through QC. Proceed with routine, scoped edits and focused checks without asking for repeated permission; ask only when a material product decision is unresolved or a required acceptance check is blocked.
- Work iteratively and evidence-first: state a falsifiable hypothesis and cheapest check, make a small reversible change, and use the focused result to guide the next step. If it fails, repair that slice and rerun the same check; do not repeat a failed approach without new evidence.
- Preserve existing user changes and data. Stop for explicit authorization before expanding scope, destructive or irreversible actions, touching real user data, physical-device installation/deployment, signing, committing, pushing, or changing branches. Do not request or expose secrets.
- After QC, evaluate the complete run from the role reports and evidence. Separate product defects, workflow gaps, and environment/tool blockers; summarize rework, duplicated effort, and handoff loss when observed. Add only the smallest reusable workflow correction after a repeatable gap is demonstrated, report that change, and leave broader workflow redesign to the user.
- This autonomy applies while handling an authorized request; it does not mean background work continues after the session or task ends.

## Handoff packet

Pass forward a compact packet, not the conversation transcript:

For every run, preserve each role's concise audit record: input/handoff received, work performed and evidence checked, bugs/risks/blockers found (or explicitly not assessed), and the key handoff sent onward. The coordinator must pass the actual decision, evidence, unresolved issue, and any changed acceptance criterion to the next role. Do not imply direct agent-to-agent conversation beyond these coordinator-mediated packets.

```text
User outcome / non-goals:
Effort / risk (separate estimates):
Acceptance criteria:
Impact map (suspected / confirmed / ruled out, with evidence):
Relevant paths and verified facts:
Existing changes or constraints:
Cheapest focused check:
Model capability selected / availability:
Unresolved risks:
```

Include only applicable fields. Keep packets to the information the next role needs; cite paths/symbols and exact observed errors instead of copying source or prior reports. Each role returns only its required result, evidence, and blocker (PM ≤120 words, BA ≤180, Dev ≤180, DevOps ≤150, QC ≤180). Role agents must use the packet and inspect only the nearest owning code/test; do not reload this full workflow, the conversation handoff, or prior transcripts unless a required fact is missing. Do not have roles re-read unrelated files or rerun already-passing suites without a reason.

## Execution and gates

1. **Orient:** check `git status`, read `AGENTS.md` and `CONVERSATION_HANDOFF.md`, then inspect the nearest owning code and one relevant test. Preserve user changes.
2. **PM → BA:** identify the user-visible outcome, persisted state, failure cases, and how each criterion can be observed. Ask the user only for decisions that cannot be inferred safely; explicit decisions are inherited, not asked again.
3. **Dev:** state one falsifiable local hypothesis and cheapest check before editing. Make the smallest change. Immediately run that check after the first edit; fix and rerun the same slice before broadening.
4. **DevOps:** first build `VocabularyWidgetApp` for `generic/platform=iOS` with fresh DerivedData outside the repository and `CODE_SIGNING_ALLOWED=NO`. Save the complete log and require exit 0 plus `BUILD SUCCEEDED`. Then build/install/launch an available iPhone Simulator in place without erasing or uninstalling. Report compile and Simulator availability separately.
5. **QC:** inspect the current diff independently, execute only relevant checks, and test the user path rather than relying on compilation. Report `PASS`, `FAIL`, or `BLOCKED` per surface. Source tests, Simulator interaction, and physical-device behavior are separate evidence levels.
6. **Close:** report changed paths, exact focused checks, build/runtime outcomes, unresolved acceptance criteria, and whether user data or Git state changed. Include the per-run report below. Do not commit, push, change branches, or physically deploy without explicit authorization.

For persistence mutations, assert exact rollback/readback behavior and actual caller feedback; drain queued asynchronous work before asserting no side effects. For topic-scoped counters, include mixed-topic fixtures. For device-only audio/App Intent/background bugs, preserve a device-side log before changes and group it by PID and launch path. Use isolated defaults in tests; never use the live App Group as a test fixture.

## Evidence discipline

- Keep full build logs outside the source tree. Classify the first actionable build failure as source, configuration, or environment; other tests do not turn a failed build into a pass.
- Use short command output during exploration; retain full logs as files and cite the relevant lines/errors in handoffs.
- Never call a deep-link dispatch, prompt, compile, or app launch an interaction pass unless the expected UI/result was actually observed.
- If a required interface is unavailable, state the exact blocker and leave that criterion `UNVERIFIED`; do not simulate evidence.
- Run a brief retrospective after QC. Add a reusable instruction only when a repeatable gap is demonstrated; do not encode one-off environment failures.

## Per-run report

After every feature/bug workflow, include a concise report in the final response; do not create a repository report file unless the user asks. Cover all five roles (PM, BA, Dev, DevOps, QC), including the input each received, actual work/evidence, issues found, and the key outgoing handoff. For the communication trail, summarize only coordinator-mediated handoffs and substantive decision/criteria changes; never invent exchanges or expose private chain-of-thought.

Close with the workflow result: defects found or introduced (distinguish product defects from process gaps and environment/tool blockers), acceptance status, where rework/duplication or handoff loss occurred, and one evidence-backed improvement for the next run. Say "none observed in checked scope" or "not assessed" as appropriate; do not convert missing evidence into a clean bill of health or score an agent from a single run. Keep suggested process changes separate from confirmed changes, and update standing instructions only for a demonstrated repeatable gap.

## Role agents

- [Vocabulary PM](../../../.github/agents/pm.agent.md)
- [Vocabulary BA](../../../.github/agents/ba.agent.md)
- [Vocabulary Dev](../../../.github/agents/dev.agent.md)
- [Vocabulary DevOps](../../../.github/agents/devops.agent.md)
- [Vocabulary QC](../../../.github/agents/qc.agent.md)

## References

- [VS Code custom agents](https://code.visualstudio.com/docs/agent-customization/custom-agents): role-specific instructions/tools and handoffs.
- [VS Code Agent Skills](https://code.visualstudio.com/docs/agent-customization/agent-skills): skills are loaded on demand, with reference/resources loaded as needed.
- [Anthropic: Building effective agents](https://www.anthropic.com/engineering/building-effective-agents): start with simple workflows and add agent complexity only when it improves results; use separate stages when subtasks are well-defined.
- [OpenAI: Prompt engineering](https://developers.openai.com/api/docs/guides/prompt-engineering): clear role/task boundaries, structured context, and concise, relevant inputs.
