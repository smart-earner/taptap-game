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
 training_rate_bp':{}}
