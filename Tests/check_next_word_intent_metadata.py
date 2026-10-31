#!/usr/bin/env python3
"""Check extracted widget action discovery and stable dispatch identities."""

import json
import pathlib
import sys

if len(sys.argv) != 3:
    sys.exit("Usage: python3 Tests/check_next_word_intent_metadata.py EXTENSION.appex VocabularyWidget.swiftconstvalues")

bundle = pathlib.Path(sys.argv[1])
constants_path = pathlib.Path(sys.argv[2])
metadata = json.loads((bundle / "Metadata.appintents/extract.actionsdata").read_text())
constants = json.loads(constants_path.read_text())

for identifier, mangled_name in (
    ("NextWordIntent", "25VocabularyWidgetExtension14NextWordIntentV"),
    ("StudiedWordIntent", "25VocabularyWidgetExtension17StudiedWordIntentV"),
):
    action = metadata["actions"].get(identifier)
    assert action is not None, f"{identifier} is missing from extracted actions"
    qualified_name = f"VocabularyWidgetExtension.{identifier}"
    assert action["fullyQualifiedTypeName"] == qualified_name, f"unexpected {identifier} dispatch type"
    assert action["identifier"] == identifier, f"unexpected {identifier} action identifier"
    assert [parameter["name"] for parameter in action["parameters"]] == [
        "topicID", "displayedIndex"
    ], f"{identifier} widget action payload changed"
    assert all(not parameter["isOptional"] for parameter in action["parameters"]), f"{identifier} payload must be required"

    intent = next(value for value in constants if value["typeName"] == qualified_name)
    assert "AppIntents.AppIntent" in intent["conformances"], f"{identifier} is missing AppIntent conformance"
    assert intent["mangledTypeName"] == mangled_name, f"{identifier} has a private or unexpected type identity"
    assert action["mangledTypeName"] == mangled_name, f"{identifier} metadata dispatch identity differs from Swift type"
    if "mangledTypeNameV2" in action:
        assert action["mangledTypeNameV2"] == mangled_name, f"{identifier} V2 dispatch identity differs from Swift type"

print("NextWordIntent and StudiedWordIntent metadata checks passed (discovery, payload, non-private dispatch identity).")
