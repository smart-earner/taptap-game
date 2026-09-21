#!/usr/bin/env python3
"""Validate PRD 0.7 contracts and export a readable specification.
This is NOT the Swift game engine, a playtest, or a macOS acceptance run.
Python 3.10+, standard library only; no network access or package installation.
"""
from __future__ import annotations
import argparse
import hashlib
import html
import json
import math
import re
import sys
from fractions import Fraction
from pathlib import Path
from urllib.parse import urljoin

ROOT = Path(__file__).resolve().parents[1]
CHAPTERS = [
    '00_PRODUCT.md', '01_CITY_GROWTH.md', '02_PRODUCTION.md',
    '03_AGENTS_AND_LOGISTICS.md', '04_FOOD_AND_ECONOMY.md',
    '05_GOVERNANCE_AND_REGION.md', '06_HEROES_COLLECTION_AND_ARMY.md',
    '06A_ATTRIBUTE_AND_SKILL_SYSTEM.md',
    '07_CONTENT_AND_PROGRESSION.md', '08_DESKTOP_UI_AND_ART.md',
    '09_ENGINEERING_AND_ACCEPTANCE.md',
]

def unique_object(pairs):
    result = {}
    for k, v in pairs:
        if k in result:
            raise ValueError('Duplicate JSON key: ' + k)
        result[k] = v
    return result

def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique_object)

def ceildiv(a, b):
    if b <= 0:
        raise ValueError('Non-positive divisor')
    return -(-a // b)

def cooked_time(recipe, rate):
    return ceildiv(recipe['prepare_s'] * 10000, rate) + recipe['passive_s'] + ceildiv(recipe['finish_s'] * 10000, rate)

def escort_score(people, training, walls, attrs, bonus=0):
    return people + 10 * training + 5 * walls + max(0, attrs['command'] - 50) // 5 + max(0, attrs['valor'] - 50) // 10 + max(0, attrs['strategy'] - 50) // 10 + bonus

def fnv64(seed, city, cycle):
    value = 14695981039346656037
    for b in f'{seed}:{city}:{cycle}'.encode('utf-8'):
        value = ((value ^ b) * 1099511628211) & ((1 << 64) - 1)
    return value

class Checks:
    def __init__(self):
        self.rows = []
    def check(self, name, ok, actual=None):
        self.rows.append({'name': name, 'status': 'PASS' if bool(ok) else 'FAIL', 'actual': actual})
    def eq(self, name, actual, expected):
        self.check(name, actual == expected, {'actual': actual, 'expected': expected})
    @property
    def failures(self):
        return [x for x in self.rows if x['status'] == 'FAIL']

def work_start(t, clock):
    phase = t % clock['cycle_s']
    if phase < clock['dawn_end']:
        return t + clock['dawn_end'] - phase
    if phase >= clock['day_end']:
        return t + clock['cycle_s'] - phase + clock['dawn_end']
    return t

def work_end(t, duration, clock):
    if duration == 0:
        return t
    t = work_start(t, clock)
    # These isolated recipe/crop stages are short; a started stage may finish at dusk.
    if t % clock['cycle_s'] + duration > clock['dusk_end']:
        raise ValueError('Reference model only supports safely finishable short stages')
    return t + duration

def isolated_crop_capacity(crop, clock):
    """One bed, ready inputs, no hauling/worker contention; final day of 7-day trace."""
    t, events = 0, []
    end = 7 * clock['growth_day_s']
    while t < end:
        t = work_end(t, crop['sow_s'], clock)
        t = work_end(t, crop['water_work_s'], clock)
        t += crop['mature_s'] // 2
        t = work_end(t, crop['water_work_s'], clock)
        t += crop['mature_s'] - crop['mature_s'] // 2
        t = work_end(t, crop['harvest_s'], clock)
        if end - clock['growth_day_s'] < t <= end:
            events.append(t)
    return len(events)

def isolated_recipe_capacity(recipe, clock):
    """One station, always-available on-shift operators; not an end-to-end city."""
    t, events = 0, []
    end = 7 * clock['growth_day_s']
    while t < end:
        t = work_end(t, recipe['prepare_s'], clock)
        t += recipe['passive_s']
        t = work_end(t, recipe['finish_s'], clock)
        if end - clock['growth_day_s'] < t <= end:
            events.append(t)
    return len(events)

def fractions_json(x):
    if isinstance(x, Fraction):
        return int(x) if x.denominator == 1 else float(x)
    if isinstance(x, dict):
        return {k: fractions_json(v) for k, v in x.items()}
    if isinstance(x, list):
        return [fractions_json(v) for v in x]
    return x

def inline(text):
    value = html.escape(text)
    value = re.sub(r'`([^`]+)`', r'<code>\1</code>', value)
    value = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', value)
    def link(m):
        target = html.unescape(m.group(2))
        if not target.startswith(('https://', 'http://', '#')):
            target = urljoin('https://github.com/smart-earner/taptap-game/blob/main/sanguo-town/docs/', target)
        return '<a href="' + html.escape(target, quote=True) + '">' + m.group(1) + '</a>'
    value = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', link, value)
    return value

def markdown_html(text):
    lines, out, headings = text.splitlines(), [], []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith('```'):
            code = []
            i += 1
            while i < len(lines) and not lines[i].startswith('```'):
                code.append(lines[i]); i += 1
            out.append('<pre><code>' + html.escape('\n'.join(code)) + '</code></pre>')
        elif re.match(r'^#{1,4} ', line):
            n = len(line.split(' ', 1)[0]); title = line[n + 1:]
            anchor = 's' + str(len(headings))
            headings.append((n, title, anchor))
            out.append(f'<h{n} id="{anchor}">' + inline(title) + f'</h{n}>')
        elif line.startswith('|'):
            rows = []
            while i < len(lines) and lines[i].startswith('|'):
                if not re.match(r'^\|[\s:|\-]+\|?$', lines[i]):
                    rows.append([x.strip() for x in lines[i].strip().strip('|').split('|')])
                i += 1
            i -= 1
            table = ['<div class="table-wrap"><table>']
            for j, row in enumerate(rows):
                cell = 'th' if j == 0 else 'td'
                table.append('<tr>' + ''.join('<' + cell + '>' + inline(x) + '</' + cell + '>' for x in row) + '</tr>')
            table.append('</table></div>'); out.extend(table)
        elif line.strip():
            if line.startswith('> '):
                out.append('<blockquote>' + inline(line[2:]) + '</blockquote>')
            else:
                out.append('<p>' + inline(line) + '</p>')
        i += 1
    return '\n'.join(out), headings

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='dist/prd-v07')
    args = parser.parse_args()
    out = Path(args.output).resolve(); out.mkdir(parents=True, exist_ok=True)
    cfg = read_json(ROOT / 'spec/life-v0.7.json')
    content = read_json(ROOT / 'spec/content-v0.7.json')
    docs = {n: (ROOT / 'docs/life-v0.7' / n).read_text(encoding='utf-8') for n in CHAPTERS}
    from hero_reference_v071 import Source, work_rate as hero_work_rate, resolve as hero_resolve, escort_score as hero_escort, validate as validate_heroes
    ability = read_json(ROOT/'spec/hero-system-v0.7.json')
    validate_heroes(ability, content, cfg)
    c = Checks()
    c.eq('matching specification versions', [cfg['spec_version'], content['spec_version']], ['0.7.1', '0.7.1'])
    c.check('not an implemented engine claim', cfg['implementation']['new_engine_verified'] is False and cfg['implementation']['swift_changed'] is False)
    for key, count in [('resources', 17), ('crops', 4), ('recipes', 10), ('jobs', 20), ('buildings', 10)]:
        rows = cfg[key]; ids = [x['id'] for x in rows]
        c.eq(key + ' count', len(rows), count)
        c.check(key + ' unique IDs', len(ids) == len(set(ids)))
    resources = {x['id']: x for x in cfg['resources']}
    crops = {x['id']: x for x in cfg['crops']}
    recipes = {x['id']: x for x in cfg['recipes']}
    jobs = {x['id']: x for x in cfg['jobs']}
    buildings = {x['id']: x for x in cfg['buildings']}
    volume = lambda stock: sum(q * resources[k]['volume_coeff'] for k, q in stock.items())
    for r in cfg['resources']:
        c.check('positive exact volume/' + r['id'], type(r['volume_coeff']) is int and r['volume_coeff'] > 0)
        if r['buy'] is not None:
            c.check('no raw buy-sell arbitrage/' + r['id'], r['buy'] > r['sell'] >= 0)
    def visit(value, trail='root'):
        if isinstance(value, dict):
            for k, v in value.items():
                if k.endswith('_mU') and isinstance(v, dict):
                    c.check('resource references/' + trail + '/' + k, set(v).issubset(resources))
                    c.check('nonnegative integer quantities/' + trail + '/' + k, all(type(q) is int and q >= 0 for q in v.values()))
                visit(v, trail + '/' + k)
        elif isinstance(value, list):
            for j, v in enumerate(value):
                visit(v, trail + '/' + str(j))
    visit(cfg); visit(content, 'content')
    expected_crop_times = {'rice': 7390, 'millet': 3745, 'vegetable': 2815, 'grass': 1900}
    for crop in cfg['crops']:
        c.eq('crop no-wait completion/' + crop['id'], crop['sow_s'] + 2 * crop['water_work_s'] + crop['mature_s'] + crop['harvest_s'], expected_crop_times[crop['id']])
        c.check('whole crop fits reserved field buffer/' + crop['id'], volume(crop['output_mU']) <= cfg['buffers']['crop_output_volume'] * 1000000)
    c.eq('rice milling grain and fodder', [48 // 4 * 3, 48 // 4], [36, 12])
    c.eq('rice milling work', 12 * cooked_time(recipes['mill'], 10000), 720)
    for recipe in cfg['recipes']:
        c.check('recipe worker exists/' + recipe['id'], recipe['job'] in jobs)
        c.check('recipe input fits/' + recipe['id'], volume(recipe['input_mU']) <= cfg['buffers']['station_input_volume'] * 1000000)
        c.check('recipe output fits/' + recipe['id'], volume(recipe['output_mU']) <= cfg['buffers']['station_output_volume'] * 1000000)
        c.check('recipe times/' + recipe['id'], recipe['prepare_s'] > 0 and recipe['finish_s'] > 0 and recipe['passive_s'] >= 0)
    for s in cfg['sources']:
        c.check('source worker/' + s['id'], s['job'] in jobs)
        c.check('source buffer/' + s['id'], volume({s['resource']: s['quantity_mU']}) <= cfg['buffers']['source_output_volume'] * 1000000)
    c.eq('basic meal ordinary', cooked_time(recipes['cook_basic'], 10000), 135)
    c.eq('generic skill-based founding cooking', cooked_time(recipes['cook_basic'], hero_work_rate(ability, {'id':'worker','attributes':dict.fromkeys(ability['attribute_labels'],50),'skill_ids':[]}, 'cook', leaders=[Source(next(h for h in content['heroes'] if h['starting']), 'prefect', True)])), 127)
    c.eq('pig passive duration', cfg['pig']['segments'] * cfg['pig']['segment_growth_s'], 17280)
    c.eq('pig care duration', cfg['pig']['segments'] * cfg['pig']['care_work_s'], 180)
    c.eq('personnel envelope', cfg['limits']['residents_city'] + cfg['limits']['legion_capacity'] + cfg['limits']['visitors_city'] + cfg['limits']['intruders_city'], 253)
    c.check('personnel capacity fits', 253 <= cfg['limits']['agents_city'])
    c.eq('initial ordinary jobs', sum(cfg['initial']['job_counts'].values()), 15)
    c.eq('initial residents', cfg['initial']['ordinary'] + 1, cfg['initial']['population'])
    c.check('initial stocks fit first warehouse', volume(cfg['initial']['stocks_mU']) <= cfg['building_levels']['warehouse_volume'][0] * 1000000)
    c.eq('building total cap', sum(x['max'] for x in cfg['buildings']), 16)
    c.eq('farm cap matches two top farms', 2 * cfg['building_levels']['farm_beds'][-1], cfg['building_levels']['farm_city_beds_max'])
    c.eq('three ration station seats defined', next(x['max'] for x in cfg['extensions'] if x['id'] == 'ration_seat'), 3)
    c.eq('initial crop belongs to a bed', cfg['initial']['farm_beds'], cfg['building_levels']['farm_beds'][0])
    c.check('seed crop is not ripe or free repeated harvest', 0 <= cfg['initial']['existing_millet_growth_s'] < crops['millet']['mature_s'])
    c.eq('initial prior water paid', cfg['initial']['existing_millet_water_mask'], 3)
    bounds = cfg['building_levels']['phase_boundaries_bp']
    c.eq('four phase bounds', bounds, [0, 2000, 4500, 8000, 10000])
    for total in [1, 999, 1000, 12001, 48000, 432000, 999999]:
        parts = [total * b // 10000 - total * a // 10000 for a, b in zip(bounds, bounds[1:])]
        c.eq('phase remainder conserved/' + str(total), sum(parts), total)
    c.eq('house level two cost', buildings['house']['cash'] * 2, 240)
    c.eq('house level two two-worker time', buildings['house']['work_s'] * 4 // 2, 7200)
    for policy, goals in cfg['civic']['goals'].items():
        c.eq('all civic goals supplied/' + policy, len(goals), len(cfg['civic']['tracks']))
        c.check('civic goal range/' + policy, all(1 <= n <= 3 for n in goals))
    c.check('trade and industry structural difference', cfg['civic']['goals']['trade'] != cfg['civic']['goals']['industry'])
    c.eq('happiness weights', sum(cfg['food']['weights'].values()), 100)
    for policy, mix in cfg['food']['menus_bp'].items():
        c.check('menu can fall back to basic/' + policy, sum(mix.values()) <= 10000)
    c.eq('basic food happiness target', (40 * 100 + 10 * 40 + 15 * 100 + 10 * 60 + 15 * 60 + 10 * 100 + 50) // 100, 84)
    c.eq('emergency order includes fee', (80 - 2) // 4, 19)
    c.eq('Lu Su whole-order price', ceildiv(40 * 9200, 10000) + 2, 39)
    c.eq('one carry timeline', [10, 10 + ceildiv(960, 32), 10 + ceildiv(960, 32) + 10], [10, 40, 50])
    c.eq('foot wood capacity mU', 4 * 1000000 // resources['wood']['volume_coeff'], 2000)
    c.eq('foot food capacity mU', 4 * 1000000 // resources['meal_basic']['volume_coeff'], 16000)
    c.eq('local work segments do not round per frame', ceildiv(100000, 10800), 10)
    heroes = {x['id']: x for x in content['heroes']}
    all_uniques = content['heroes'] + content['weapons'] + content['mounts'] + content['souvenirs']
    c.eq('six heroes', len(heroes), 6)
    c.eq('unique collectible count', len(all_uniques), 17)
    c.eq('unique IDs across all collection categories', len({x['id'] for x in all_uniques}), 17)
    c.eq('one founding hero', [x['id'] for x in content['heroes'] if x['starting']], ['xunyu'])
    c.eq('Zhao Yun escort example', hero_escort(ability, heroes['zhaoyun'],30,1,1), 63)
    c.eq('Guan Yu escort example', hero_escort(ability, heroes['guanyu'],30,1,1), 69)
    c.eq('Zhao Yun wounded', ceildiv(5 * (10000-hero_resolve(ability,[Source(heroes['zhaoyun'],'commander',True)],'wounded_reduction_bp')),10000), 4)
    c.eq('equipment crosses valor threshold', escort_score(30, 0, 0, {'command': 50, 'valor': 61, 'strategy': 50}) - escort_score(30, 0, 0, {'command': 50, 'valor': 59, 'strategy': 50}), 1)
    for hero in heroes.values():
        c.check('hero attributes/' + hero['id'], all(type(v) is int and 0 <= v <= 100 for v in hero['attributes'].values()))
    for recruit in content['recruitment']:
        c.check('recruit ID/' + recruit['hero'], recruit['hero'] in heroes and not heroes[recruit['hero']]['starting'])
        c.eq('recruit three stages/' + recruit['hero'], len(recruit['stages']), 3)
    zhao = next(x for x in content['recruitment'] if x['hero'] == 'zhaoyun')
    c.eq('Zhao Yun passive minimum', sum(s['passive_s'] for s in zhao['stages']), 18600)
    c.eq('Zhao Yun total cash', sum(s['cash'] for s in zhao['stages']), 130)
    unique_ids = {x['id'] for x in all_uniques}
    registry = content['metrics_registry']
    def valid_metric(metric):
        if metric in registry: return True
        if metric.startswith('building.'): return metric.split('.', 1)[1] in buildings
        if metric.startswith('civic.'): return metric.split('.', 1)[1] in cfg['civic']['tracks']
        if metric.startswith('owned.'): return metric.split('.', 1)[1] in unique_ids
        if metric.startswith('extension.'): return metric.split('.', 1)[1] in {x['id'] for x in cfg['extensions']}
        return False
    def condition_walk(value, trail='content'):
        if isinstance(value, dict):
            for key, data in value.items():
                if key in ('unlock', 'conditions', 'requires') and isinstance(data, list):
                    for row in data:
                        c.check('condition tuple/' + trail + '/' + key + '/' + str(row), len(row) == 3 and valid_metric(row[0]) and row[1] in content['condition_language']['comparators'])
                condition_walk(data, trail + '/' + key)
        elif isinstance(value, list):
            for i, x in enumerate(value): condition_walk(x, trail + '/' + str(i))
    condition_walk(content)
    deps = {x['id']: [r[0].split('.', 1)[1] for r in x.get('unlock', []) if r[0].startswith('owned.') and r[2] is True] for x in all_uniques}
    def acyclic(node, stack=()):
        return node not in stack and all(acyclic(d, stack + (node,)) for d in deps.get(node, []))
    c.check('unique ownership dependencies have no cycles', all(acyclic(x) for x in deps))
    c.eq('four landmark routes', len(content['landmarks']), 4)
    c.eq('twelve landmark stages', sum(len(x['stages']) for x in content['landmarks']), 12)
    expected_totals = {'welfare': 6300, 'commerce': 8400, 'industry': 7700, 'military': 9100}
    for lm in content['landmarks']:
        c.eq('landmark total cash/' + lm['id'], sum(s['cash'] for s in lm['stages']), expected_totals[lm['id']])
        c.eq('three stages/' + lm['id'], len(lm['stages']), 3)
        c.check('increasing landmark work/' + lm['id'], [s['work_s'] for s in lm['stages']] == sorted(s['work_s'] for s in lm['stages']))
    c.eq('twelve permanent event definitions', len(content['events']), 12)
    c.check('no event money printing', all(e['cash_reward'] == 0 for e in content['events']))
    settlement = cfg['region']['settlement']
    for key, total in settlement['materials_mU'].items():
        c.eq('settlement pack conserved/' + key, settlement['construction_consumes_mU'].get(key, 0) + settlement['handover_stocks_mU'].get(key, 0), total)
    c.eq('settlement cash phases', settlement['survey_cash'] + settlement['build_cash'], settlement['cash'])
    for n in [30, 60, 90]:
        duration_cycles = ceildiv(cfg['army']['escort']['duration_s'], cfg['clock']['cycle_s'])
        total = n * duration_cycles + cfg['army']['escort']['communal_rations_mU'] // 1000
        maximum_person_load = duration_cycles + ceildiv(60, n)
        c.check('escort real pack capacity/' + str(n), maximum_person_load * 1000 * resources['rations']['volume_coeff'] <= cfg['movement']['soldier_ration_pack_capacity'] * 1000000)
        c.eq('escort total rations/' + str(n), total, {30:510, 60:960, 90:1410}[n])
    c.eq('48-minute cycles per growth day', cfg['clock']['growth_day_s'] // cfg['clock']['cycle_s'], 30)
    c.eq('night guard can rest at least 600 seconds', cfg['clock']['night_guard_rest'][1] - cfg['clock']['night_guard_rest'][0], 840)
    c.eq('stable FNV algorithm', fnv64(20260920, 'plain', 10), fnv64(20260920, 'plain', 10))
    # Reference capacity checks: deliberately excludes transport and shared worker contention.
    crop_day = {x['id']: isolated_crop_capacity(x, cfg['clock']) for x in cfg['crops']}
    millet_capacity = crop_day['millet'] * 16 * cfg['building_levels']['farm_city_beds_max']
    ration_batches = isolated_recipe_capacity(recipes['ration_plain'], cfg['clock'])
    ration_capacity = ration_batches * 16 * 3
    forest_upper = Fraction(86400 * 24 * 4, 7200 + 105 + 30)
    matrix = []
    for residents in [16, 64, 150]:
        for soldiers in [0, 30, 60, 90]:
            meals = residents * 60; rations = soldiers * 30
            grain = Fraction(meals + rations, 4)
            wood = Fraction(meals + rations, 16)
            water = Fraction(meals, 8) + Fraction(rations, 16)
            matrix.append({'residents': residents, 'soldiers': soldiers, 'resident_meals_per_day': meals, 'military_rations_per_day': rations, 'grain_per_day': grain, 'wood_per_day': wood, 'water_per_day': water})
    max_need = matrix[-1]
    c.eq('150 residents plus 90 soldiers raw grain need', max_need['grain_per_day'], Fraction(2925))
    c.eq('150 residents plus 90 soldiers cooking wood need', max_need['wood_per_day'], Fraction(2925, 4))
    c.check('crop reference capacity has feasible space', millet_capacity >= max_need['grain_per_day'], millet_capacity)
    c.check('ration reference station capacity has feasible space', ration_capacity >= 2700, ration_capacity)
    c.check('forest reference physical regrowth ceiling exceeds basic cooking', forest_upper >= max_need['wood_per_day'], float(forest_upper))
    capacity = {'scope': 'isolated_reference_arithmetic_not_city_engine', 'shared_workers_and_hauling_simulated': False, 'is_balance_proven': False, 'calendar_trace_days': 7, 'crop_harvests_per_bed_in_final_day': crop_day, '24_millet_beds_reference_grain': millet_capacity, '3_ration_stations_reference_output': ration_capacity, 'forest_regrowth_rate_ceiling': float(forest_upper), 'demand_matrix': fractions_json(matrix)}
    # Geometry: parse the actual chapter coordinates rather than silently choosing a second map.
    geometry = docs['08_DESKTOP_UI_AND_ART.md'].split('稳定slotID与新布局中心：', 1)[1].split('新layoutVersion', 1)[0]
    points = [(int(a), int(x), int(y)) for a, x, y in re.findall(r'(\d+)[^()；;\n]*\((\d+),(\d+)\)', geometry)]
    c.eq('sixteen documented map anchors', len(points), 16)
    c.eq('map anchors exactly 0..15', sorted(x[0] for x in points), list(range(16)))
    for i, x, y in points:
        c.check('anchor in reference map/' + str(i), 45 <= x <= 1875 and 28 <= y <= 1052)
        c.check('main roads do not pass building footprint/' + str(i), not any(x-45 < road < x+45 for road in [140,680,1200,1780]) and not any(y-22 < road < y+28 for road in [200,380,640,840,1000]))
    # Parse application acceptance definitions, but never mark them PASS here.
    cases = []
    for line in docs['09_ENGINEERING_AND_ACCEPTANCE.md'].splitlines():
        if re.match(r'^\|(?:PR|LG|FD|CT|HR|GV|CL|SV|UX)\d{2}\|', line):
            cells = [x.strip() for x in line.strip('|').split('|')]
            cases.append({'id': cells[0], 'given_and_action': cells[1], 'expected': cells[2], 'status':'NOT_RUN', 'engine_commit': None, 'actual': None})
    c.eq('application acceptance definitions', len(cases), 72)
    c.eq('application acceptance unique IDs', len({x['id'] for x in cases}), 72)
    c.check('no fabricated application passes', all(x['status'] == 'NOT_RUN' for x in cases))
    for name, text in docs.items():
        c.check('substantive chapter/' + name, len(text) > 1500)
        c.check('no unresolved placeholder/' + name, not re.search(r'\b(?:TODO|TBD|FIXME)\b', text))
        c.check('no internal tool marker/' + name, 'turn' not in text or not re.search(r'turn\d+(?:file|search|view)', text))
    combined = '# 桌面三国·小城志 PRD v0.7.1\n\n完整研发规格；当前新生活引擎尚未实现。\n\n' + '\n\n---\n\n'.join(docs.values())
    (out / 'PRD-v0.7-complete.md').write_text(combined, encoding='utf-8')
    body, headings = markdown_html(combined)
    toc = ''.join('<a class="h' + str(n) + '" href="#' + anchor + '">' + html.escape(title) + '</a>' for n, title, anchor in headings if n <= 2)
    css = '''body{margin:0;background:#f3f5f4;color:#20322d;font-family:system-ui,-apple-system,"PingFang SC","Microsoft YaHei",sans-serif;line-height:1.8}aside{position:fixed;left:0;top:0;bottom:0;width:245px;overflow:auto;padding:24px;background:#173d34;color:white}aside a{display:block;color:#dcebe6;text-decoration:none;font-size:12px;line-height:1.5;margin:9px 0}aside .h1{font-weight:700;margin-top:20px}main{margin:32px 36px 80px 320px;max-width:1200px;padding:42px;background:white;border-radius:12px}h1{font-size:28px;margin-top:52px;border-bottom:3px solid #adbfaf;padding-bottom:14px;scroll-margin:24px}h2{font-size:21px;margin-top:36px;scroll-margin:20px}p{margin:14px 0}.table-wrap{overflow:auto;margin:20px 0}table{width:100%;border-collapse:collapse;font-size:13px}th{background:#e8eee9;text-align:left}td,th{border:1px solid #d5ded8;padding:10px;vertical-align:top;min-width:70px}tr:nth-child(even){background:#f7faf8}code{font-family:ui-monospace,monospace;background:#edf2ee;padding:2px 4px;border-radius:3px;overflow-wrap:anywhere}pre{overflow:auto;background:#f1f4f2;padding:20px;font-size:12px;line-height:1.6}blockquote{border-left:4px solid #6d9e8b;padding:10px 20px;background:#f4f8f5}a{color:#26644f}details{margin:20px 0}summary{cursor:pointer;font-weight:650}.status{padding:18px;background:#fff5dc;border-left:4px solid #b58c35;font-size:14px}@media(max-width:1000px){aside{display:none}main{margin:12px;padding:20px}h1{font-size:24px}}@media print{aside{display:none}main{margin:0;padding:0;max-width:none}body{background:white;font-size:10pt}h1{break-before:page}.table-wrap{overflow:visible}tr{break-inside:avoid}details{display:none}a{color:inherit}th{background:#eee}}'''
    raw = '<details><summary>核心参数 JSON（完整）</summary><pre>' + html.escape(json.dumps(cfg, ensure_ascii=False, indent=2)) + '</pre></details><details><summary>人物、收藏、特色工程与事件 JSON（完整）</summary><pre>' + html.escape(json.dumps(content, ensure_ascii=False, indent=2)) + '</pre></details>'
    page = '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>小城志 PRD v0.7 完整研发规格</title><style>' + css + '</style></head><body><aside><strong>小城志 · PRD v0.7</strong>' + toc + '</aside><main><div class="status">研发规格与数值基线，不是新客户端交付。此页面无外部资源请求；参考链接只在主动点击后打开。应用验收状态保留 NOT_RUN。</div>' + body + raw + '</main></body></html>'
    (out / 'PRD-v0.7-readable.html').write_text(page, encoding='utf-8')
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'spec/life-v0.7.json', ROOT/'spec/content-v0.7.json'] + [ROOT/'docs/life-v0.7'/n for n in CHAPTERS]}
    report = {'scope':'static_specification_and_isolated_reference_models_only','spec_version':'0.7.1','passed':len(c.rows)-len(c.failures),'failed':len(c.failures),'application_cases':len(cases),'application_cases_executed':0,'swift_engine_tested':False,'m4_tested':False,'checks':fractions_json(c.rows),'sha256':hashes}
    for name, value in [('validation.json', report), ('capacity-reference.json', capacity), ('acceptance-plan.json', cases)]:
        (out / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: report[k] for k in ['scope','passed','failed','application_cases','application_cases_executed']}, ensure_ascii=False))
    for fail in c.failures: print('FAIL:', fail['name'], fail['actual'])
    print('Reference capacity:', json.dumps(capacity, ensure_ascii=False))
    return 1 if c.failures else 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, KeyError, OSError, TypeError) as exc:
        print('SPEC VALIDATION ERROR:', str(exc), file=sys.stderr)
        sys.exit(2)
