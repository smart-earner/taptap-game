#!/usr/bin/env python3
"""Validate v0.8 contracts, not the Swift simulation or gameplay balance."""
import argparse
import copy
import hashlib
import json
import re
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / 'spec/hero-town-v0.8.json'


def validate(s):
    rows = []

    def check(name, condition):
        rows.append({'name': name, 'passed': bool(condition)})

    check('version', s['spec_version'] == '0.8.0' and s['save_format'] == 3)
    check('scope/no ordinary population', s['scope'] == {
        'cities': 1, 'resident_pool': 30, 'ordinary_residents': False,
        'immigration': False, 'legion': False, 'cross_city': False,
        'hero_learning': False, 'manual_cast': False, 'breeding': False})
    resources = {r['id']: r for r in s['resources']}
    check('eight resources', len(s['resources']) == 8 and set(resources) ==
          {'grain', 'meat', 'meal', 'rations', 'wood', 'stone', 'iron', 'tools'})
    for name, digest in s['dependency_sha256'].items():
        check('dependency/' + name, hashlib.sha256((ROOT / 'spec' / name).read_bytes()).hexdigest() == digest)
    library = json.loads((ROOT / 'spec/hero-system-v0.7.json').read_text())
    old = json.loads((ROOT / 'spec/heroes-v0.7.2.json').read_text())
    originals = {h['id']: h for h in old['heroes']}
    skills = {x['id']: x for x in library['skills']}
    heroes = s['heroes']
    ids = [h['id'] for h in heroes]
    starters = {h['id'] for h in heroes if h['starting']}
    check('thirty unique hero IDs', len(ids) == len(set(ids)) == 30)
    check('exact five starters', starters == set(s['bootstrap']['starters']) ==
          {'xunyu', 'liubei', 'zhangfei', 'zhaoyun', 'huangyueying'})
    check('five initial beds', s['bootstrap']['beds'] == len(starters) == 5)
    jobs = [j for values in s['work_groups'].values() for j in values]
    check('six groups cover twenty jobs once', len(s['work_groups']) == 6 and
          len(jobs) == len(set(jobs)) == 20 and set(jobs) == set(library['job_weights_bp']))
    check('skill weights pinned', s['skill_contract']['job_weights_bp'] == library['job_weights_bp'])
    for h in heroes:
        prefix = 'hero/' + h['id']
        check(prefix + '/attributes', set(h['attributes']) == {'administration', 'strategy', 'valor', 'command'}
              and all(type(v) is int and 0 <= v <= 100 for v in h['attributes'].values()))
        check(prefix + '/skills', 1 <= len(h['skill_ids']) <= 5 and
              len(h['skill_ids']) == len(set(h['skill_ids'])) and set(h['skill_ids']) <= set(skills))
        check(prefix + '/original identity', h['id'] in originals and
              h['name'] == originals[h['id']]['name'] and h['attributes'] == originals[h['id']]['attributes']
              and h['skill_ids'] == originals[h['id']]['skill_ids'])
        check(prefix + '/preference', h['preferred_group'] in s['work_groups'])
        check(prefix + '/profile', (h['recruitment_profile'] == 'founding') == h['starting'] and
              (h['starting'] or h['recruitment_profile'] in s['recruitment']['profiles']))
    # Population-only gate reachability, NOT resource/timing/bed feasibility.
    owned, pending = set(starters), [h for h in heroes if not h['starting']]
    while pending:
        ready = [h for h in pending if h['minimum_owned'] <= len(owned)]
        if not ready:
            break
        for h in ready:
            owned.add(h['id'])
            pending.remove(h)
    check('population gates have no cycle', len(owned) == 30 and not pending)
    for h in heroes:
        if h['starting']:
            continue
        t = h['tier']
        check('tier/' + h['id'], 0 <= t < 5 and h['minimum_owned'] == [5, 8, 12, 18, 24][t])
    for key, p in s['recruitment']['profiles'].items():
        check('recruitment/' + key, len(p['cash']) == len(p['wait_s']) == len(p['materials_mU']) == 3
              and all(type(x) is int and x >= 0 for x in p['cash'] + p['wait_s']))

    def material_map(m, path):
        check(path + '/resources', isinstance(m, dict) and set(m) <= set(resources))
        check(path + '/amounts', all(type(v) is int and v >= 0 for v in m.values()))

    def visit(obj, path='spec'):
        if isinstance(obj, dict):
            for key, value in obj.items():
                if key.endswith('_mU'):
                    if type(value) is int:
                        check(path + '/' + key + '/nonnegative', value >= 0)
                    else:
                        for i, m in enumerate(value if isinstance(value, list) else [value]):
                            material_map(m, path + '/' + key + '/' + str(i))
                visit(value, path + '/' + key)
        elif isinstance(obj, list):
            for i, value in enumerate(obj):
                visit(value, path + '/' + str(i))
    visit(s)

    def volume(stock):
        return sum(q * resources[k]['volume_coeff'] for k, q in stock.items())

    recipes = {r['id']: r for r in s['recipes']}
    check('four exact recipes', set(recipes) == {'cook_basic', 'cook_meat', 'ration_plain', 'forge'})
    for rid, expected in [('cook_basic', 70), ('cook_meat', 100), ('ration_plain', 160), ('forge', 195)]:
        r = recipes[rid]
        check('recipe/' + rid + '/duration', sum(r[k] for k in ['prepare_s', 'passive_s', 'finish_s']) == expected)
        check('recipe/' + rid + '/fits', volume(r['output_mU']) <= s['storage']['device_output_volume'] * 1000000)
    check('basic exact vector', recipes['cook_basic']['input_mU'] == {'grain': 1000, 'wood': 250}
          and recipes['cook_basic']['output_mU'] == {'meal': 4000})
    check('four portion meal batches', all(recipes[r]['output_mU']['meal'] == 4000 for r in ['cook_basic', 'cook_meat']))
    check('two crops', {c['id'] for c in s['crops']} == {'millet', 'rice'})
    for c in s['crops']:
        check('crop/' + c['id'] + '/duration', c['sow_s'] + 2*c['water_work_s'] + c['mature_s'] + c['harvest_s'] ==
              {'millet': 3745, 'rice': 7390}[c['id']])
        check('crop/' + c['id'] + '/fits', volume(c['output_mU']) <= 64000000)
    b = {b['id']: b for b in s['buildings']}
    check('sixteen functional plots', sum(x['max'] for x in b.values()) == 16)
    check('house capacities', b['house']['capacity'] == [5, 8, 10])
    stock = dict(s['bootstrap']['stocks_mU'])
    meal = stock.pop('meal')
    check('initial meal storage fits', volume({'meal': meal}) <= s['storage']['home_meal_volume'][0] * 1000000)
    check('initial granary fits', volume(stock) <= b['granary']['capacity'][0] * 1000000)
    check('initial meals cover two meals', meal == len(starters) * 2 * 1000)
    check('initial protected food', Fraction(meal + 4*stock['grain'], 1000) >= 4*len(starters))
    check('admin lease contract', s['scheduler']['admin_work_s'] == 30 and
          s['scheduler']['admin_lease_s'] == 600 and not s['skill_contract']['self_prefect_stacking'])
    check('rest window can contain rest', s['clock']['rest_window'][1] - s['clock']['rest_window'][0] >= s['clock']['continuous_rest_s'])
    check('no five-person night slot', s['scheduler']['night_patrol_min_owned'] > len(starters))
    check('two pigs', s['pig']['target'] == s['pig']['slots'] == 2)
    check('pig total grain', s['pig']['segments'] * s['pig']['feed_mU']['grain'] == 1500)
    check('emergency arithmetic', (s['food']['emergency_budget'] - s['food']['market_contract_fee']) // 4 == 9)
    check('twelve landmark stages', len(s['landmarks']['stages']) == 12 and
          len({x['id'] for x in s['landmarks']['stages']}) == 12)
    check('landmark full cash', sum(s['landmarks']['stage_cash']) == 1260)
    check('six weapons four mounts', len(s['collections']['weapons']) == 6 and len(s['collections']['mounts']) == 4)
    check('story no rewards', s['stories']['resources_delta'] == s['stories']['experience_delta'] == 0
          and not s['stories']['blocking'] and not s['stories']['relationship_bonus'])
    for n in [5, 10, 20, 30]:
        daily = n * 2 * (s['clock']['growth_day_s'] // s['clock']['cycle_s'])
        check('food equivalence/' + str(n), Fraction(daily, 4) == n*15)
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', type=Path, default=ROOT/'dist/prd-v08')
    args = ap.parse_args()
    s = json.loads(SPEC.read_text())
    rows = validate(s)
    negative = []
    for label, mutate in [
        ('duplicate hero', lambda x: x['heroes'].__setitem__(1, copy.deepcopy(x['heroes'][0]))),
        ('old sixteen portion batch', lambda x: x['recipes'][0]['output_mU'].__setitem__('meal', 16000)),
        ('ordinary immigration', lambda x: x['scope'].__setitem__('immigration', True)),
        ('unreachable population', lambda x: [h.__setitem__('minimum_owned', 31) for h in x['heroes'] if not h['starting']]),
        ('removed water resource', lambda x: x['recipes'][0]['input_mU'].__setitem__('water', 1000)),
        ('insufficient meal buffer', lambda x: x['storage']['home_meal_volume'].__setitem__(0, 1)),
        ('dependency mismatch', lambda x: x['dependency_sha256'].__setitem__('hero-system-v0.7.json', '0'*64)),
    ]:
        bad = copy.deepcopy(s)
        mutate(bad)
        rejected = any(not r['passed'] for r in validate(bad))
        negative.append({'name': label, 'rejected': rejected})
        rows.append({'name': 'negative/' + label, 'passed': rejected})
    chapters = sorted((ROOT/'docs/life-v0.7').glob('0*.md'))
    docs = [ROOT/'docs/PRD.md', ROOT/'docs/PRD_CITY_LIFE.md', ROOT/'docs/PRD_DESKTOP_MODE.md'] + chapters
    for path in docs:
        text = path.read_text()
        rows.append({'name': 'version/' + path.name, 'passed': 'v0.8' in text})
        for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)', text):
            if target.startswith(('http:', 'https:', '#')):
                continue
            rows.append({'name': 'link/' + path.name + '/' + target,
                         'passed': (path.parent / target.split('#')[0]).resolve().exists()})
    failed = [r for r in rows if not r['passed']]
    report = {'scope': 'static_contract_only', 'status': 'STATIC_FAIL' if failed else 'STATIC_PASS',
              'spec_sha256': hashlib.sha256(SPEC.read_bytes()).hexdigest(),
              'checks': rows, 'negative_tests': negative,
              'passed': len(rows)-len(failed), 'failed': len(failed),
              'application_cases_executed': 0, 'engine_tested': False,
              'runtime_cases': [{'caseID': f'HT{i:02}', 'status': 'NOT_RUN'} for i in range(1, 33)],
              'ux_cases': [{'caseID': f'UX{i:02}', 'status': 'NOT_RUN'} for i in range(1, 9)]}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output/'validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    combined = '\n\n---\n\n'.join(p.read_text() for p in [ROOT/'docs/PRD.md'] + chapters)
    # Convert relative markdown links to canonical repository paths in this standalone export.
    sections = []
    for p in [ROOT/'docs/PRD.md'] + chapters:
        def link(m):
            target = m.group(2)
            if target.startswith(('https:', 'http:', '#')):
                return m.group(0)
            resolved = (p.parent/target.split('#')[0]).resolve().relative_to(ROOT.parent)
            return f'[{m.group(1)}](https://github.com/smart-earner/taptap-game/blob/main/{resolved})'
        sections.append(re.sub(r'\[([^\]]*)\]\(([^)]+)\)', link, p.read_text()))
    combined = '\n\n---\n\n'.join(sections)
    combined += '\n\n# 附录：完整 v0.8 参数表\n\n```json\n'+json.dumps(s, ensure_ascii=False, indent=2)+'\n```\n'
    (args.output/'PRD-v0.8-complete.md').write_text(combined)
    print(json.dumps({k: report[k] for k in ['scope', 'status', 'passed', 'failed', 'application_cases_executed']}, ensure_ascii=False))
    for r in failed:
        print('FAIL:', r['name'])
    return bool(failed)


if __name__ == '__main__':
    raise SystemExit(main())
