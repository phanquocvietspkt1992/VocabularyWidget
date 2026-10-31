#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/build/next-word-intent-checks"
mkdir -p "$OUTPUT_DIR/modules"

# Compile the production intent verbatim, without the widget's separate @main.
python3 - "$ROOT/Widget/VocabularyWidget.swift" "$ROOT/Tests/NextWordIntentChecks.swift" "$OUTPUT_DIR/NextWordIntent.swift" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
start = source.index("struct NextWordIntent: AppIntent")
if source[max(0, start - 8):start].endswith("private "):
    start -= len("private ")
end = source.index("\n@main", start)
checks = pathlib.Path(sys.argv[2]).read_text()
pathlib.Path(sys.argv[3]).write_text("import AppIntents\nimport WidgetKit\n" + source[start:end] + checks)
PY

swiftc \
  -module-name VocabularyWidgetExtension \
  -module-cache-path "$OUTPUT_DIR/modules" \
  "$ROOT/Shared/VocabularyData.swift" \
  "$ROOT/Shared/WidgetProgressStore.swift" \
  "$OUTPUT_DIR/NextWordIntent.swift" \
  -o "$OUTPUT_DIR/checks"
"$OUTPUT_DIR/checks"
