#!/usr/bin/env python3
"""
Clean Localizable.xcstrings by removing keys that are not referenced in source code.
Keeps only keys that appear as a substring in any .swift or .plist file under NaarsCars.
"""
import json
import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = REPO_ROOT / "Resources" / "Localizable.xcstrings"
SOURCE_DIR = REPO_ROOT  # NaarsCars folder

def main():
    print("Loading catalog...")
    with open(CATALOG_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    strings = data.get("strings", {})
    total_keys = len(strings)
    print(f"Total keys in catalog: {total_keys}")

    # Collect all source file contents (Swift, plist); skip xcstrings and non-text
    source_contents = []
    for ext in ("*.swift", "*.plist"):
        for path in SOURCE_DIR.rglob(ext):
            if "Localizable.xcstrings" in str(path) or ".build" in str(path):
                continue
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as f:
                    source_contents.append(f.read())
            except Exception as e:
                print(f"  Skip {path}: {e}")

    combined = "\n".join(source_contents)
    print(f"Scanned {len(source_contents)} source files")

    # Keep only keys that appear in source
    kept = {}
    removed = []
    for key in strings:
        if key in combined:
            kept[key] = strings[key]
        else:
            removed.append(key)

    data["strings"] = kept
    print(f"Kept: {len(kept)}, Removed: {len(removed)}")

    # Backup then write
    backup = REPO_ROOT / "Resources" / "Localizable.xcstrings.backup"
    if not backup.exists():
        print(f"Creating backup: {backup}")
        with open(CATALOG_PATH, "r", encoding="utf-8") as f:
            backup.write_text(f.read(), encoding="utf-8")

    with open(CATALOG_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print("Done. Catalog written.")
    if removed and len(removed) <= 30:
        print("Removed keys (sample):", removed[:30])
    elif removed:
        print("Removed keys (first 20):", removed[:20])
        print("... and", len(removed) - 20, "more")

if __name__ == "__main__":
    main()
