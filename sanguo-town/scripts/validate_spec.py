#!/usr/bin/env python3
"""Validate the PRD fixtures only. This is NOT the game's simulation or UI test suite."""
from __future__ import annotations
import hashlib
import json
import math
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
results: list[dict[str, str]] = []

def read_json(relative: str) -> Any:
    path = ROOT / relative
    if not path.is_file():
        raise FileNotFoundError(f"Missing required fixture: {relative}")
    return json.loads(path.read_text(encoding="utf-8"))

def check(name: str, condition: bool) -> None:
    if not condition:
        raise ValueError(f"Static check failed: {name}")
    results.append({"name": name, "result": "pass"})

def main() -> None:
    config = read_json("spec/prototype-config.json")
    fixture = read_json("spec/three-city-fixture.json")
    cases = read_json("spec/acceptance-cases.json")
    doc = (ROOT / "docs/PRD.md").read_text(encoding="utf-8")
    cap = config["capacity"]
    check("document version matches config", "PRD v0.3" in doc and config["document_version"] == "0.3")
    check("fixture explicitly not an implementation", config["status"] == "design_fixture_not_game_implementation")
    check("capacity: three cities one district one legion", [cap[k] for k in ("cities", "districts", "legions")] == [3,1,1])
    check("three cities have unique ids", len({c["id"] for c in config["cities"]}) == 3)
    check("nine world nodes have unique ids", len(set(config["world_nodes"])) == cap["world_nodes"] == 9)
    for route in config["routes"]:
        check("route endpoints:"+route["id"], route["a"] in config["world_nodes"] and route["b"] in config["world_nodes"] and route["one_way_seconds"] > 0)
    for name, weights in config["policy"]["presets"].items():
        check("policy weights:"+name, len(weights) == 5 and sum(weights) == 100 and min(weights) >= 0)
    check("periodic operating caps sum correctly", config["policy"]["operating_per_city"] * cap["cities"] == config["policy"]["operating_realm_max"])
    check("initial treasury does not violate reserve", config["initial"]["treasury"] >= config["initial"]["startup_capital_allowance"] + config["policy"]["treasury_floor_per_city"])
    check("initial labor formula", config["initial"]["labor"] == math.floor(config["initial"]["population"]*.75))
    for city, bundle in config["city_packages"].items():
        check("city package conserves inventory:"+city, all(bundle["outgoing"][r] == bundle["consumed"][r]+bundle["starting_stock"][r] for r in bundle["outgoing"]))
        count = math.ceil(sum(bundle["outgoing"].values())/cap["cargo_per_shipment"])
        check("city package shipment count:"+city, count == bundle["minimum_shipments"])
    check("local market buy price exceeds sell", all(config["markets"]["local_buy"][r] > price for r,price in config["markets"]["local_sell"].items()))
    sell,buy = config["markets"]["offers"]
    extra = sell["units"] * (sell["unit_price"]-config["markets"]["local_sell"][sell["cargo"]])-sell["freight"]
    check("external wine opportunity contribution = 70", extra == 70)
    arrived_cost = buy["units"] * buy["unit_price"] + buy["freight"]
    check("iron arrived cost = 210", arrived_cost == 210)
    check("operating cap can cover example iron purchase", config["policy"]["operating_per_city"] >= arrived_cost)
    check("iron cost saving = 30", buy["units"]*config["markets"]["local_buy"][buy["cargo"]]-arrived_cost == 30)
    check("capital allowance example = 100", max(0,min(400,.4*200+20,2000-300-500-200)) == 100)
    # Continuous steady-state arithmetic only: no discrete-event simulation is performed.
    check("neutral fixture grain net = 52", 2*60-60-16*.5 == 52)
    check("plain fixture grain net = 82", 2*60*1.25-60-16*.5 == 82)
    check("stone fixture grain net = 28", 2*60*.8-60-16*.5 == 28)
    check("stone fixture wood net = 9.6", math.isclose(36-24*1.1,9.6))
    check("stone fixture iron net = 1.8", math.isclose(12*1.25-12*1.1,1.8))
    check("two product gross receipts = 408", 12*14+6*40 == 408)
    check("six unique heroes", len(config["characters"]) == len({h["id"] for h in config["characters"]}) == 6)
    check("six weapons four mounts", len(config["collections"]["weapons"]) == 6 and len(config["collections"]["mounts"]) == 4)
    check("16 core collections", len(config["characters"])+len(config["collections"]["weapons"])+len(config["collections"]["mounts"]) == 16)
    holders = [a["holder"] for a in fixture["appointments"] if a["state"] == "active"]
    check("no duplicate active actor appointments", len(holders) == len(set(holders)))
    check("seven distinct active office holders", len(holders) == 7)
    hero_ids = {h["id"] for h in config["characters"]}
    check("missing hero seats filled by NPC", all(h in hero_ids or h.startswith("npc-") for h in holders))
    check("governor not a prefect or active legion leader", fixture["districts"][0]["governor"] not in [c["prefect"] for c in fixture["cities"]] + fixture["legions"][0]["leaders"])
    check("fixture cities match district scope", set(fixture["districts"][0]["cities"]) == {c["id"] for c in fixture["cities"]})
    for c in fixture["cities"]:
        check("city inventory and labor:"+c["id"], c["labor"] == math.floor(c["population"]*.75) and all(0 <= v <= c["inventory_capacity_each"] for v in c["resources"].values()) and c["slots_used"] <= cap["city_slots"])
    check("transport unique position and IDs", len({t["id"] for t in fixture["transport_teams"]}) == 3 and all(t["location"] in config["world_nodes"] for t in fixture["transport_teams"]))
    check("military ceiling and recovery attempts", config["campaign"]["max_actions"] == 4 and config["campaign"]["alternative_attempts_after_failure"] == 1)
    check("appointments never expire by default", config["offline"]["appointments_expire"] is False)
    check("seven-day normal offline cap", config["offline"]["normal_cap_seconds"] == 7*24*3600)
    check("activity opt-in and cap", config["activity"]["enabled_by_default"] is False and config["activity"]["project_fraction_limit"] == .2)
    check("100 unique acceptance IDs", len(cases) == len({c["id"] for c in cases}) == 100)
    check("all application tests honestly not run", all(c["status"] == "not_run" for c in cases))
    check("90 core and 10 optional acceptance cases", sum(c["scope"] == "P0" for c in cases) == 90 and sum(c["scope"] == "P0-R" for c in cases) == 10)
    check("all acceptance IDs present in full PRD", all(c["id"] in doc for c in cases))
    check("ten decision cards present", all(f"## DEC-{i:02d} " in doc for i in range(1,11)))
    check("seven appendices present", all(f"# 附录{letter} " in doc for letter in "ABCDEFG"))
    check("27 main chapters present", all(f"# {i:02d} " in doc for i in range(1,28)))
    check("no raw tool citation markers", "" not in doc and "turn806992" not in doc)
    hashes = {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/"docs/PRD.md",ROOT/"spec/prototype-config.json",ROOT/"spec/three-city-fixture.json",ROOT/"spec/acceptance-cases.json"]}
    report = {"scope":"document_and_static_fixtures_only","checks_passed":len(results),"checks":results,"file_sha256":hashes,"game_simulation_tested":False,"m4_tested":False,"application_acceptance_not_run":100}
    (ROOT / "docs/static-validation.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"PASS: {len(results)} static checks. Game simulation / M4 / 100 application cases: NOT RUN.")

if __name__ == "__main__":
    main()
