#!/usr/bin/env python3
"""Check extraction and stable dispatch identity in a built widget extension."""

import json
import pathlib
import sys

if len(sys.argv) != 3:
    sys.exit("Usage: python3 Tests/check_next_word_intent_metadata.py EXTENSION.appex VocabularyWidget.swiftconstvalues")

bundle = pathlib.Path(sys.argv[1])
constants_path = pathlib.Path(sys.argv[2])
metadata = json.loads((bundle / "Metadata.appintents/extract.actionsdata").read_text())
action = metadata["actions"].get("NextWordIntent")
assert action is not None, "NextWordIntent is missing from extracted actions"
qualified_name = "VocabularyWidgetExtension.NextWordIntent"
assert action["fullyQualifiedTypeName"] == qualified_name, "unexpected dispatch type"
assert action["identifier"] == "NextWordIntent", "unexpected action identifier"
assert [parameter["name"] for parameter in action["parameters"]] == [
    "topicID", "displayedIndex"
], "widget action payload changed"
assert all(not parameter["isOptional"] for parameter in action["parameters"]), "action payload must be required"

constants = json.loads(constants_path.read_text())
intent = next(value for value in constants if value["typeName"] == qualified_name)
assert "AppIntents.AppIntent" in intent["conformances"], "missing AppIntent conformance"
expected_mangled_name = "25VocabularyWidgetExtension14NextWordIntentV"
assert intent["mangledTypeName"] == expected_mangled_name, "intent has a private or unexpected type identity"
assert action["mangledTypeName"] == expected_mangled_name, "metadata dispatch identity differs from Swift type"
if "mangledTypeNameV2" in action:
    assert action["mangledTypeNameV2"] == expected_mangled_name, "V2 dispatch identity differs from Swift type"
print("NextWordIntent metadata checks passed (discovery, payload, non-private dispatch identity).")
