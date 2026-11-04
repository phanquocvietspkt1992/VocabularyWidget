#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT="$(mktemp -d "${TMPDIR:-/tmp}/VocabularyWidget-sentences.XXXXXX")"
trap 'rm -rf "$OUTPUT"' EXIT
swiftc -module-cache-path "$OUTPUT/modules" "$ROOT/App/SentenceGame.swift" "$ROOT/App/SentenceAudio.swift" "$ROOT/Tests/SentenceGameChecks.swift" -o "$OUTPUT/checks"
"$OUTPUT/checks"