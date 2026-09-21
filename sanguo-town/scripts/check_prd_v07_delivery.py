#!/usr/bin/env python3
"""Final PRD cross-file checks and deterministic reading export; no game execution."""
from __future__ import annotations
import argparse
from collections import Counter
from fractions import Fraction
import hashlib
import html
import importlib.util
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='dist/prd-v07')
    args = parser.parse_args()
    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location('v07validator', ROOT/'scripts/validate_prd_v07.py')
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    cfg = module.read_json(ROOT/'spec/life-v0.7.json')
    content = module.read_json(ROOT/'spec/content-v0.7.json')
    seed = module.read_json(ROOT/'spec/bootstrap-v0.7.json')
    c = module.Checks()
    c.eq('bootstrap shares specification version', seed['spec_version'], cfg['spec_version'])
    c.eq('bootstrap remains a design fixture', seed['status'], 'design_fixture_not_runtime_save')
    agents = [seed['hero']] + seed['ordinary_agents']
    c.eq('sixteen unique resident IDs', len({a['id'] for a in agents}), 16)
    c.eq('sixteen distinct reserved beds', len({a['bed_id'] for a in agents}), 16)
    c.eq('ordinary role distribution', dict(Counter(a['role'] for a in seed['ordinary_agents'])), cfg['initial']['job_counts'])
    c.eq('starting hero identity', seed['hero']['person_id'], cfg['initial']['hero'])
    c.eq('starting bed count does not create office bonus beds', len(agents), cfg['building_levels']['house_beds'][0])
    r = {x['id']:x for x in cfg['resources']}
    total = Counter()
    for location in seed['locations']:
        c.check('known location resources/'+location['id'], set(location['stock_mU']).issubset(r))
        c.check('each initial location fits/'+location['id'], sum(q*r[k]['volume_coeff'] for k,q in location['stock_mU'].items()) <= location['capacity_volume']*1000000)
        total.update(location['stock_mU'])
    c.eq('initial location sums equal authoritative totals', dict(total), cfg['initial']['stocks_mU'])
    ordinary_meals = seed['initial_food_allocation']['ordinary_per_person_mU'] * len(seed['ordinary_agents'])
    c.eq('one source per initial meal', ordinary_meals + seed['initial_food_allocation']['hero_mU'], cfg['initial']['stocks_mU']['meal_basic'])
    c.check('initial meals not consumed in advance', seed['initial_food_allocation']['already_consumed'] is False)
    c.eq('four actual field IDs', len(set(seed['initial_beds']['farm_bed_ids'])), cfg['initial']['farm_beds'])
    c.check('one inherited crop belongs to a real bed', seed['initial_beds']['growing_bed'] in seed['initial_beds']['farm_bed_ids'])
    c.eq('inherited crop elapsed growth', seed['initial_beds']['effective_growth_s'], cfg['initial']['existing_millet_growth_s'])
    c.eq('FNV fixed independent vector zero', module.fnv64(20260920,'plain',0),2070784952295781526)
    c.eq('FNV fixed independent vector ten', module.fnv64(20260920,'plain',10),11922799572503056283)
    c.eq('no resident tax', cfg['economy']['tax_enabled'], False)
    c.eq('no food decay', cfg['economy']['spoilage_enabled'], False)
    c.eq('no intruder loss', cfg['security']['losses'], False)
    c.check('public ration packs are not imaginary carts', '不自动生成辎重车' in (ROOT/'docs/life-v0.7/06_HEROES_COLLECTION_AND_ARMY.md').read_text())
    c.check('present consumers explicitly distinguished', 'presentConsumerIDs' in (ROOT/'docs/life-v0.7/04_FOOD_AND_ECONOMY.md').read_text())
    # Independently bind the capacity gate to the actual source, population and recipe inputs.
    # The first script's reference vector is not accepted as proof when parameters change.
    tree = next(x for x in cfg['sources'] if x['id']=='trees')
    recipes = {x['id']:x for x in cfg['recipes']}
    cycles = Fraction(cfg['clock']['growth_day_s'], cfg['clock']['cycle_s'])
    civilian_meals = cfg['limits']['residents_city'] * cfg['food']['meals_per_cycle'] * cycles
    military_meals = Fraction(cfg['limits']['legion_capacity'] * cfg['army']['rations_per_person_cycle_mU'],1000) * cycles
    cooking_wood = civilian_meals * Fraction(recipes['cook_basic']['input_mU']['wood'],recipes['cook_basic']['output_mU']['meal_basic']) + military_meals * Fraction(recipes['ration_plain']['input_mU']['wood'],recipes['ration_plain']['output_mU']['rations'])
    forest_ceiling = Fraction(cfg['clock']['growth_day_s'] * tree['nodes'] * tree['quantity_mU'], 1000 * (tree['regrow_s']+tree['work_s']+tree['replant_s']))
    c.check('configured forest physical ceiling covers configured basic food need', forest_ceiling >= cooking_wood, {'ceiling':float(forest_ceiling),'required':float(cooking_wood),'nodes':tree['nodes']})
    capacity = module.read_json(out/'capacity-reference.json')
    capacity['forest_regrowth_rate_ceiling'] = float(forest_ceiling)
    capacity['forest_capacity_inputs'] = tree
    capacity['basic_food_wood_requirement_from_recipes'] = float(cooking_wood)
    capacity['final_capacity_gate'] = 'check_prd_v07_delivery.py uses actual JSON inputs; not shared-worker or logistics simulation'
    (out/'capacity-reference.json').write_text(json.dumps(capacity,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    root = ROOT/'docs/PRD.md'
    paths = [root] + [ROOT/'docs/life-v0.7'/name for name in module.CHAPTERS]
    for path in paths:
        text = path.read_text(encoding='utf-8')
        for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)', text):
            if target.startswith(('http://','https://','#')): continue
            resolved = (path.parent/target.split('#')[0]).resolve()
            c.check('relative link/'+str(path.relative_to(ROOT))+'/'+target, resolved.exists())
    c.check('main entrypoint refers to new PRD', 'v0.7.1' in root.read_text())
    c.check('original v0.6 entrypoint preserved', (ROOT/'docs/reference/PRD-v0.6.md').exists())
    original = (ROOT/'docs/reference/PRD-v0.6.md').read_bytes()
    blob = hashlib.sha1(b'blob '+str(len(original)).encode()+b'\0'+original).hexdigest()
    c.eq('archived original byte-exact Git blob',blob,'d0546b9029b849dcde8561090de075db033d1972')
    acceptance = module.read_json(out/'acceptance-plan.json')
    c.eq('new engine acceptance not silently passed', sum(x['status']!='NOT_RUN' for x in acceptance), 0)
    c.eq('acceptance count retained',len(acceptance),72)
    c.check('base checks completed before export', module.read_json(out/'validation.json')['failed']==0)
    combined = '\n\n---\n\n'.join(p.read_text(encoding='utf-8') for p in paths)
    for title, value in [('附录A 核心数值JSON',cfg),('附录B 人物与内容JSON',content),('附录C 确定性开局JSON',seed),('附录D 四维与技能库JSON',module.read_json(ROOT/'spec/hero-system-v0.7.json'))]:
        combined += '\n\n# '+title+'\n\n```json\n'+json.dumps(value,ensure_ascii=False,indent=2)+'\n```\n'
    (out/'PRD-v0.7-complete.md').write_text(combined,encoding='utf-8')
    body, headings = module.markdown_html(combined)
    toc = ''.join('<a class="h'+str(n)+'" href="#'+anchor+'">'+html.escape(title)+'</a>' for n,title,anchor in headings if n<=2)
    previous = (out/'PRD-v0.7-readable.html').read_text(encoding='utf-8')
    styles = re.search(r'<style>(.*?)</style>',previous,re.S)
    assert styles is not None
    responsive = 'p,td,th,a,blockquote{overflow-wrap:anywhere}main{min-width:0}pre,.table-wrap{max-width:100%;box-sizing:border-box}'
    page = '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>小城志 PRD v0.7.1 完整研发规格</title><style>'+styles[1]+responsive+'</style></head><body><aside><strong>小城志 · PRD v0.7.1</strong>'+toc+'</aside><main><div class="status">完整研发规格：十章与能力专章、四份配置。新生活引擎与M4实机验收尚未执行；静态通过不等于游戏完成。</div>'+body+'</main></body></html>'
    (out/'PRD-v0.7-readable.html').write_text(page,encoding='utf-8')
    source_paths = paths + [ROOT/'spec/hero-system-v0.7.json',ROOT/'scripts/hero_reference_v071.py',ROOT/'scripts/validate_hero_v071.py',ROOT/'spec/life-v0.7.json',ROOT/'spec/content-v0.7.json',ROOT/'spec/bootstrap-v0.7.json',Path(__file__).resolve(),ROOT/'scripts/validate_prd_v07.py']
    report = {'scope':'cross_file_delivery_and_bootstrap_spec_only','spec_version':'0.7.1','passed':len(c.rows)-len(c.failures),'failed':len(c.failures),'application_cases_executed':0,'engine_tested':False,'checks':c.rows,'sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in source_paths},'complete_markdown_bytes':len(combined.encode('utf-8'))}
    (out/'delivery-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ['scope','passed','failed','application_cases_executed','complete_markdown_bytes']},ensure_ascii=False))
    for row in c.failures: print('FAIL:',row['name'],row['actual'])
    return int(bool(c.failures))

if __name__=='__main__':
    try:
        raise SystemExit(main())
    except (KeyError,ValueError,OSError,TypeError) as exc:
        print('PRD DELIVERY ERROR:',exc,file=sys.stderr)
        raise SystemExit(2)
