# PM Handoff: New Medium Widget—5 Examples Display

## Stated Need vs. Problem

**User's Stated Need:**
- Implement a new medium widget to display all 5 examples for a single word

**Observed Problem/Motivation:**
- Current medium widget shows one word with limited context; users want richer example-based learning at a glance
- Users cannot see all examples without opening the app or cycling through the widget

## Who is Affected & Impact

**Primary Users:**
- Vocabulary learners who benefit from seeing multiple contextual uses of a word
- Users who prefer example-driven learning over definitions

**Impact:**
- **Positive:** Expanded widget variety; deeper learning without app launch; faster review
- **Negative/Risk:** Widget families and App Intents code will grow slightly; may create confusion if too many widget options exist

## Smallest Useful Outcome (MVP)

**In Scope:**
- New `systemMedium` widget family: "Word Examples"
- Display a single word with all 5 examples (1 from VocabularyData + 4 from VocabularyExtraExamples)
- Layout: Vertically stacked, numbered (1–5), read-only text
- Tap-to-action: Opens word details in the app (use existing Deep Link or App Intent)
- Minimal header: Topic name + word text (or word text only)
- No buttons, actions, or state mutations

**Out of Scope:**
- Modifications to existing small/medium widgets
- Any interactive elements (next, mark-learned, etc.)
- New accessory widget families
- Pagination or example filtering

## Open Questions (Materially Affect Behavior)

1. **Header/Context:** Should the widget header show topic name + word text, or just word text? (affects visual balance and quick recognition)

2. **Sparse Data Handling:** If a word has fewer than 5 examples (e.g., 3), should the widget display all 3, show empty slots, or pad with a message? (affects consistency and perceived completeness)

3. **Coexistence:** Should users be able to choose between the current medium widget and the new examples widget, or should both be offered as separate family options? (affects widget gallery UX and user decision complexity)

4. **Widget Cycle/Lock:** Can users lock/pin the examples widget, or is it part of the normal Smart Stack rotation? (affects how frequently they see it vs. other widgets)

5. **Word Content:** Should the header also show part of speech and/or meaning, or keep it minimal (examples only)? (affects layout, readability, and learn value)

---

## Recommendation for BA

Request design clarification on questions 1–5 before implementation. The MVP is self-contained and does not require changes to existing widget code paths, reducing regression risk.
