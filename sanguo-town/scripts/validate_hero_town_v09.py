#!/usr/bin/env python3
"""Static v0.9 document/data checks and reference vectors, not Swift acceptance."""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / 'spec/hero-town-v0.9.json'


def validate(s):
    rows = []
    def check(name, value):
        rows.append({'name': name, 'passed': bool(value)})
    check('versions', (s['spec_version'], s['rules_version'], s['save_format'], s['layout_version']) == ('0.9.0', 'hero-town-0.9.0', 4, 6))
    check('manual cultivation', not s['cultivation']['automatic'] and not s['scope']['auto_cultivation'])
    check('player actions', set(s['governance']['player_actions']) == {'recruit_draw', 'star_up', 'disassemble_cards', 'exchange_souls'})
    check('no automated consumption', not set(s['governance']['automatic']) & {'star_up', 'surplus_disassembly', 'soul_exchange', 'recruit_draw'})
    check('no ordinary people', s['scope']['resident_pool'] == 30 and not s['scope']['ordinary_residents'] and not s['scope']['immigration'])
    check('ten resources', {r['id'] for r in s['resources']} == {'grain','meat','meal','rations','wood','stone','iron','tools','gold_ore','gold_ingot'} and len(s['resources']) == 10)
    resources = {r['id'] for r in s['resources']}
    jobs = s['skill_contract']['job_weights_bp']
    for name, digest in s['dependency_sha256'].items():
        check('dependency/' + name, hashlib.sha256((ROOT/'spec'/name).read_bytes()).hexdigest() == digest)
    for job, weights in jobs.items():
        check('weight/' + job, sum(weights.values()) == 10000 and all(v > 0 for v in weights.values()))
    check('bootstrap', s['bootstrap']['gold_coins'] == 200 and s['bootstrap']['beds'] == 5 and len(s['bootstrap']['starters']) == 5)
    check('all resource amounts', set(s['bootstrap']['stocks_mU']) == resources and all(q >= 0 for q in s['bootstrap']['stocks_mU'].values()))
    check('no old recruitment', 'recruitment' not in s)
    check('cost', s['gacha']['cost'] == {'single':100, 'ten':1000})
    check('probability', s['gacha']['rarity_bp'] == {'talent':7000,'renowned':2500,'legend':500})
    check('pity', s['gacha']['pity_threshold'] == 20 and s['gacha']['pity_resets_on_duplicate_legend'])
    check('duplicates enabled', not s['gacha']['remove_owned'] and s['gacha']['hero_count'] == 30)
    check('no automatic draw', s['gacha']['manual_auto_draw'] is False and s['gacha']['daily_reset'] is False)
    check('arrival', s['gacha']['arrival_s'] == 30 and s['gacha']['guest_beds'] >= 25)
    check('unique definitions', len(s['heroes']) == 30 and len({h['id'] for h in s['heroes']}) == 30)
    for rarity, n in [('talent',10),('renowned',12),('legend',8)]:
        check('pool/' + rarity, sum(h['rarity'] == rarity for h in s['heroes']) == n)
    all_skills = []
    for h in s['heroes']:
        check('attributes/' + h['id'], set(h['attributes']) == {'administration','strategy','valor','command'} and all(0 <= x <= 100 for x in h['attributes'].values()))
        check('hero/' + h['id'], h['star_initial'] == 1 and h['star_profile'] in s['star_skill_profiles'] and len(h['skills']) == 3)
        check('gates/' + h['id'], [v['unlock_star'] for v in h['skills']] == [1,3,5])
        check('skills/' + h['id'], h['skills'][0]['values_by_star'] == [400,600,600,600,600] and h['skills'][1]['values_by_star'] == [0,0,400,600,600])
        for sk in h['skills']:
            all_skills.append(sk['id'])
            check('jobs/' + sk['id'], set(sk.get('jobs',[])) <= set(jobs))
        check('signature/' + h['id'], h['skills'][2]['effect'] == s['star_skill_profiles'][h['star_profile']]['signature'])
    check('90 distinct skills', len(set(all_skills)) == 90)
    check('star costs', s['cultivation']['duplicate_cost_by_next_star'] == {'2':1,'3':2,'4':3,'5':4})
    check('body and locks', s['cultivation']['protect_resident_body'] and s['cultivation']['lock_cards'] and s['cultivation']['default_batch_selection'] == 'none')
    check('manual splitting nonmax', not s['cultivation']['disassemble_only_surplus_at_max_star'])
    for rarity in ['talent','renowned','legend']:
        check('no arbitrage/' + rarity, s['cultivation']['exchange_cost'][rarity] == 4 * s['cultivation']['disassemble_yield'][rarity])
    check('six recipes', len(s['recipes']) == 6 and len({r['id'] for r in s['recipes']}) == 6)
    for r in s['recipes']:
        check('recipe/' + r['id'], set(r['input_mU']) <= resources and set(r['output_mU']) <= resources and all(x > 0 for x in list(r['input_mU'].values()) + list(r['output_mU'].values())))
    smelt = next(r for r in s['recipes'] if r['id'] == 'smelt_gold')
    check('smelting', smelt['input_mU'] == {'gold_ore':2000,'wood':500} and smelt['output_mU'] == {'gold_ingot':1000} and (smelt['prepare_s'],smelt['passive_s'],smelt['finish_s']) == (60,120,20))
    gold = s['gold_economy']
    check('gold source', gold['coin_per_ingot'] == 10 and gold['mint_requires_unloaded'] and not gold['periodic_grants'] and not gold['trade_coins'])
    for b in s['buildings'] + s['attachments']:
        check('building/' + b['id'], b['cash'] == 0 and b['work_s'] > 0 and set(b['materials_mU']) <= resources)
    check('initial gold facilities', {'goldmine-1','smelter-1','tavern-1'} <= set(s['bootstrap']['buildings']))
    check('no legacy active skills', s['skill_contract']['legacy_library_active'] is False and s['skill_contract']['enabled_roles'] == ['self'])
    # Isolated arithmetic vectors, never reported as engine acceptance.
    check('reference one draw production', 10*smelt['output_mU']['gold_ingot']//1000*gold['coin_per_ingot'] == s['gacha']['cost']['single'])
    check('reference five stars', sum(s['cultivation']['duplicate_cost_by_next_star'].values()) == 10)
    check('reference cumulative affordable upgrades', 1+2+3+4 == 10 and 10*10 == 100)
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', type=Path, default=ROOT/'dist/prd-v09')
    args = ap.parse_args()
    s = json.loads(SPEC.read_text())
    rows = validate(s)
    mutations = [
        ('auto cultivation', lambda x: x['cultivation'].__setitem__('automatic', True)),
        ('system draw', lambda x: x['governance']['automatic'].append('recruit_draw')),
        ('remove owned', lambda x: x['gacha'].__setitem__('remove_owned', True)),
        ('wrong probability', lambda x: x['gacha']['rarity_bp'].__setitem__('legend', 1000)),
        ('same hero twice', lambda x: x['heroes'].__setitem__(1, copy.deepcopy(x['heroes'][0]))),
        ('free coins', lambda x: x['gold_economy'].__setitem__('periodic_grants', True)),
        ('coin building', lambda x: x['buildings'][0].__setitem__('cash', 100)),
        ('soul arbitrage', lambda x: x['cultivation']['exchange_cost'].__setitem__('legend', 50)),
        ('decompose body', lambda x: x['cultivation'].__setitem__('protect_resident_body', False)),
        ('instant gold', lambda x: x['recipes'][4]['output_mU'].__setitem__('gold_coin', 100)),
        ('old skill stacking', lambda x: x['skill_contract'].__setitem__('legacy_library_active', True)),
        ('no guest beds', lambda x: x['gacha'].__setitem__('guest_beds', 0)),
    ]
    for name, mutate in mutations:
        bad = copy.deepcopy(s); mutate(bad)
        rows.append({'name':'negative/' + name, 'passed':any(not r['passed'] for r in validate(bad))})
    chapters = sorted((ROOT/'docs/life-v0.7').glob('0*.md'))
    docs = [ROOT/'docs/PRD.md', ROOT/'docs/PRD_CITY_LIFE.md', ROOT/'docs/PRD_DESKTOP_MODE.md'] + chapters
    for p in docs:
        content = p.read_text()
        rows.append({'name':'current version/' + p.name,'passed':'v0.9' in content})
        for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)', content):
            if not target.startswith(('http:', 'https:', '#')):
                rows.append({'name':'link/' + p.name + '/' + target,'passed':(p.parent/target.split('#')[0]).exists()})
    # Verify the source tables against data, including labor that must not be zeroed with currency.
    table = (ROOT/'docs/life-v0.7/01_CITY_GROWTH.md').read_text()
    for b in s['buildings']:
        rows.append({'name':'table/building/' + b['id'],'passed':f"|{b['id']}|{b['max']}|0|{b['work_s']}|" in table})
    for b in s['attachments']:
        rows.append({'name':'table/attachment/' + b['id'],'passed':f"|{b['id']}|0|{b['work_s']}|" in table})
    failed = [r for r in rows if not r['passed']]
    report = {'scope':'static_contract_only','status':'STATIC_FAIL' if failed else 'STATIC_PASS',
              'spec_sha256':hashlib.sha256(SPEC.read_bytes()).hexdigest(), 'passed':len(rows)-len(failed), 'failed':len(failed),
              'application_cases_executed':0,'engine_tested':False,'checks':rows,
              'runtime_cases':[{'caseID':f'GC{i:02}','status':'NOT_RUN'} for i in range(1,29)]}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output/'validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    sections=[]
    for p in [ROOT/'docs/PRD.md']+chapters:
        def link(m):
            target=m.group(2)
            if target.startswith(('http:', 'https:', '#')): return m.group(0)
            path=(p.parent/target.split('#')[0]).resolve().relative_to(ROOT.parent)
            return f'[{m.group(1)}](https://github.com/smart-earner/taptap-game/blob/main/{path})'
        sections.append(re.sub(r'\[([^\]]*)\]\(([^)]+)\)',link,p.read_text()))
    (args.output/'PRD-v0.9-complete.md').write_text('\n\n---\n\n'.join(sections)+'\n\n# 完整参数\n\n```json\n'+json.dumps(s,ensure_ascii=False,indent=2)+'\n```\n')
    print(json.dumps({k:report[k] for k in ['scope','status','passed','failed','application_cases_executed']},ensure_ascii=False))
    for r in failed: print('FAIL',r['name'])
    return bool(failed)

if __name__ == '__main__':
    raise SystemExit(main())
