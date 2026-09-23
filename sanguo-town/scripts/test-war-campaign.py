#!/usr/bin/env python3
"""Black-box early war and real-clock boundary against an isolated Godot save."""
import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BIN = ROOT / ".build/debug/SanguoLifeCLI"

with tempfile.TemporaryDirectory(prefix="godot-fixture-war-") as directory:
    def call(operation="snapshot", seconds=0, real_utc=0):
        request = {"operation": operation, "seconds": seconds, "realUTC": real_utc}
        response = json.loads(subprocess.check_output(
            [str(BIN), "--godot-bridge", json.dumps(request), "--godot-save", directory],
            text=True,
        ))
        assert response["ok"], response
        return response

    start = call()
    assert len(start["campaign"]["cities"]) == 12
    assert start["campaign"]["cities"]["00"]["recruitPool"] == 40
    assert start["campaign"]["soldierCount"] == 0 if "soldierCount" in start["campaign"] else not start["campaign"]["squads"]
    print("PASS twelve cities and initial finite recruit pool")

    progressed = call("advance", 30_000)
    war = progressed["campaign"]
    first_city = war["cities"]["01"]
    assert first_city["owner"] == "enemy", "frozen real time must not gift a core capture"
    assert first_city["points"]["outer"] == "player"
    assert war["cities"]["02"]["points"]["outer"] == "player"
    assert len([key for key in war["firstClearReceipts"] if key.startswith("01:")]) >= 1
    assert war["cities"]["00"]["recruitPool"] == 0
    first_city_reports = [row for row in war.get("reports", []) if row.get("cityID") == "01" and row.get("kind") == "battle_win"]
    assert first_city_reports
    assert all(row["attack"] > row["defense"] and row["casualties"] >= 0 for row in first_city_reports)
    print("PASS real soldiers clear border points without bypassing finite recruitment or the core")
    assert "stone_transport" not in (war.get("builtFacilities") or [])
    saved = json.loads((pathlib.Path(directory) / "world.json").read_text())
    world = json.loads(saved["payload"])
    assert world["consumed"].get("wood", 0) >= 2_000
    assert world["consumed"].get("iron", 0) >= 1_000
    assert world["consumed"].get("rations", 0) >= 1_000
    print("PASS recruitment and expedition consume real equipment and rations")
    loot = [lot for lot in world["lots"].values() if lot["origin"].startswith("war-loot:")]
    assert loot
    assert any(lot["location"] == "warehouse" for lot in loot)
    assert all(lot["amount"] > 0 for lot in loot)
    print("PASS finite border loot reached the capital through real transport tasks")

    reloaded = call()
    assert set(reloaded["campaign"]["firstClearReceipts"]) == set(war["firstClearReceipts"])
    assert reloaded["campaign"]["cities"]["01"]["owner"] == "enemy"
    assert reloaded["campaign"]["cities"]["01"]["points"]["outer"] == "player"
    print("PASS save/reload retains partial captures without duplicate rewards")

    raid = call(real_utc=2_700)
    assert raid["campaign"]["raidIndex"] == 1
    repeated = call(real_utc=2_700)
    assert repeated["campaign"]["raidIndex"] == 1
    print("PASS real-time raid watermark persists across snapshots")

    paused = call("pause_war", real_utc=2_700)
    assert paused["campaign"]["paused"]
    assert call("resume_war", real_utc=2_700)["campaign"]["paused"] is False
    print("PASS player can pause and resume new offensives")
