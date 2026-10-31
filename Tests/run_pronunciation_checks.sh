#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/build/dev-pronunciation-checks"
mkdir -p "$OUTPUT_DIR/modules"
swiftc \
  -module-cache-path "$OUTPUT_DIR/modules" \
  "$ROOT/Shared/PronunciationIntent.swift" \
  "$ROOT/Tests/PronunciationChecks.swift" \
  -o "$OUTPUT_DIR/checks"
"$OUTPUT_DIR/checks"
