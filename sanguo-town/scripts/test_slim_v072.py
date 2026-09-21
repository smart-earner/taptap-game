#!/usr/bin/env python3
"""Static release-contract tests and pure hero arithmetic; NOT the city engine."""
from __future__ import annotations
import argparse, copy, json, tempfile, unittest
from collections import Counter
from pathlib import Path
from build_slim_v072 import ROOT, MAP_FIELDS, material_map, read, resolve, write
from hero_reference_v071 import Source, validate as validate_skills, work_rate, escort_score
CFG=read(ROOT/'spec/slim-v0.7.2.json'); ROSTER=read(ROOT/'spec/heroes-v0.7.2.json'); R=resolve()
ALLOWED={x['id'] for x in CFG['resources']}
class ScopeTests(unittest.TestCase):
 def test_01_eight_actual_resources(self):
  self.assertEqual(ALLOWED,{'grain','meat','meal','rations','wood','stone','iron','tools'})
  self.assertEqual(len(R['life']['resources']),8); self.assertTrue(CFG['cash_is_separate'])
  self.assertEqual(R['life']['hero_system'],'hero-system.json');self.assertEqual(R['content']['hero_system'],'hero-system.json')
 def test_02_four_recipes(self):
  self.assertEqual({x['id'] for x in R['life']['recipes']},{'cook_basic','cook_meat','ration_plain','forge'})
  for x in R['life']['recipes']:
   self.assertTrue(set(x['input_mU'])<=ALLOWED);self.assertTrue(set(x['output_mU'])<=ALLOWED)
   self.assertGreater(x['prepare_s'],0);self.assertGreater(x['finish_s'],0);self.assertGreaterEqual(x['passive_s'],0)
 def test_03_all_material_references(self):
  def visit(x):
   if isinstance(x,list):
    for v in x:visit(v)
   if isinstance(x,dict):
    for k,v in x.items():
     if k in MAP_FIELDS and isinstance(v,dict):
      self.assertTrue(set(v)<=ALLOWED,(k,v));self.assertTrue(all(type(q)is int and q>=0 for q in v.values()))
     else:visit(v)
  for x in R.values():visit(x)
 def test_04_two_crops_only(self):
  crops={x['id']:x for x in R['life']['crops']}
  self.assertEqual(set(crops),{'rice','millet'});self.assertEqual(crops['rice']['mature_s'],7200)
  self.assertEqual(crops['rice']['output_mU'],{'grain':36000});self.assertEqual(crops['millet']['mature_s'],3600)
  self.assertTrue(all('water_each_mU' not in c for c in crops.values()))
 def test_05_design_quote_mapping(self):
  self.assertEqual(material_map({'wood':8000,'planks':4000,'water':2000},CFG),{'wood':14000})
  self.assertEqual(material_map({'planks':1},CFG),{'wood':2})
  with self.assertRaises(ValueError):material_map({'magic':1000},CFG)
 def test_06_founding_conservation(self):
  total=Counter(); by_id={r['id']:r for r in R['life']['resources']}
  for loc in R['bootstrap']['locations']:
   total.update(loc['stock_mU']);self.assertLessEqual(sum(q*by_id[k]['volume_coeff'] for k,q in loc['stock_mU'].items()),loc['capacity_volume']*1_000_000)
  self.assertEqual(dict(total),R['life']['initial']['stocks_mU'])
  self.assertEqual(total['grain'],64000);self.assertEqual(total['meal'],32000)
  agents=[R['bootstrap']['hero']]+R['bootstrap']['ordinary_agents']
  self.assertEqual(len({x['id'] for x in agents}),16);self.assertEqual(len({x['bed_id'] for x in agents}),16)
 def test_07_thirty_heroes_one_start(self):
  heroes=R['content']['heroes'];self.assertEqual(len(heroes),30);self.assertEqual(len({h['id'] for h in heroes}),30)
  self.assertEqual(len({h['name'] for h in heroes}),30)
  self.assertEqual([h['id'] for h in heroes if h['starting']],['xunyu'])
 def test_08_original_six_unchanged(self):
  old=read(ROOT/'spec/content-v0.7.json')['heroes'];new={h['id']:h for h in R['content']['heroes']}
  for h in old:
   self.assertEqual(new[h['id']]['attributes'],h['attributes']);self.assertEqual(new[h['id']]['skill_ids'],h['skill_ids'])
 def test_09_skill_library_no_growth(self):
  self.assertEqual(R['hero-system']['skills'],read(ROOT/'spec/hero-system-v0.7.json')['skills'])
  self.assertEqual(len(R['hero-system']['skills']),22);self.assertEqual(len(R['hero-system']['metrics']),7)
  validate_skills(R['hero-system'],R['content'],R['life'])
 def test_10_every_nonstarter_has_route(self):
  routes=R['content']['recruitment'];self.assertEqual(len(routes),29)
  self.assertEqual({r['hero'] for r in routes},{h['id'] for h in R['content']['heroes'] if not h['starting']})
  for r in routes:
   self.assertEqual(len(r['stages']),3);self.assertEqual(len({c[0] for c in r['unlock']}),len(r['unlock']))
   for stage in r['stages']:self.assertGreater(stage['cash'],0);self.assertGreater(stage['passive_s'],0)
 def test_11_shared_routes_and_permanent_gates(self):
  self.assertEqual(len(ROSTER['standard_recruitment_profiles']),6)
  self.assertTrue(ROSTER['recruitment_rules']['gate_latches_when_first_satisfied'])
  self.assertFalse(ROSTER['recruitment_rules']['require_war'])
  self.assertFalse(ROSTER['recruitment_rules']['random_draw'])
  self.assertTrue(all(16<=h['minimum_population']<=64 for h in R['content']['heroes']))
 def test_12_renamed_heroes_have_same_results(self):
  ordinary={'id':'worker','attributes':dict.fromkeys(['administration','strategy','valor','command'],50),'skill_ids':[]}
  for hero in R['content']['heroes']:
   other=copy.deepcopy(hero);other['id']='unknown';other['name']='临时测试名'
   self.assertEqual(escort_score(R['hero-system'],hero,30,1,1),escort_score(R['hero-system'],other,30,1,1))
   for job in R['life']['jobs']:
    a=work_rate(R['hero-system'],ordinary,job['id'],leaders=[Source(hero,'prefect',True)])
    b=work_rate(R['hero-system'],ordinary,job['id'],leaders=[Source(other,'prefect',True)])
    self.assertEqual(a,b);self.assertTrue(8000<=a<=14000)
 def test_13_bad_skills_rejected(self):
  for mutation in ['unknown','duplicate','overflow','attribute']:
   c=copy.deepcopy(R['content']);h=c['heroes'][0]
   if mutation=='unknown':h['skill_ids']=['does_not_exist']
   if mutation=='duplicate':h['skill_ids']=['agriculture']*2
   if mutation=='overflow':h['skill_ids']=['agriculture','cookery','logistics','commerce','drill','patrol']
   if mutation=='attribute':h['attributes']['command']=101
   with self.assertRaises(ValueError):validate_skills(R['hero-system'],c,R['life'])
 def test_14_quality_not_extra_inventory(self):
  self.assertEqual(CFG['meal_qualities'],{'basic':40,'hearty':100})
  for loc in R['bootstrap']['locations']:
   if loc['stock_mU'].get('meal'):self.assertEqual(loc['lot_metadata']['meal']['quality'],'basic')
  for recipe in R['life']['recipes']:
   if 'meal' in recipe['output_mU']:self.assertIn(recipe['meal_quality'],CFG['meal_qualities'])
 def test_15_no_obsolete_furnace_reward(self):
  stages=next(x for x in R['content']['landmarks'] if x['id']=='industry')['stages']
  self.assertEqual(stages[1]['effects'],{'first_workshop_forge_slots_once':1})
  self.assertEqual(stages[2]['effects'],{'first_workshop_restorer_slots_once':1})
  self.assertEqual({s['resource'] for s in R['life']['sources']},{'wood','stone','iron'})
 def test_16_not_a_save_migration(self):
  self.assertFalse(CFG['scope_flags']['import_new_rules_to_existing_save'])
  self.assertFalse(R['life']['resolved_build_contract']['runtime_migration_enabled'])
  self.assertEqual(len({h['art_family'] for h in ROSTER['heroes']}),8)
  self.assertTrue(all(not ({'effects','prefect','commander','trait'} & set(h)) for h in R['content']['heroes']))
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',default='dist/slim-v072');a=p.parse_args()
 result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ScopeTests))
 report={'scope':'design_configuration_and_Python_reference_only','spec_version':'0.7.2','tests_run':result.testsRun,'failed':len(result.failures),'errors':len(result.errors),'swift_runtime_changed':False,'new_city_engine_tested':False,'m4_tested':False,'new_hero_art_completed':False}
 write(Path(a.output)/'validation.json',report)
 raise SystemExit(0 if result.wasSuccessful() else 1)
if __name__=='__main__':main()
