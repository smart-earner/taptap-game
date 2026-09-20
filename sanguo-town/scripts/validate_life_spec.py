#!/usr/bin/env python3
"""Validate PRD 0.6 data and arithmetic only. Does NOT execute the Swift game.
Usage: python3 scripts/validate_life_spec.py [--output dist/life-spec]
The generated application acceptance plan remains NOT_RUN.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECKS: list[dict] = []
VECTORS: list[dict] = []

def require(name: str, condition: bool, detail: str = "") -> None:
    CHECKS.append({"name": name, "status": "PASS" if condition else "FAIL", "detail": detail})

def ceil_div(n: int, d: int) -> int:
    if d <= 0:
        raise ValueError("non-positive divisor")
    return (n + d - 1) // d

def vector(name: str, inputs: dict, actual: object, expected: object) -> None:
    require("golden:" + name, actual == expected, f"actual={actual!r}; expected={expected!r}")
    VECTORS.append({"id": name, "inputs": inputs, "expected": expected,
                    "arithmetic_actual": actual, "scope": "spec_arithmetic_not_game_runtime"})

def index(items: list[dict], name: str) -> dict[str, dict]:
    ids = [v["id"] for v in items]
    require(name + ":unique_ids", len(ids) == len(set(ids)))
    return {v["id"]: v for v in items}

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default=str(ROOT / "dist/life-spec"))
    args = parser.parse_args()
    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    cfg = json.loads((ROOT / "spec/life-v0.6.json").read_text(encoding="utf-8"))
    items = json.loads((ROOT / "spec/collections-v0.6.json").read_text(encoding="utf-8"))
    require("version_match", cfg["spec_version"] == items["spec_version"] == "0.6.0")
    require("honest_status", cfg["status"] == items["status"] == "design_contract_not_runtime_implementation")
    require("no_engine_test_claim", not cfg["implementation"]["engine_tests_executed"])
    require("no_m4_claim", not cfg["implementation"]["m4_playtest_executed"])
    require("no_swift_changes_claim", not cfg["implementation"]["swift_changed_in_this_delivery"])
    resources = index(cfg["resources"], "resources")
    crops = index(cfg["crops"], "crops")
    recipes = index(cfg["recipes"], "recipes")
    jobs = index(cfg["jobs"], "jobs")
    heroes = index(cfg["heroes"], "heroes")
    buildings = index(cfg["buildings"], "buildings")
    weapons = index(items["weapons"], "weapons")
    mounts = index(items["mounts"], "mounts")
    for name, values, expected in [("resources", resources,17),("crops",crops,4),("recipes",recipes,10),
          ("jobs",jobs,20),("heroes",heroes,6),("buildings",buildings,10),("weapons",weapons,6),("mounts",mounts,4)]:
        require(name + ":count", len(values) == expected)
    attrs = {"command","valor","strategy","administration","charisma"}
    for rid, r in resources.items():
        require("volume:" + rid, type(r["volume_milli"]) is int and r["volume_milli"] > 0)
        require("price:" + rid, (r["buy"] is None and r["sell"] is None) or
                (type(r["buy"]) is int and type(r["sell"]) is int and r["buy"] > r["sell"] >= 0))
    for jid, job in jobs.items():
        require("job_attribute:" + jid, job["attribute"] in attrs)
        require("job_shift:" + jid, job["shift"] in {"day","service","roster"})
    def material_check(label: str, material: dict) -> None:
        require(label, all(k in resources and type(v) is int and v > 0 for k,v in material.items()))
    for rid, r in recipes.items():
        require("recipe_job:" + rid, r["job"] in jobs)
        material_check("recipe_input:" + rid, r["inputs_mU"])
        material_check("recipe_output:" + rid, r["outputs_mU"])
        require("recipe_times:" + rid, all(type(r[k]) is int and r[k] >= 0 for k in
              ["prepare_work_s","passive_s","finish_work_s"]) and r["prepare_work_s"] + r["finish_work_s"] > 0)
    for cid, crop in crops.items():
        material_check("crop_output:" + cid, crop["outputs_mU"])
        require("crop_irrigation:" + cid, crop["watering_at_growth_bp"] == [0,5000] and crop["water_mU_each"] > 0)
        require("crop_time:" + cid, crop["mature_growth_s"] > 0 and crop["mature_growth_s"] % 2 == 0)
    for hid, hero in heroes.items():
        require("hero_attrs:" + hid, set(hero["attributes"]) == attrs and all(type(v) is int and 0 <= v <= 100 for v in hero["attributes"].values()))
    require("only_xunyu_starts", [h["id"] for h in cfg["heroes"] if h["starting"]] == ["xunyu"])
    require("initial_population", cfg["initial"]["ordinary_residents"] + len(cfg["initial"]["hero_ids"]) == cfg["initial"]["residents"] == 16)
    material_check("initial_stock", cfg["initial"]["stocks_mU"])
    require("initial_cash", cfg["initial"]["treasury"] >= cfg["economy"]["protected_cash"])
    require("initial_buildings_known", all(b in buildings for b in cfg["initial"]["buildings"]))
    for bid, b in buildings.items():
        material_check("building_material:" + bid, b["materials_mU"])
        require("building_quote:" + bid, b["cash"] > 0 and b["work_s"] > 0)
    require("building_plot_count", sum(b["max_instances"] for b in buildings.values()) == 16)
    require("clock_order", 0 < cfg["clock"]["dawn_end_s"] < cfg["clock"]["day_end_s"] < cfg["clock"]["dusk_end_s"] < cfg["clock"]["cycle_s"])
    require("dinner_before_sleep", max(cfg["clock"]["meal_offsets_s"]) + cfg["clock"]["meal_grace_s"] == cfg["clock"]["dusk_end_s"])
    require("happiness_weights", sum(cfg["food"]["weights"].values()) == 100)
    lim = cfg["limits"]
    require("human_cap", lim["residents_per_city"] + lim["legion_capacity"] + lim["visitors_per_city"] + lim["intruders_per_city"] <= lim["agents_per_city"])
    require("display_budget", lim["visible_people"] == sorted(set(lim["visible_people"])) and max(lim["visible_people"]) <= lim["agents_per_city"])
    require("skill_thresholds", cfg["hero_progression"]["skill_xp_thresholds"] == [0,60,180,360,600])
    recruit_ids = [r["hero"] for r in cfg["recruitment"]]
    require("five_recruitment_paths", set(recruit_ids) == set(heroes) - {"xunyu"} and len(recruit_ids) == 5)
    recruit_expect = {"zhaoyun":(18600,130),"lusu":(26400,200),"liang":(54000,340),"guanyu":(34200,250),"zhangfei":(18000,180)}
    for path in cfg["recruitment"]:
        require("recruit_three_stages:" + path["hero"], len(path["stages"]) == 3)
        for stage in path["stages"]:
            material_check("recruit_material:" + path["hero"] + ":" + stage["id"], stage["materials_mU"])
            require("recruit_cost:" + path["hero"] + ":" + stage["id"], stage["cash"] > 0 and stage["passive_s"] > 0)
        vector("recruit_" + path["hero"], {"path":path["hero"]},
               [sum(s["passive_s"] for s in path["stages"]),sum(s["cash"] for s in path["stages"])], list(recruit_expect[path["hero"]]))
    for iid, item in {**weapons, **mounts}.items():
        material_check("unique_material:" + iid, item["materials_mU"])
        require("unique_quote:" + iid, item["cash"] > 0 and item["source_passive_s"] > 0)
    require("unique_disjoint", not(set(weapons) & set(mounts)) and not(set(heroes) & set(weapons)))
    require("collection_count", len(heroes)+len(weapons)+len(mounts)+1 == items["discovery_total"]["total"] == 17)
    require("no_animal_neglect_death", not cfg["pig"]["death_from_neglect"] and not cfg["pig"]["breeding_enabled"])
    require("no_thief_loss_or_coin", not cfg["security"]["loss_enabled"] and cfg["security"]["reward_currency"] == 0)
    for cid, expected in [("rice",7390),("millet",3745),("vegetable",2815),("grass",1900)]:
        c = crops[cid]
        vector("crop_" + cid, {"shift_wait":0,"transport_wait":0},
               c["sow_work_s"]+2*c["watering_work_s_each"]+c["mature_growth_s"]+c["harvest_work_s"], expected)
    vector("mill_32_paddy", {"paddy_mU":32000}, {k:v*8 for k,v in recipes["mill"]["outputs_mU"].items()}, {"grain":24000,"fodder":8000})
    basic = recipes["cook_basic"]
    vector("one_basic_batch", {"rate_bp":10000}, basic["prepare_work_s"]+basic["passive_s"]+basic["finish_work_s"], 135)
    vector("sixteen_residents_cycle", {"residents":16,"meals_per_cycle":2}, {k:v*2 for k,v in basic["inputs_mU"].items()}, {"grain":8000,"water":4000,"wood":2000})
    vector("sixteen_residents_meals", {}, sum(basic["outputs_mU"].values())*2, 32000)
    vector("xunyu_cook", {"rate_bp":10800}, ceil_div(basic["prepare_work_s"]*10000,10800)+basic["passive_s"]+ceil_div(basic["finish_work_s"]*10000,10800),130)
    vector("lusu_buy_ten_grain", {"units":10,"base_price":4,"fee":2}, ceil_div(10*resources["grain"]["buy"]*9200,10000)+2,39)
    vector("zhaoyun_wounded", {"base":5},ceil_div(5*items["commander_score"]["zhaoyun_wounded_multiplier_bp"],10000),4)
    vector("house_level_two", {}, [buildings["house"]["cash"]*2,buildings["house"]["work_s"]*4], [240,14400])
    vector("pig_growth_and_feed", {}, [cfg["pig"]["segments"]*cfg["pig"]["segment_growth_s"],cfg["pig"]["segments"]*cfg["pig"]["feed_mU_per_segment"]["grain"]], [17280,1500])
    vector("baseline_happiness_target", {}, (40*100+10*40+15*100+10*60+15*60+10*100)//100,84)
    vector("freight_available_at", {"load":10,"distance":960,"speed":32,"unload":10},10+ceil_div(960,32)+10,50)
    vector("food_floor_16", {}, cfg["food"]["reserve_cycles"]*cfg["food"]["meals_per_cycle"]*16,64)
    kitchen = {"grain":8000,"water":8000,"wood":4000,"meal_basic":32000}
    store = {"grain":56000,"water":24000,"wood":36000,"stone":12000,"iron":6000,"tools":4000,"fodder":8000}
    merged = dict(kitchen)
    for k,v in store.items(): merged[k] = merged.get(k,0)+v
    vector("initial_storage_split", {}, merged, cfg["initial"]["stocks_mU"])
    chapters = sorted((ROOT / "docs/life-v0.6").glob("[0-9][0-9]_*.md"))
    require("six_normative_chapters", len(chapters) == 6)
    docs = [ROOT / "docs/PRD.md", *chapters]
    for path in docs:
        text = path.read_text(encoding="utf-8")
        require("no_unresolved_parameter:" + path.name, not re.search(r"\bTODO\b|\bTBD\b|待定数值",text))
        for link in re.findall(r"\[[^\]]*\]\(([^)]+)\)",text):
            if re.match(r"https?://|#",link): continue
            target = (path.parent / link.split('#')[0]).resolve()
            require("link:" + path.name + ":" + link,target.exists())
    acceptance_text = (ROOT / "docs/life-v0.6/06_ACCEPTANCE_AND_DELIVERY.md").read_text(encoding="utf-8")
    cases = []
    for line in acceptance_text.splitlines():
        match = re.match(r"\|([A-G][0-9]{2})\|([^|]+)\|([^|]+)\|",line)
        if match:
            cases.append({"id":match[1],"given_when":match[2],"expected":match[3],"status":"NOT_RUN"})
    require("seventy_unique_application_cases",len(cases)==70 and len({c['id'] for c in cases})==70)
    require("all_application_cases_not_run",all(c['status']=='NOT_RUN' for c in cases))
    require("root_has_runtime_boundary","未在本次改成life-0.6" in docs[0].read_text(encoding="utf-8"))
    source_files = docs + [ROOT/'spec/life-v0.6.json', ROOT/'spec/collections-v0.6.json', Path(__file__).resolve()]
    failed = [x for x in CHECKS if x['status']=='FAIL']
    report = {"spec_version":"0.6.0","scope":"static_spec_and_arithmetic_only","checks":len(CHECKS),
              "passed":len(CHECKS)-len(failed),"failed":len(failed),"golden_vectors":len(VECTORS),
              "application_cases_planned":len(cases),"application_cases_executed":0,"game_runtime_tested":False,
              "m4_tested":False,"results":CHECKS,"sha256":{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files}}
    (out/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (out/'golden-vectors.json').write_text(json.dumps(VECTORS,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (out/'acceptance-plan.json').write_text(json.dumps(cases,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    combined = '\n\n---\n\n'.join(p.read_text(encoding='utf-8') for p in docs)
    (out/'PRD-v0.6-complete.md').write_text(combined,encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in {'results','sha256'}},ensure_ascii=False,indent=2))
    for f in failed: print('FAIL:',f['name'],f['detail'],file=sys.stderr)
    return 1 if failed else 0

if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError,ValueError,KeyError,TypeError) as exc:
        print(f'SPEC VALIDATION ERROR: {exc}',file=sys.stderr)
        raise SystemExit(2)
