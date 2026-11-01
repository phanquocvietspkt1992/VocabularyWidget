#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/VocabularyWidget-progress.XXXXXX")"
trap 'rm -rf "$OUTPUT_DIR"' EXIT
OUTPUT="$OUTPUT_DIR/checks"
MODULE_CACHE="$OUTPUT_DIR/modules"
mkdir -p "$MODULE_CACHE"

GROUP_ID="group.com.phanquocviet.VocabularyWidget"
grep -Fq "static let appGroupID = \"$GROUP_ID\"" "$ROOT/Shared/WidgetProgressStore.swift"
grep -Fq "<string>$GROUP_ID</string>" "$ROOT/App/VocabularyWidget.entitlements"
grep -Fq "<string>$GROUP_ID</string>" "$ROOT/Widget/VocabularyWidgetExtension.entitlements"

awk '/^struct VocabularyWordDetailView: View/ { exit } { print }' \
  "$ROOT/App/VocabularyWordDetailView.swift" > "$OUTPUT_DIR/DetailPresentation.swift"
awk '/^struct TopicPickerView: View/ { exit } { print }' \
  "$ROOT/App/TopicPickerView.swift" > "$OUTPUT_DIR/TopicSelectionModel.swift"

swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT/Shared/VocabularyExtraExamples.swift" \
  "$ROOT/Shared/VocabularySchedule.swift" \
  "$ROOT/Shared/VocabularyNotifications.swift" \
  "$ROOT/Shared/VocabularyData.swift" \
  "$ROOT/Shared/WidgetProgressStore.swift" \
  "$ROOT/Shared/VocabularyLearningStore.swift" \
  "$ROOT/Shared/VocabularyWordDetail.swift" \
  "$OUTPUT_DIR/DetailPresentation.swift" \
  "$OUTPUT_DIR/TopicSelectionModel.swift" \
  "$ROOT/Tests/ProgressStoreChecks.swift" \
  -o "$OUTPUT"
"$OUTPUT"
