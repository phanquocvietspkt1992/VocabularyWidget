#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/build/dev-schedule-checks"
mkdir -p "$OUTPUT_DIR/modules"
swiftc -module-cache-path "$OUTPUT_DIR/modules" \
  "$ROOT/Shared/VocabularyExtraExamples.swift" \
  "$ROOT/Shared/VocabularyData.swift" \
  "$ROOT/Shared/VocabularySchedule.swift" \
  "$ROOT/Shared/WidgetProgressStore.swift" \
  "$ROOT/Tests/ScheduleChecks.swift" -o "$OUTPUT_DIR/checks"
"$OUTPUT_DIR/checks"
