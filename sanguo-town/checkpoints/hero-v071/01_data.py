#!/usr/bin/env python3
"""One-shot PRD data revision, not a game-save migration or game runtime."""
from pathlib import Path
import json
P=Path(__file__).resolve().parents[2]
def load(p):return json.loads((P/p).read_text())
def dump(p,v):(P/p).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
content=load('spec/content-v0.7.json');cfg=load('spec/life-v0.7.json');seed=load('spec/bootstrap-v0.7.json')
assert all(v['spec_version']=='0.7.0' for v in (content,cfg,seed)), 'requires untouched PRD 0.7.0'
attrs={'administration':'政治','strategy':'智力','valor':'武力','command':'统率'}
weights={
'farmer':{'administration':7000,'strategy':3000},'herder':{'administration':6000,'command':4000},
'butcher':{'valor':8000,'strategy':2000},'cook':{'administration':6000,'strategy':4000},
'server':{'administration':7000,'command':3000},'rationer':{'administration':5000,'command':5000},
'logger':{'valor':8000,'command':2000},'miner':{'valor':8000,'strategy':2000},
'carpenter':{'strategy':6000,'administration':4000},'smith':{'strategy':7000,'valor':3000},
'builder':{'command':5000,'administration':5000},'porter':{'command':6000,'valor':4000},
'clerk':{'administration':7000,'strategy':3000},'merchant':{'administration':6000,'strategy':4000},
'courier':{'command':6000,'strategy':4000},'guard':{'command':6000,'valor':4000},
'quartermaster':{'command':7000,'administration':3000},'groom':{'command':6000,'administration':4000},
'restorer':{'strategy':8000,'administration':2000},'handyman':{'administration':6000,'command':4000}}
metrics={
'work_rate_bp':{'event':'work_phase_start','cap':1200,'allowed_roles':['worker','prefect','governor']},
'purchase_discount_bp':{'event':'quote_created','cap':1000,'allowed_roles':['worker','prefect','governor']},
'patrol_speed_bp':{'event':'patrol_segment_start','cap':2000,'allowed_roles':['worker','prefect','governor']},
 'training_rate_bp':{'event':'training_phase_start','cap':1200,'allowed_roles':['commander']},
 'escort_score':{'event':'escort_departure','cap':10,'allowed_roles':['commander']},
 'wounded_reduction_bp':{'event':'escort_departure','cap':3000,'allowed_roles':['commander']},
 'happiness_rise_extra':{'event':'meal_window_open','cap':2,'allowed_roles':['prefect','governor']}}
skills=[]
def add(id,name,kind,metric,value,family,jobs=None,roles=None):
 m=metrics[metric];e={'metric':metric,'value':value,'event':m['event'],'roles':roles or m['allowed_roles'],'family':family}
 if jobs:e['jobs']=jobs
 if metric=='happiness_rise_extra':e['requires_coverage_bp']=9500
 skills.append({'id':id,'name':name,'kind':kind,'level':1,'activation':'automatic','effects':[e]})
for id,name,jobs in [('agriculture','农桑',['farmer']),('husbandry','畜养',['herder','butcher','groom']),('cookery','庖厨',['cook','server']),('carpentry','木作',['carpenter']),('metallurgy','冶铸',['smith']),('restoration','修复',['restorer']),('construction','营造',['builder']),('rationcraft','制粮',['rationer','quartermaster']),('gathering','力作',['logger','miner']),('logistics','转运',['porter','courier','clerk'])]:add(id,name,'common','work_rate_bp',400,id,jobs)
add('commerce','通商','common','purchase_discount_bp',500,'bargaining')
add('appeasement','安抚','common','happiness_rise_extra',1,'appeasement')
add('drill','练兵','common','training_rate_bp',500,'training')
add('patrol','巡检','common','patrol_speed_bp',800,'patrol')
add('escort','护送','common','escort_score',4,'escort')
add('rearguard','保全','common','wounded_reduction_bp',1000,'preservation')
add('kings_counsel','王佐之才','signature','work_rate_bp',600,'statecraft',['cook','rationer','clerk'],['prefect','governor'])
add('dragon_courage','一身是胆','signature','wounded_reduction_bp',2000,'preservation')
add('diplomatic_plan','榻上筹策','signature','work_rate_bp',600,'coordination',['porter','courier','merchant','clerk'],['prefect','governor'])
add('sleeping_dragon','卧龙筹策','signature','work_rate_bp',800,'engineering',['builder','restorer'],['prefect','governor'])
add('martial_sage','武圣','signature','escort_score',6,'breakthrough')
add('thunder_roar','燕人咆哮','signature','training_rate_bp',800,'training')
lib={'spec_version':'0.7.1','status':'design_and_reference_resolver_not_game_integration','attribute_labels':attrs,'attribute_range':[0,100],
'hero_skill_count':[1,5],'ordinary_skill_count':[0,2],'signature_limit':1,'skill_levels':1,'job_weights_bp':weights,
'appointment_weights_bp':{'prefect':{'administration':5000,'strategy':3000,'command':2000},'governor':{'command':4000,'administration':4000,'strategy':2000},'commander':{'command':6000,'valor':3000,'strategy':1000}},
'rates':{'baseline':50,'worker_bp_per_point':20,'worker_attribute_cap':1000,'leader_bp_per_point':10,'leader_attribute_cap':500,'governor_scale_bp':5000,'job_xp_bp_per_level':100,'job_level_max':5,'work_ability_cap':1200,'work_total_min':8000,'work_total_max':14000,'purchase_attribute_bp_per_point':10,'purchase_total_cap':1000},
'metrics':metrics,'stacking':'filter role/event/jobs, scale governor then max per metric+family across holders; sum families then cap; same personID never repeated in source list','skills':skills,
'feature_flags':{'skill_learning':False,'skill_reroll':False,'skill_consumables':False,'manual_casting':False,'tactical_battle_skill_timeline':False},
'migration':{'source_attributes':{'administration':'administration','strategy':'strategy','valor':'valor','command':'command'},'charisma':'preserve under legacyAttributes only; not converted or summed','removed_seven_star_bonus':'charisma+3 -> administration+3 for new rules only','retroactive_task_recalculation':False,'runtime_base_unchanged':True}}
lib['policy_fit_job_weights_bp']={
'supply':{'farmer':3000,'cook':3000,'server':1000,'herder':1000,'porter':1000,'handyman':1000},
'trade':{'merchant':3500,'porter':2500,'courier':2000,'cook':1000,'clerk':1000},
'industry':{'builder':2000,'carpenter':2500,'smith':2500,'miner':1500,'porter':1500},
'military':{'rationer':3000,'quartermaster':2000,'guard':2000,'porter':1500,'smith':1500},
'balanced':{'farmer':1500,'cook':2000,'builder':2000,'porter':2000,'smith':1000,'merchant':1500}}
lib['policy_fit_max_bonus']=10;lib['policy_fit_normalizer_bp']=1700
for s in skills:s['category']='tactic' if s['effects'][0]['metric'] in ['escort_score','wounded_reduction_bp'] else 'specialty'
assignments={'xunyu':['agriculture','cookery','appeasement','kings_counsel'],'zhaoyun':['patrol','drill','escort','dragon_courage'],'lusu':['commerce','logistics','diplomatic_plan'],'liang':['construction','metallurgy','restoration','logistics','sleeping_dragon'],'guanyu':['rationcraft','drill','escort','martial_sage'],'zhangfei':['gathering','construction','escort','thunder_roar']}
for h in content['heroes']:
 h['attributes'].pop('charisma');h.pop('prefect');h.pop('commander');h['skill_ids']=assignments[h['id']]
for w in content['weapons']:
 if 'charisma' in w['attributes']:w['attributes']['administration']=w['attributes'].pop('charisma')
content['hero_system']='hero-system-v0.7.json';cfg['hero_system']='hero-system-v0.7.json'
for j in cfg['jobs']:j.pop('attribute');j['attribute_weights_bp']=weights[j['id']]
cfg['rates'].pop('city_trait_bp_cap');cfg['rates']['leader_attribute_bp_cap']=500;cfg['rates']['ability_work_bp_cap']=1200
cfg['governance'].pop('policy_fit');cfg['governance']['policy_fit_method']='weighted_job_effects_from_hero_system'
seed['ordinary_defaults']['attributes'].pop('charisma');seed['ordinary_defaults']['skill_ids']=[]
for p,v in [('spec/content-v0.7.json',content),('spec/life-v0.7.json',cfg),('spec/bootstrap-v0.7.json',seed)]:v['spec_version']='0.7.1';dump(p,v)
dump('spec/hero-system-v0.7.json',lib)
print('Generated four-attribute profiles and 22 reusable skills; no runtime sources touched.')
