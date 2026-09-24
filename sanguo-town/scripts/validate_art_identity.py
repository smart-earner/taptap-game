#!/usr/bin/env python3
"""Keep the Godot town silhouettes aligned with the Swift roster/card art."""

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SWIFT = ROOT / "Sources/SanguoLifeVisual/LifeHeroArt.swift"
GODOT = ROOT / "godot/scripts/desktop_map_2d.gd"
CATALOG = ROOT / "Sources/SanguoLife/Resources/hero-town-v0.9.json"

SWIFT_ROW = re.compile(
    r'\("(?P<id>[a-z]+)","#(?P<coat>[0-9A-Fa-f]{6})","#(?P<trim>[0-9A-Fa-f]{6})",'
    r'(?P<head>\d+),(?P<beard>\d+),(?P<build>\d+(?:\.\d+)?)\)'
)
GODOT_ROW = re.compile(
    r'"(?P<id>[a-z]+)":\{"coat":"(?P<coat>[0-9A-Fa-f]{6})",'
    r'"trim":"(?P<trim>[0-9A-Fa-f]{6})","head":(?P<head>\d+),'
    r'"beard":(?P<beard>\d+),"build":(?P<build>(?:\d+)?\.\d+|\d+)\}'
)


def looks(path: Path, pattern: re.Pattern[str]) -> dict[str, tuple]:
    rows = [match.groupdict() for match in pattern.finditer(path.read_text())]
    assert len(rows) == len({row["id"] for row in rows}), f"duplicate hero ID in {path}"
    return {
        row["id"]: (
            row["coat"].lower(), row["trim"].lower(),
            int(row["head"]), int(row["beard"]), float(row["build"]),
        )
        for row in rows
    }


def main() -> None:
    swift = looks(SWIFT, SWIFT_ROW)
    godot = looks(GODOT, GODOT_ROW)
    catalog = {hero["id"] for hero in json.loads(CATALOG.read_text())["heroes"]}
    assert set(swift) == catalog, f"Swift appearance roster differs from catalog: {set(swift) ^ catalog}"
    assert set(godot) == catalog, f"Godot appearance roster differs from catalog: {set(godot) ^ catalog}"
    mismatches = [hero_id for hero_id in sorted(catalog) if swift[hero_id] != godot[hero_id]]
    assert not mismatches, f"Godot/Swift identity mismatch: {mismatches}"
    assert len(set(godot.values())) == len(godot), "two hero IDs have exactly the same appearance"
    print(f"ART_IDENTITY_PASS {len(catalog)} catalog heroes aligned")


if __name__ == "__main__":
    main()
