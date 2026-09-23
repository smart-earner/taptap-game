#!/usr/bin/env python3
"""Static checks for the v0.10 growth delta; never reports engine acceptance."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "spec" / "hero-town-v0.9.json"
DELTA = ROOT / "spec" / "hero-town-v0.10-growth-delta.json"
OUTPUT = ROOT / "dist" / "prd-v10-growth" / "validation.json"


def main() -> int:
    delta = json.loads(DELTA.read_text())
    rows = []

    def check(name, value):
        rows.append({"name": name, "passed": bool(value)})

    base_hash = hashlib.sha256(BASE.read_bytes()).hexdigest()
    check("base spec hash", delta["base_spec_sha256"] == base_hash)
    check(
        "target versions",
        (
            delta["target_rules_version"],
            delta["target_save_format"],
            delta["target_layout_version"],
        )
        == ("hero-town-0.10.0", 5, 7),
    )
    check(
        "player actions unchanged",
        set(delta["principles"]["player_actions_unchanged"])
        == {"recruit_draw", "star_up", "disassemble_cards", "exchange_souls"},
    )
    check("no ordinary residents", delta["principles"]["ordinary_residents"] is False)

    pacing = delta["pacing"]
    check(
        "two-times default presentation",
        pacing["default_presentation_speed"] == 2
        and pacing["presentation_speed_options"] == [0, 1, 2, 6, 30],
    )
    check(
        "bounded resource pacing bonus",
        pacing["formal_resource_job_bonus_bp"] == 1500
        and set(pacing["resource_jobs"]) == {"farmer", "logger", "miner"}
        and pacing["resource_bonus_changes_work_seconds_not_output_yield"] is True
        and pacing["free_resource_grants"] is False,
    )
    check(
        "visible foundation precedes civics",
        pacing["early_visible_build_order"][:4]
        == ["house-2", "farm-2", "granary-2", "workshop-1"]
        and pacing["protected_builder_when_food_coverage_bp_at_least"] == 9500
        and pacing["protected_builder_is_permanent_assignment"] is False,
    )

    population = delta["population"]
    breakthroughs = population["breakthroughs"]
    check("population endpoints", population["initial_resident_hard_cap"] == 30 and population["maximum_resident_hard_cap"] == 60)
    check("three breakthroughs", len(breakthroughs) == 3)
    check(
        "continuous caps",
        [(item["from_cap"], item["to_cap"]) for item in breakthroughs]
        == [(30, 40), (40, 50), (50, 60)],
    )
    check("automatic breakthroughs", all(item["automatic"] for item in breakthroughs))
    check(
        "positive breakthrough costs",
        all(
            item["work_s"] > 0
            and set(item["cost_mU"]) == {"wood", "stone", "tools"}
            and all(value > 0 for value in item["cost_mU"].values())
            for item in breakthroughs
        ),
    )
    admission = population["admission_policy"]
    check("stable admission order", admission["order"] == ["paidAt", "heroID"])
    check(
        "legal residence admission",
        admission["conditions"].get("legal_residence_reservation_available") is True
        and "reserved_bed_available" not in admission["conditions"],
    )
    check(
        "waiting is not hidden labor",
        admission["waiting_state"] == "WAITING_RESIDENCY"
        and admission["waiting_heroes_consume_city_food"] is False
        and admission["waiting_heroes_can_work"] is False
        and admission["waiting_heroes_can_be_cultivated"] is True,
    )

    housing = delta["housing_and_households"]
    map_rows = housing["parcel_category_rows_top_to_bottom"]
    flat = "".join(map_rows)
    codes = housing["parcel_category_codes"]
    allocation = housing["final_parcel_allocation"]
    check("84 mapped standard parcels", len(map_rows) == 7 and all(len(row) == 12 for row in map_rows) and len(flat) == 84)
    check(
        "fixed parcel allocation",
        set(flat) == set(codes)
        and all(flat.count(code) == allocation[category] for code, category in codes.items())
        and sum(allocation.values()) == 84,
    )
    road_parcels = {(x, y) for y, row in enumerate(map_rows) for x, code in enumerate(row) if code == "I"}
    reached = set()
    if road_parcels:
        frontier = [min(road_parcels)]
        while frontier:
            x, y = frontier.pop()
            if (x, y) in reached:
                continue
            reached.add((x, y))
            frontier.extend((nx, ny) for nx, ny in ((x-1, y), (x+1, y), (x, y-1), (x, y+1)) if (nx, ny) in road_parcels and (nx, ny) not in reached)
    check("connected infrastructure corridor", reached == road_parcels)
    stage_grids = [(8, 5, 8), (10, 5, 10), (10, 6, 13), (12, 7, 15)]
    check(
        "staged residential permits",
        all(sum(row[:columns].count("H") for row in map_rows[:height]) == permits for columns, height, permits in stage_grids)
        and housing["initial_unlocked_grid"] == {"columns": 8, "rows": 5, "parcel_count": 40, "residential_courtyard_permits": 8}
        and housing["final_grid"] == {"columns": 12, "rows": 7, "parcel_count": 84},
    )
    levels = housing["levels"]
    check(
        "courtyard capacities support sixty single heroes",
        [(level["level"], level["household_units"], level["resident_capacity"]) for level in levels]
        == [(1, 2, 4), (2, 3, 6), (3, 4, 8)]
        and housing["residential_courtyard_plot_count"] == 15
        and 15 * levels[-1]["household_units"] == housing["hero_resident_hard_cap"] == 60
        and 15 * levels[-1]["resident_capacity"] == housing["future_family_resident_capacity"] == 120,
    )
    check(
        "breakthrough grid and capacity gates",
        all(
            item["prerequisites"].get("formal_household_units_at_least") == item["from_cap"]
            and item["prerequisites"].get("formal_resident_capacity_at_least") == item["from_cap"]
            and item["effects"]["unlock_house_plots"] == permits - stage_grids[index][2]
            and (item["effects"]["unlocked_grid_columns"], item["effects"]["unlocked_grid_rows"], item["effects"]["unlocked_parcel_count"])
            == (columns, height, columns * height)
            for index, (item, (columns, height, permits)) in enumerate(zip(breakthroughs, stage_grids[1:]))
        ),
    )
    check(
        "family system remains reserved",
        housing["romance_and_birth_runtime_enabled"] is False
        and delta["principles"]["family_residents_runtime_enabled"] is False
        and housing["vacant_capacity_creates_residents"] is False
        and housing["formal_admission_requires_free_household_unit_and_person_capacity"] is True
        and housing["guest_admission_requires_real_tavern_guest_bed"] is True,
    )

    pool = delta["gacha_pool_extension"]
    check("sixty unique target", pool["unique_hero_count"] == 60 and pool["new_hero_record_count"] == 30)
    check("new rarity total", sum(pool["new_rarity_counts"].values()) == 30)
    check("full rarity total", sum(pool["total_rarity_counts"].values()) == 60)
    check("rarity probability total", sum(pool["rarity_probability_bp_unchanged"].values()) == 10000)
    check("pity unchanged", pool["pity_threshold_unchanged"] == 20)

    happiness = delta["happiness"]
    dimensions = happiness["dimensions"]
    check("seven happiness dimensions", len(dimensions) == 7 and len({item["id"] for item in dimensions}) == 7)
    check("happiness weights", sum(item["weight_bp"] for item in dimensions) == 10000)
    check("per resident happiness", happiness["scope"] == "per_resident_hero" and happiness["range"] == [0, 100])
    bands = happiness["work_rate_modifier_bp"]
    covered_happiness = []
    for band in bands:
        covered_happiness.extend(range(band["min"], band["max"] + 1))
    check("work bands cover 0..100 once", sorted(covered_happiness) == list(range(101)) and len(covered_happiness) == 101)
    check("recovery floor", happiness["negative_modifier_floor_bp_for_recovery_jobs"] == 0 and bool(happiness["recovery_jobs"]))

    shortage = delta["food_shortage"]
    covered_coverage = []
    for tier in shortage["tiers"]:
        covered_coverage.extend(range(tier["min_bp"], tier["max_bp"] + 1))
    check("food tiers cover 0..10000 once", sorted(covered_coverage) == list(range(10001)) and len(covered_coverage) == 10001)
    check(
        "no double hunger penalty",
        shortage["efficiency_penalty_channel"] == "happiness_only"
        and shortage["additional_hunger_work_rate_penalty"] is False,
    )
    check("no irreversible hunger outcomes", not any(shortage["irreversible_outcomes"].values()))

    health = delta["health_and_clinic"]
    clinic = health["building"]
    check(
        "clinic quote",
        clinic["id"] == "clinic"
        and clinic["max"] == 1
        and clinic["cash"] == 0
        and clinic["work_s"] == 2400
        and clinic["materials_mU"] == {"wood": 12000, "stone": 6000, "tools": 1000},
    )
    check("clinic beds", clinic["treatment_beds_by_level"] == [2, 4, 6])
    check("physician weights", sum(health["physician_job"]["attribute_weights_bp"].values()) == 10000)
    conditions = health["conditions"]
    check("two bounded health conditions", {item["id"] for item in conditions} == {"overwork_strain", "minor_work_injury"} and health["condition_limit_per_hero"] == 1)
    check(
        "positive treatment and recovery time",
        all(
            item["home_recovery_continuous_rest_s"] > 0
            and all(value > 0 for value in item["clinic_treatment"].values())
            for item in conditions
        ),
    )
    check("no new medicine resource", health["treatment_consumes_new_resource"] is False)
    check("no irreversible health outcomes", not any(health["irreversible_outcomes"].values()))

    migration = delta["migration"]
    check("format migration", (migration["from_save_format"], migration["to_save_format"]) == (4, 5))
    check("layout migration", migration["new_layout_expansion_required_for_cap_above_30"] is True)
    check(
        "legacy occupants survive migration",
        migration["existing_formal_residents_get_stable_single_person_households"] is True
        and migration["excess_legacy_house_occupants_get_nontransferable_occupied_leases"] is True
        and migration["legacy_occupied_leases_can_admit_new_heroes"] is False
        and migration["legacy_occupied_lease_retires_on_atomic_courtyard_move"] is True
        and migration["migration_creates_spouses_or_children"] is False,
    )
    check("acceptance ids", delta["acceptance_cases"] == [f"GC{i}_{suffix}" for i, suffix in [
        (29, "population_cap_and_safe_admission"),
        (30, "three_breakthrough_projects_and_idempotence"),
        (31, "pool_v2_60_unique_and_waiting_residency"),
        (32, "per_hero_happiness_dimensions_and_work_rate"),
        (33, "food_shortage_tiers_and_recovery_protection"),
        (34, "30_40_50_60_population_long_run"),
        (35, "clinic_conditions_treatment_and_recovery"),
        (36, "shared_courtyards_households_and_84_parcels"),
    ]])

    required_docs = [
        ROOT / "docs" / "PRD-v0.10-growth.md",
        ROOT / "docs" / "systems" / "01_TAVERN_GACHA.md",
        ROOT / "docs" / "systems" / "02_HERO_CULTIVATION.md",
        ROOT / "docs" / "systems" / "04_GOVERNOR_LOGISTICS.md",
        ROOT / "docs" / "systems" / "05_FOOD_LIFE.md",
        ROOT / "docs" / "systems" / "06_CITY_PROGRESSION.md",
        ROOT / "docs" / "systems" / "07_PRESENTATION.md",
        ROOT / "docs" / "systems" / "08_ENGINEERING_ACCEPTANCE.md",
    ]
    for path in required_docs:
        check(f"document/{path.name}", path.exists() and "v0.10" in path.read_text())

    delta_doc = ROOT / "docs" / "PRD-v0.10-growth.md"
    for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", delta_doc.read_text()):
        path_text, _, anchor = target.partition("#")
        linked = delta_doc.parent / path_text
        valid = linked.exists()
        if valid and anchor:
            valid = f'id="{anchor}"' in linked.read_text()
        check(f"link/{target}", valid)

    failed = [row for row in rows if not row["passed"]]
    report = {
        "scope": "static_contract_only",
        "status": "STATIC_FAIL" if failed else "STATIC_PASS",
        "base_spec_sha256": base_hash,
        "delta_spec_sha256": hashlib.sha256(DELTA.read_bytes()).hexdigest(),
        "passed": len(rows) - len(failed),
        "failed": len(failed),
        "application_cases_executed": 0,
        "engine_tested": False,
        "runtime_cases": [{"caseID": f"GC{i:02}", "status": "NOT_RUN"} for i in range(29, 37)],
        "checks": rows,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: report[key] for key in ["scope", "status", "passed", "failed", "application_cases_executed"]}, ensure_ascii=False))
    for row in failed:
        print("FAIL", row["name"])
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
