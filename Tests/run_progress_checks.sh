#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT="${TMPDIR:-/tmp}/vocabulary-widget-progress-checks"
MODULE_CACHE="${TMPDIR:-/tmp}/vocabulary-widget-swift-modules"
mkdir -p "$MODULE_CACHE"

GROUP_ID="group.com.example.VocabularyWidget"
grep -Fq "static let appGroupID = \"$GROUP_ID\"" "$ROOT/Shared/WidgetProgressStore.swift"
grep -Fq "<string>$GROUP_ID</string>" "$ROOT/App/VocabularyWidget.entitlements"
grep -Fq "<string>$GROUP_ID</string>" "$ROOT/Widget/VocabularyWidgetExtension.entitlements"

swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT/Shared/VocabularyData.swift" \
  "$ROOT/Shared/WidgetProgressStore.swift" \
  "$ROOT/Tests/ProgressStoreChecks.swift" \
  -o "$OUTPUT"
"$OUTPUT"
