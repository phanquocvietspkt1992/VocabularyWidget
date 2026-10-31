#!/usr/bin/env python3
"""Verify the shared audio intent is discoverable in both target products."""

import json
import pathlib
import plistlib
import sys

if len(sys.argv) != 4:
    sys.exit("Usage: python3 Tests/check_pronunciation_metadata.py BUNDLE PronunciationIntent.swiftconstvalues MODULE")

bundle = pathlib.Path(sys.argv[1])
constants = json.loads(pathlib.Path(sys.argv[2]).read_text())
module = sys.argv[3]
assert module in {"VocabularyWidgetApp", "VocabularyWidgetExtension"}, "unexpected target module"
with (bundle / "Info.plist").open("rb") as plist_file:
    info = plistlib.load(plist_file)
if module == "VocabularyWidgetApp":
    assert info.get("UIBackgroundModes") == ["audio"], "host app must declare the audio background mode array"
else:
    assert "UIBackgroundModes" not in info, "widget extension must not declare background modes"
identifier = "SpeakWordIntent"
qualified_name = f"{module}.{identifier}"
mangled_name = f"{len(module)}{module}{len(identifier)}{identifier}V"
metadata = json.loads((bundle / "Metadata.appintents/extract.actionsdata").read_text())
action = metadata["actions"].get(identifier)
assert action is not None, "SpeakWordIntent is missing from extracted actions"
assert action["fullyQualifiedTypeName"] == qualified_name, "unexpected dispatch type"
assert action["identifier"] == identifier, "unexpected action identifier"
assert [parameter["name"] for parameter in action["parameters"]] == ["word"], "speak only the displayed word payload"
assert not action["parameters"][0]["isOptional"], "word must be required"
intent = next(value for value in constants if value["typeName"] == qualified_name)
assert "AppIntents.AudioPlaybackIntent" in intent["conformances"], "missing app-process audio playback conformance"
assert intent["mangledTypeName"] == mangled_name, "private or unexpected type identity"
assert action["mangledTypeName"] == mangled_name, "metadata dispatch differs from Swift type"
if "mangledTypeNameV2" in action:
    assert action["mangledTypeNameV2"] == mangled_name, "V2 dispatch differs from Swift type"
print(f"SpeakWordIntent metadata checks passed for {module} (discovery, required word, AudioPlaybackIntent, non-private identity, target-specific background audio mode).")
