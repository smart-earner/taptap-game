#!/usr/bin/env python3
"""Validate data-driven hero contracts and reference arithmetic, not the game."""
from __future__ import annotations
import argparse, ast, copy, json, unittest
from pathlib import Path
from hero_reference_v071 import Source, aptitude, ceildiv, resolve, work_rate, purchase_price, escort_score, validate, recommendation, training_rate
ROOT=Path(__file__).resolve().parents[1]
LIB=json.loads((ROOT/'spec/hero-system-v0.7.json').read_text())
CONTENT=json.loads((ROOT/'spec/content-v0.7.json').read_text())
CFG=json.loads((ROOT/'spec/life-v0.7.json').read_text())
H={h['id']:h for h in CONTENT['heroes']}
BASIC={'id':'ordinary-worker','attributes':dict.fromkeys(LIB['attribute_labels'],50),'skill_ids':[]}
def clone(h,name):
 p=copy.deepcopy(h);p['id']=name;p['name']='新配置武将';return p

class ContractTests(unittest.TestCase):
 def test_catalog(self):
  validate(LIB,CONTENT,CFG)
  self.assertEqual(len(LIB['skills']),22)
  self.assertEqual(sum(s['kind']=='common' for s in LIB['skills']),16)
  self.assertEqual([len(h['skill_ids']) for h in CONTENT['heroes']],[4,4,3,5,4,4])
  self.assertEqual({LIB['spec_version'],CONTENT['spec_version'],CFG['spec_version']},{'0.7.1'})
 def test_all_jobs_weighted(self):
  for job in CFG['jobs']:
   self.assertEqual(aptitude(BASIC['attributes'],job['attribute_weights_bp']),50)
   self.assertEqual(work_rate(LIB,BASIC,job['id']),10000)
 def test_high_attributes_without_named_traits(self):
  p=clone(BASIC,'unknown-hero');p['attributes']['valor']=100;p['skill_ids']=['gathering']
  self.assertEqual(work_rate(LIB,p,'miner'),11200)
  self.assertEqual(work_rate(LIB,p,'farmer'),10000)
 def test_cooking_unchanged_passive_and_yield(self):
  rate=work_rate(LIB,BASIC,'cook',leaders=[Source(H['xunyu'],'prefect',True)])
  self.assertEqual(rate,11410)
  r=next(x for x in CFG['recipes'] if x['id']=='cook_basic')
  self.assertEqual(ceildiv(r['prepare_s']*10000,rate)+r['passive_s']+ceildiv(r['finish_s']*10000,rate),127)
  self.assertEqual(r['output_mU'],{'meal_basic':16000})
  self.assertEqual(next(x for x in CFG['crops'] if x['id']=='rice')['mature_s'],7200)
 def test_same_name_no_magic(self):
  p=clone(H['xunyu'],'not-a-known-name')
  self.assertEqual(work_rate(LIB,BASIC,'cook',leaders=[Source(p,'prefect',True)]),11410)
  p['skill_ids']=[]
  rate=work_rate(LIB,BASIC,'cook',leaders=[Source(p,'prefect',True)])
  self.assertEqual(rate,10410)
  self.assertEqual(ceildiv(600000,rate)+60+ceildiv(150000,rate),133)
 def test_ineligible_and_out_of_scope(self):
  self.assertEqual(work_rate(LIB,BASIC,'cook',leaders=[Source(H['xunyu'],'prefect',False)]),10000)
  self.assertEqual(resolve(LIB,[Source(H['xunyu'],'worker',True)],'work_rate_bp',job='miner'),0)
  self.assertEqual(resolve(LIB,[Source(H['guanyu'],'governor',True)],'escort_score'),0)
  self.assertEqual(resolve(LIB,[Source(H['xunyu'],'prefect',True)],'work_rate_bp',job='cook',event='passive_growth'),0)
 def test_duplicates_and_scope_rejected(self):
  with self.assertRaises(ValueError): resolve(LIB,[Source(H['xunyu'],'prefect',True),Source(H['xunyu'],'governor',True)],'work_rate_bp',job='cook')
  with self.assertRaises(ValueError):resolve(LIB,[Source(H['xunyu'],'prefect',True),Source(H['lusu'],'prefect',True)],'work_rate_bp',job='cook')
 def test_max_family_then_sum(self):
  p=clone(BASIC,'farmer');p['skill_ids']=['agriculture']
  g=clone(H['xunyu'],'governor-test')
  sources=[Source(p,'worker',True),Source(H['xunyu'],'prefect',True),Source(g,'governor',True)]
  self.assertEqual(resolve(LIB,sources,'work_rate_bp',job='farmer'),400)
  self.assertEqual(resolve(LIB,[Source(H['xunyu'],'governor',True)],'work_rate_bp',job='cook'),500)
 def test_rate_caps(self):
  lib=copy.deepcopy(LIB)
  for s in lib['skills']:
   for e in s['effects']:
    if e['metric']=='work_rate_bp':e['value']=1200
  self.assertEqual(resolve(lib,[Source(H['liang'],'prefect',True)],'work_rate_bp',job='builder'),1200)
  self.assertEqual(work_rate(LIB,BASIC,'cook',facility_bp=5000),14000)
  self.assertEqual(work_rate(LIB,BASIC,'cook',penalty_bp=5000),8000)
 def test_discount(self):
  s=[Source(H['lusu'],'prefect',True)]
  self.assertEqual(purchase_price(LIB,40,2,s),39)
  self.assertEqual(purchase_price(LIB,40,2,s,regional_bp=500),39)
  p=clone(H['lusu'],'no-commerce');p['skill_ids']=[]
  self.assertEqual(purchase_price(LIB,40,2,[Source(p,'prefect',True)]),41)
  self.assertEqual(purchase_price(LIB,40,2,[]),42)
 def test_escort_no_identity_branch(self):
  self.assertEqual(escort_score(LIB,H['zhaoyun'],30,1,1),63)
  self.assertEqual(escort_score(LIB,H['guanyu'],30,1,1),69)
  for h in H.values():self.assertEqual(escort_score(LIB,h,30,1,1),escort_score(LIB,clone(h,'new-person-id'),30,1,1))
 def test_wounded_family(self):
  p=clone(H['zhaoyun'],'test2');p['skill_ids'].append('rearguard')
  r=resolve(LIB,[Source(p,'commander',True)],'wounded_reduction_bp')
  self.assertEqual(r,2000);self.assertEqual(ceildiv(5*(10000-r),10000),4)
 def test_training_general(self):
  self.assertEqual(training_rate(LIB,H['zhaoyun']),11340)
  self.assertEqual(training_rate(LIB,clone(H['zhangfei'],'renamed')),training_rate(LIB,H['zhangfei']))
  self.assertEqual(resolve(LIB,[Source(H['zhangfei'],'prefect',True)],'training_rate_bp'),0)
 def test_happiness_never_fakes_coverage(self):
  s=[Source(H['xunyu'],'prefect',True)]
  self.assertEqual(resolve(LIB,s,'happiness_rise_extra',coverage_bp=9400),0)
  self.assertEqual(resolve(LIB,s,'happiness_rise_extra',coverage_bp=9500),1)
  self.assertEqual(resolve(LIB,[Source(H['xunyu'],'governor',True)],'happiness_rise_extra',coverage_bp=10000),0)
 def test_recommendation_not_named_preferences(self):
  self.assertNotIn('policy_fit',CFG['governance'])
  for h in H.values():
   for policy,w in LIB['policy_fit_job_weights_bp'].items():
    self.assertEqual(sum(w.values()),10000)
    self.assertEqual(recommendation(LIB,h,policy),recommendation(LIB,clone(h,'other'),policy))
 def test_snapshot_is_value_not_live_definition(self):
  p=clone(H['guanyu'],'governor-snapshot');before=escort_score(LIB,p,30,1,1)
  snapshot=json.loads(json.dumps({'score':before,'definitionVersion':LIB['spec_version']}))
  p['skill_ids']=[]
  self.assertEqual(escort_score(LIB,p,30,1,1),59);self.assertEqual(snapshot['score'],69)
 def test_bad_configs_fail(self):
  mutations=[lambda c:c['heroes'][0].update(skill_ids=[]),lambda c:c['heroes'][0].update(skill_ids=['agriculture']*6),lambda c:c['heroes'][0].update(skill_ids=['missing']),lambda c:c['heroes'][0].update(skill_ids=['agriculture','agriculture']),lambda c:c['heroes'][0].update(prefect={'magic':999}),lambda c:c['heroes'][0]['attributes'].update(charisma=90),lambda c:c['heroes'][0].update(skill_ids=['kings_counsel','martial_sage'])]
  for change in mutations:
   c=copy.deepcopy(CONTENT);change(c)
   with self.assertRaises((ValueError,KeyError)):validate(LIB,c,CFG)
  lib=copy.deepcopy(LIB);lib['skills'][0]['effects'][0]['script']='grant_grain(10)'
  with self.assertRaises(ValueError):validate(lib,CONTENT,CFG)
 def test_resolver_contains_no_known_names(self):
  tree=ast.parse((ROOT/'scripts/hero_reference_v071.py').read_text())
  constants={n.value for n in ast.walk(tree) if isinstance(n,ast.Constant) and isinstance(n.value,str)}
  for h in H.values():self.assertNotIn(h['id'],constants);self.assertNotIn(h['name'],constants)

if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',default='dist/prd-v07');args=parser.parse_args()
 result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ContractTests))
 out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
 report={'spec_version':'0.7.1','scope':'Python_contract_and_reference_arithmetic_only','tests_run':result.testsRun,'failed':len(result.failures),'errors':len(result.errors),'swift_game_integrated':False,'application_acceptance_executed':0,'example':{'cook_rate':11410,'cook_seconds':127,'trade_quote':39,'zhao_escort':63,'guan_escort':69}}
 (out/'hero-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 raise SystemExit(not result.wasSuccessful())
