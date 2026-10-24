#!/usr/bin/env python3
"""Add new keys to NaarsCars/Resources/Localizable.xcstrings, preserving Xcode's byte layout.

Usage: python3 -I scripts/add-localization-keys.py <keys.json>
Input: {"key": {"en": ..., "es": ..., "ko": ..., "vi": ..., "zh-Hans": ..., "zh-Hant": ...}}
Refuses a key that exists or misses a locale. Inserts each new key at its sorted position.
"""
import json
import os
import sys

LOCALES = ["en", "es", "ko", "vi", "zh-Hans", "zh-Hant"]
CATALOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "NaarsCars", "Resources", "Localizable.xcstrings")


def dump(d):
    return json.dumps(d, ensure_ascii=False, indent=2, separators=(",", " : ")).replace("{}", "{\n\n    }")


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: add-localization-keys.py <keys.json>")
    with open(sys.argv[1], encoding="utf-8") as f:
        new_keys = json.load(f)
    with open(CATALOG, encoding="utf-8") as f:
        raw = f.read()
    catalog = json.loads(raw)
    if dump(catalog) != raw:
        sys.exit("refusing: re-serializing the unmodified catalog does not reproduce the file byte for byte")

    for key, values in new_keys.items():
        if key in catalog["strings"]:
            sys.exit("refusing: key already exists: " + key)
        missing = [l for l in LOCALES if not values.get(l)]
        if missing:
            sys.exit("refusing: %s misses locales %s" % (key, missing))

    old_keys = list(catalog["strings"].keys())
    strings = dict(catalog["strings"])
    for key in sorted(new_keys, key=str.casefold):
        entry = {
            "extractionState": "manual",
            "localizations": {
                l: {"stringUnit": {"state": "translated", "value": new_keys[key][l]}} for l in LOCALES
            },
        }
        items = list(strings.items())
        pos = len(items)
        for i, (k, _) in enumerate(items):
            if k.casefold() > key.casefold():
                pos = i
                break
        items.insert(pos, (key, entry))
        strings = dict(items)
    catalog["strings"] = strings

    with open(CATALOG, "w", encoding="utf-8") as f:
        f.write(dump(catalog))

    with open(CATALOG, encoding="utf-8") as f:
        after = json.load(f)
    expected = [k for k in after["strings"] if k not in new_keys]
    assert expected == old_keys, "old key order changed"
    for k in old_keys:
        assert after["strings"][k] == json.loads(raw)["strings"][k], "entry changed: " + k
    print("added %d key(s)" % len(new_keys))


if __name__ == "__main__":
    main()
