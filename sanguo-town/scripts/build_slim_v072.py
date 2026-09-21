#!/usr/bin/env python3
"""Resolve a smaller design release. This never opens or migrates a player's save."""
from __future__ import annotations
import argparse, copy, hashlib, json
from collections import Counter
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MAP_FIELDS={'input_mU','output_mU','materials_mU','materials_per_level_mU','stocks_mU','stock_mU','feed_mU','construction_consumes_mU','handover_stocks_mU'}
def read(path):
    return json.loads(path.read_text(encoding='utf-8'))
def write(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def material_map(values,contract):
    """The mapping revises *design quotes*, not existing inventories or active orders."""
    known={r['id'] for r in contract['resources']}; rules=contract['price_rewrite_design_only']; result=Counter()
    for key,q in values.items():
        if type(q) is not int or q<0: raise ValueError('invalid material amount')
        if key in known: result[key]+=q
        elif key in rules:
            rule=rules[key]
            if rule is not None:
                result[rule['target']]+=(q*rule['numerator']+rule['denominator']-1)//rule['denominator']
        else: raise ValueError('unmapped resource: '+key)
    return {k:v for k,v in result.items() if v}
def transform(data,contract):
    if isinstance(data,list): return [transform(v,contract) for v in data]
    if not isinstance(data,dict): return data
    return {k:material_map(v,contract) if k in MAP_FIELDS and isinstance(v,dict) else transform(v,contract) for k,v in data.items()}
def resolve(root=ROOT):
    contract=read(root/'spec/slim-v0.7.2.json'); roster=read(root/'spec/heroes-v0.7.2.json')
    base={}
    for name,checksum in contract['base_sha256'].items():
        path=root/'spec'/name
        if hashlib.sha256(path.read_bytes()).hexdigest()!=checksum: raise ValueError('base changed; review required: '+name)
        base[name]=read(path)
    life=transform(copy.deepcopy(base['life-v0.7.json']),contract)
    content=transform(copy.deepcopy(base['content-v0.7.json']),contract)
    seed=transform(copy.deepcopy(base['bootstrap-v0.7.json']),contract)
    skills=copy.deepcopy(base['hero-system-v0.7.json'])
    for item in [life,content,seed,skills]: item['spec_version']='0.7.2'
    life['rules_version']='life-0.7.2';life['schema_version']=7
    life['hero_system']='hero-system.json';content['hero_system']='hero-system.json'
    life['status']='resolved_design_not_runtime_save'
    life['resources']=copy.deepcopy(contract['resources']);life['recipes']=copy.deepcopy(contract['recipes']);life['crops']=copy.deepcopy(contract['crops'])
    life['sources']=[s for s in life['sources'] if s['id']!='well']
    for s in life['sources']:
        if s['id']=='mine': s.update(resource='iron',quantity_mU=2000,work_s=300)
    life['services']=copy.deepcopy(contract['services'])
    life['water_service_slots_by_level']=life['civic'].pop('well_slots_by_level')
    life['extensions']=[e for e in life['extensions'] if e['id']!='emergency_well_slot']
    life['pig'].update(copy.deepcopy(contract['pig']))
    life['food'].pop('paddy_equivalence',None)
    life['food']['quality']={'basic':40,'hearty':100,'rations':30}
    life['food']['menus_bp']={k:{'hearty':v} for k,v in contract['food']['hearty_target_bp'].items()}
    life['food']['grain_equivalence']=4
    life['food']['quality_is_meal_lot_metadata']=True
    life['economy']['visitor_prices']={'basic':2,'hearty':4}
    life['workshop_station_ids']=['carpentry','forge','restorer']
    # No extra grain is granted in a fresh game in compensation for removed grass/water.
    initial=base['life-v0.7.json']['initial']['stocks_mU']
    life['initial']['stocks_mU']={k:v for k,v in initial.items() if k in {'grain','wood','stone','iron','tools'}}
    life['initial']['stocks_mU']['meal']=initial['meal_basic']
    for original,location in zip(base['bootstrap-v0.7.json']['locations'],seed['locations']):
        original_stock=original['stock_mU']
        location['stock_mU']={k:v for k,v in original_stock.items() if k in {'grain','meat','rations','wood','stone','iron','tools'}}
        if original_stock.get('meal_basic'):
            location['stock_mU']['meal']=original_stock['meal_basic']
            location['lot_metadata']={'meal':{'quality':'basic'}}
    life['initial']['meal_quality']='basic';seed['initial_food_allocation']['quality']='basic'
    content['heroes']=copy.deepcopy(roster['heroes']); content['recruitment']=[]
    for h in roster['heroes']:
        if h['starting']: continue
        profile=roster['standard_recruitment_profiles'][h['recruitment_profile']]
        route={'hero':h['id'],'unlock':copy.deepcopy(profile['unlock'])+[['population','>=',h['minimum_population']]],'stages':[]}
        for index in range(3):
            route['stages'].append({'name':['接待','共事','邀留'][index],'passive_s':profile['wait_s'][index],'cash':profile['cash'][index],'materials_mU':copy.deepcopy(profile['materials_mU'][index])})
        content['recruitment'].append(route)
    content['mount_care']=copy.deepcopy(contract['mount_care'])
    content['recruitment_rules']=copy.deepcopy(roster['recruitment_rules'])
    # An idle furnace is not a reward once ore and smelting have been removed.
    for path in content['landmarks']:
        if path['id']=='industry':
            path['stages'][1]['name']='锻造棚'
            path['stages'][1]['effects']={'first_workshop_forge_slots_once':1}
            path['stages'][2]['effects']={'first_workshop_restorer_slots_once':1}
    life['resolved_build_contract']={'source_spec':'slim-v0.7.2.json','runtime_migration_enabled':False,'recruitment_catalog_size':30,'ability_library_size':22,'ability_primitive_count':7}
    return {'life':life,'content':content,'bootstrap':seed,'hero-system':skills}
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',default='dist/slim-v072');a=p.parse_args()
    out=Path(a.output);result=resolve()
    for name,data in result.items(): write(out/'resolved'/(name+'.json'),data)
    write(out/'manifest.json',{'spec_version':'0.7.2','scope':'generated_design_configuration_only','swift_runtime_changed':False,'player_save_migrated':False,'resources':8,'heroes':30,'recipes':4,'crops':2,'skills':22,'sha256':{name:hashlib.sha256((out/'resolved'/(name+'.json')).read_bytes()).hexdigest() for name in result}})
    print(json.dumps({'resources':8,'heroes':30,'recipes':4,'crops':2,'skills':22,'runtime_changed':False}))
if __name__=='__main__': main()
