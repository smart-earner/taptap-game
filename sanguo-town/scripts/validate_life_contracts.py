#!/usr/bin/env python3
"""Cross-chapter specification checks, not application tests."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def main()->int:
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',default=str(ROOT/'dist/life-spec'))
    args=p.parse_args();out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
    cfg=json.loads((ROOT/'spec/life-v0.6.json').read_text())
    c=json.loads((ROOT/'spec/life-contracts-v0.6.json').read_text())
    items=json.loads((ROOT/'spec/collections-v0.6.json').read_text())
    rows=[]
    def check(name,ok):rows.append({'name':name,'status':'PASS' if ok else 'FAIL'})
    check('version',cfg['spec_version']==c['spec_version']==items['spec_version']=='0.6.0')
    check('design_only',c['status']=='design_contract_not_runtime_implementation')
    r={x['id']:x for x in cfg['resources']}
    for crop in cfg['crops']:
        volume=sum(q*r[k]['volume_milli']//1000 for k,q in crop['outputs_mU'].items())
        check('crop_buffer:'+crop['id'],volume<=c['buffers']['crop_bed_output_volume_mU'])
    for source in cfg['sources']:
        volume=source['quantity_mU']*r[source['output']]['volume_milli']//1000
        check('source_buffer:'+source['id'],volume<=c['buffers']['source_output_volume_mU'])
    for recipe in cfg['recipes']:
        vi=sum(q*r[k]['volume_milli']//1000 for k,q in recipe['inputs_mU'].items())
        vo=sum(q*r[k]['volume_milli']//1000 for k,q in recipe['outputs_mU'].items())
        check('recipe_input_buffer:'+recipe['id'],vi<=c['buffers']['station_input_volume_mU'])
        check('recipe_output_buffer:'+recipe['id'],vo<=c['buffers']['station_output_volume_mU'])
    check('city_trait_cap',c['attributes']['max_city_trait_bp']==cfg['hero_progression']['city_trait_cap_bp'])
    check('total_rate_cap',c['attributes']['max_total_rate_bp']==cfg['hero_progression']['total_rate_cap_bp'])
    check('base_well_capacity',c['civic_modifiers']['well_slots_by_water_level'][0]==cfg['sources'][0]['slots'])
    check('no_idle_rewards',c['idle_life']['resource_delta']==c['idle_life']['xp_delta']==0)
    check('no_fake_idle_agent',c['idle_life']['requires_real_agent'] and not c['idle_life']['override_production'])
    check('no_implicit_tax_salary',not c['prices']['resident_tax_enabled'] and not c['prices']['salary_enabled'])
    check('no_undefined_extensions',not any(c['feature_flags'].values()))
    check('no_academy_double_xp',c['civic_modifiers']['academy_extra_xp']==0)
    def fnv(seed:int,city:str,cycle:int)->int:
        value=int(c['random']['offset_basis_decimal']);prime=int(c['random']['prime_decimal'])
        for byte in f'{seed}:{city}:{cycle}'.encode('utf-8'):
            value=((value^byte)*prime)&((1<<64)-1)
        return value
    check('deterministic_seed_vector_0',fnv(20260920,'plain',0)==2070784952295781526)
    check('deterministic_seed_vector_10',fnv(20260920,'plain',10)==11922799572503056283)
    check('first_night_no_forced_intruder',fnv(20260920,'plain',0)%100==26)
    # Physical production: paddy -> grain -> meals has identical staple equivalence.
    check('rice_staple_equivalence',32*cfg['food']['paddy_to_meal_factor']==24*cfg['food']['raw_grain_to_meal_factor']==96)
    check('basic_recipe_equivalence',4*cfg['food']['raw_grain_to_meal_factor']==16)
    check('outgoing_not_double_counted','excluded_from_source' in c['ownership']['outgoing_cargo'])
    check('incoming_not_ready','not_ready_food' in c['ownership']['incoming_cargo'])
    check('planner_tie_breaker_explicit',len(c['construction_selection']['tie_breaker'])==4)
    check('planner_default_explicit',bool(c['construction_selection']['no_matching_candidate']))
    report={'spec_version':'0.6.0','scope':'static_contract_checks_not_game_runtime','checks':len(rows),
            'passed':sum(x['status']=='PASS' for x in rows),'failed':sum(x['status']=='FAIL' for x in rows),
            'application_cases_executed':0,'results':rows,
            'config_sha256':hashlib.sha256((ROOT/'spec/life-contracts-v0.6.json').read_bytes()).hexdigest()}
    (out/'contract-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='results'},ensure_ascii=False,indent=2))
    return int(report['failed']!=0)
if __name__=='__main__':raise SystemExit(main())
