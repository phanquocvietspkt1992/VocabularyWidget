# Acceptance Criteria: Medium Widget - Examples View

## Feature Summary
A new medium-sized widget that displays all 5 numbered examples for a selected word, providing read-only access to example content with navigation to the full word detail view.

---

## 1. NORMAL PATH: Display All 5 Examples

### Scenario: Widget displays complete examples list
```gherkin
Feature: Medium Widget Examples Display
  Scenario: Display all 5 examples for a word with full data
    Given a word is selected with exactly 5 examples
    And the medium widget is added to Home Screen
    When the widget loads
    Then the widget displays:
      | Element | Expected Content |
      | Topic Name | Uppercase word topic |
      | Word Text | The selected word |
      | Part of Speech + Meaning | Word POS and definition |
      | Example 1 | "1. " + first example text |
      | Example 2 | "2. " + second example text |
      | Example 3 | "3. " + third example text |
      | Example 4 | "4. " + fourth example text |
      | Example 5 | "5. " + fifth example text |
    And examples are vertically stacked
    And dark blue gradient background is visible
    And light blue accents highlight the examples
    
  Scenario: Styling consistency with existing widgets
    Given the examples widget is displayed
    When I compare visual styling to action widgets
    Then the color scheme matches (dark blue gradient + light blue accents)
    And font sizes are readable in medium widget space
    And spacing between examples allows comfortable reading
```

---

## 2. EDGE CASES: Handling Incomplete/Missing Data

### Scenario A: Word with fewer than 5 examples
```gherkin
  Scenario: Display fewer than 5 examples gracefully
    Given a word is selected with only 3 examples
    When the examples widget loads
    Then the widget displays:
      | 1. first example |
      | 2. second example |
      | 3. third example |
    And no placeholder/empty slots appear for missing examples
    And the layout adjusts vertically without excess whitespace
    And the widget remains fully tappable

  Scenario: Word with 0 examples
    Given a word is selected with no examples
    When the examples widget loads
    Then the widget displays an empty state message
    And the message indicates "No examples available"
    And tapping still opens the word detail view
    And the empty state is visually consistent with other widgets
```

### Scenario B: No words in topic
```gherkin
  Scenario: Topic is empty (no words added)
    Given the app has a topic with no words
    When the medium examples widget is added
    Then the widget shows an empty state
    And a message like "No word selected" or "Add words to get started" is displayed
    And tapping the widget does not crash
    And if the user adds a word to the topic, widget updates on next refresh
```

### Scenario C: Topic switching
```gherkin
  Scenario: User switches topics in the app
    Given the examples widget is displaying Word A from Topic 1
    And the app is switched to Topic 2
    When Widget refresh occurs (normal cadence)
    Then the widget displays a word from Topic 2
    And the examples shown correspond to the newly selected topic
    And no stale data from Topic 1 is displayed
```

---

## 3. PERSISTED STATE: Consistency Across Widgets

### Scenario: Topic selection consistency
```gherkin
  Scenario: Topic selection is unified across all widgets
    Given the user has small action widget, medium action widget, and examples widget
    And all widgets are displaying words from Topic 1
    When the user changes topic in the app
    Then all widgets immediately respect the new topic selection (on refresh)
    And no widget shows data from a different topic than the others
    And the selected word is consistent across all widgets
```

### Scenario: Progress index isolation
```gherkin
  Scenario: Word progress does not advance when browsing examples
    Given a word has progress_index = 3
    When the user taps the examples widget to view details
    And closes the detail view
    Then the word's progress_index remains 3
    And only navigation to word detail via examples widget does NOT increment progress
    And interacting with small/medium action widgets still increments progress normally
```

### Scenario: Timeline refresh cadence
```gherkin
  Scenario: Widget respects 5-minute refresh timeline
    Given the examples widget is displayed at time T
    When T + 3 minutes pass
    Then the widget content does not change
    And no background network activity occurs
    
  Scenario: Widget updates after timeline interval
    Given the examples widget displayed Word A at time T
    When T + 5 minutes pass
    Then the widget refreshes and may show a different word (new topic selection)
    And the refresh does not re-increment progress on the previous word
```

---

## 4. WIDGET INTERACTION: Navigation & Integration

### Scenario: Tapping opens word detail view
```gherkin
  Scenario: Full widget tap navigates to word detail
    Given the examples widget is displayed
    When I tap anywhere on the examples widget
    Then the word detail view opens
    And the word shown matches the widget's current word
    And the detail view shows all examples (not just the first one)
    And the detail view is read-only (no editing from this entry point)
    And tapping a specific example number does not scroll or highlight that example in detail view
    
  Scenario: Navigation links back to Home Screen
    Given the word detail view was opened from examples widget
    When I tap back or close the detail view
    Then I return to Home Screen
    And the examples widget is visible and unchanged
```

### Scenario: Other widgets remain independent
```gherkin
  Scenario: Small action widget operates independently
    Given small action and examples widgets both show Word A
    When I tap the small action widget to advance
    Then Word A's progress_index increments
    And the medium examples widget still shows Word A (unchanged state)
    And the next refresh cycle applies new selection to both widgets

  Scenario: Medium action widget operates independently
    Given medium action and examples widgets both show Word A
    When I tap the medium action widget to reveal answer
    Then the answer is shown on the medium action widget
    And the examples widget remains unaffected (shows only examples)
    And both widgets continue to refresh on the normal cadence
```

### Scenario: Widget availability on Home Screen
```gherkin
  Scenario: Examples widget appears as an option when adding widgets
    Given I open Home Screen widget picker
    When I search for or scroll to VocabularyWidget options
    Then I see:
      | Option |
      | Small Action Widget |
      | Medium Action Widget |
      | Medium Examples Widget |
    And I can tap to add the "Medium Examples Widget"
    
  Scenario: Multiple examples widgets can be added
    Given one examples widget is already on Home Screen
    When I add a second examples widget
    Then both widgets appear on Home Screen
    And both display the same word (same topic selection)
    And both refresh on the same cadence
    And tapping either opens the same word detail view
```

---

## 5. TESTING PLAN

### Automated Tests (Unit + Integration)
- ✅ Widget correctly parses 5 examples from data model
- ✅ Widget handles < 5 examples without rendering empty slots
- ✅ Empty state displays when examples array is nil/empty
- ✅ Topic selection state is read from shared UserDefaults/AppStorage
- ✅ Progress index does NOT increment when entering detail view from examples widget
- ✅ Widget configuration correctly identifies systemMedium size
- ✅ Link wrapper on the entire view is properly constructed
- ✅ All 5 example texts are rendered in correct order
- ✅ Widget timeline respects 5-minute refresh interval

### Manual Tests (Simulator/Device)
- ⚠️ Visual layout: All 5 examples fit without truncation or overflow
- ⚠️ Color scheme and styling match existing widgets
- ⚠️ Tapping widget smoothly opens word detail view (no crashes/delays)
- ⚠️ Switching topics in app → widget updates reflect new topic
- ⚠️ Small/medium action widgets still increment progress independently
- ⚠️ Widget appears in Home Screen picker UI
- ⚠️ Multiple examples widgets can be added and display consistently
- ⚠️ Empty state is user-friendly when word has < 5 examples
- ⚠️ Empty state is user-friendly when no words exist in topic

### Device-Specific Tests (Physical iPhone)
- ⚠️ Confirm widget loads in actual Home Screen (not just simulator)
- ⚠️ Verify tapping opens app to word detail view (URL scheme works)
- ⚠️ Check that widget respects device light/dark mode
- ⚠️ Confirm refresh cadence works over time (monitor 5-minute cycles)
- ⚠️ Test on different iPhone sizes (Pro Max, standard, SE) for layout stability

---

## 6. DEFINITION OF DONE

The feature is considered complete when:
1. ✅ All 5 examples display correctly for words with full data
2. ✅ Edge cases (< 5 examples, empty topics) are handled gracefully
3. ✅ Topic selection is consistent across all widgets
4. ✅ Progress index does NOT increment when viewing examples
5. ✅ Tapping opens the full word detail view
6. ✅ Styling matches the existing VocabularyWidget theme
7. ✅ Widget appears as an option in Home Screen picker
8. ✅ All automated tests pass
9. ✅ QC verification on simulator completes all manual scenarios
10. ✅ (If applicable) QC verification on physical device confirms behavior

---

## Notes for QC

- Test with words that have exactly 5, 4, 2, 1, and 0 examples to cover the spectrum
- Verify the widget can be added/removed from Home Screen without crashes
- Confirm the refresh cadence is respected (no excessive network calls every few seconds)
- When testing topic switching, use topics with different numbers of words to confirm isolation
- Check that opening the app from the widget doesn't create duplicate tabs or corrupt state
