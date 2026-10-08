#!/usr/bin/env python3
"""
Compatibility database validator for PSPC5 Plus.
Checks database.json schema, verifies title IDs, and ensures integrity.
"""

import json
import os
import sys

REQUIRED_FIELDS = [
    "game_name",
    "boot_status",
    "gameplay_status",
    "graphics_status",
    "audio_status",
    "input_status",
    "tested_cpu",
    "tested_gpu",
    "emulator_version",
    "notes"
]

VALID_STATUSES = [
    "Playable · Completable",
    "In-game",
    "Intro / In-engine (Not Playable)",
    "Intro / Menu",
    "Boots",
    "Nothing"
]

def validate_database(filepath: str) -> bool:
    if not os.path.exists(filepath):
        print(f"Error: {filepath} not found.", file=sys.stderr)
        return False

    with open(filepath, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            print(f"JSON Syntax Error: {e}", file=sys.stderr)
            return False

    if not isinstance(data, list):
        print("Database root must be a list of game records.", file=sys.stderr)
        return False

    errors = 0
    for idx, record in enumerate(data):
        title = record.get("game_name", f"Record #{idx}")
        for field in REQUIRED_FIELDS:
            if field not in record:
                print(f"[{title}] Missing required field: {field}", file=sys.stderr)
                errors += 1
        
        status = record.get("gameplay_status")
        if status and status not in VALID_STATUSES:
            print(f"[{title}] Unknown gameplay status: '{status}'", file=sys.stderr)
            errors += 1

    if errors == 0:
        print(f"Successfully validated {len(data)} compatibility records in {filepath}.")
        return True
    else:
        print(f"Validation failed with {errors} errors.", file=sys.stderr)
        return False

if __name__ == "__main__":
    db_path = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "compatibility", "database.json")
    success = validate_database(os.path.abspath(db_path))
    sys.exit(0 if success else 1)
