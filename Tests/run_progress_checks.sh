#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/build/dev-study-history-progress-checks"
OUTPUT="$OUTPUT_DIR/checks"
MODULE_CACHE="$OUTPUT_DIR/modules"
mkdir -p "$MODULE_CACHE"

GROUP_ID="group.com.phanquocviet.VocabularyWidget"
grep -Fq "static let appGroupID = \"$GROUP_ID\"" "$ROOT/Shared/WidgetProgressStore.swift"
grep -Fq "<string>$GROUP_ID</string>" "$ROOT/App/VocabularyWidget.entitlements"
grep -Fq "<string>$GROUP_ID</string>" "$ROOT/Widget/VocabularyWidgetExtension.entitlements"

swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT/Shared/VocabularyExtraExamples.swift" \
  "$ROOT/Shared/VocabularySchedule.swift" \
  "$ROOT/Shared/VocabularyNotifications.swift" \
  "$ROOT/Shared/VocabularyData.swift" \
  "$ROOT/Shared/WidgetProgressStore.swift" \
  "$ROOT/Tests/ProgressStoreChecks.swift" \
  -o "$OUTPUT"
"$OUTPUT"
