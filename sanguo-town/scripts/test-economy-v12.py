#!/usr/bin/env python3
"""Black-box v0.12 economy check against an isolated formal Godot save."""
import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BIN = ROOT / ".build/debug/SanguoLifeCLI"

with tempfile.TemporaryDirectory(prefix="godot-fixture-economy-") as directory:
    def call(operation="snapshot", seconds=0, **extra):
        request = {"operation": operation, "seconds": seconds, "realUTC": 0, **extra}
        response = json.loads(subprocess.check_output(
            [str(BIN), "--godot-bridge", json.dumps(request), "--godot-save", directory], text=True,
        ))
        assert response["ok"], response
        return response

    initial = call()
    assert initial["coins"] == 200
    assert initial["goldChain"]["coinsPerIngot"] == 100
    assert initial["resources"]["gold_ore"] == 0
    assert any(plot["id"] == "goldmine-1" and plot["service"] > 0 for plot in initial["plots"])
    print("PASS new desktop save has a working mine without free ore and a 100-coin ingot rate")

    call("draw", commandID="first", count=1)
    spent = call("draw", commandID="second", count=1)
    assert spent["coins"] == 0 and spent["goldChain"]["nextDrawMissing"] == 100
    print("PASS two player draws consume only the opening wallet")

    earned = call("advance", seconds=2_400)
    assert earned["coins"] >= 100
    assert earned["minted"] == earned["goldChain"]["deliveredIngots"] // 1000 * 100
    assert earned["goldChain"]["nextDrawMissing"] == 0
    print("PASS first earned draw is minted from delivered ingots within 20 real minutes at 2x")

    before_reload = pathlib.Path(directory, "world.json").read_bytes()
    reloaded = call()
    after_reload = pathlib.Path(directory, "world.json").read_bytes()
    assert reloaded["coins"] == earned["coins"] and before_reload == after_reload
    print("PASS reload does not re-mint or rewrite the economy save")

with tempfile.TemporaryDirectory(prefix="godot-fixture-meals-") as directory:
    def call_meals(seconds, real_utc):
        response = json.loads(subprocess.check_output(
            [str(BIN), "--godot-bridge", json.dumps({
                "operation": "advance" if seconds else "snapshot",
                "seconds": seconds, "realUTC": real_utc,
            }), "--godot-save", directory], text=True,
        ))
        assert response["ok"], response
        return response

    call_meals(0, 0)
    for index in range(1, 25):
        state = call_meals(3_600, index * 1_800)
    assert state["food"] >= 9_500 and not state["supplyRecovery"]
    assert state["resources"]["grain"] > 0 and state["resources"]["meal"] > 0
    print("PASS 12-hour military-town replay keeps meals accessible and avoids recovery deadlock")
