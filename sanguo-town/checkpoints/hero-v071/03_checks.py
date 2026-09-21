#!/usr/bin/env python3
"""Bounded one-shot validator/export update; only PRD files and read-only spec CI."""
from pathlib import Path
P=Path(__file__).resolve().parents[2]
p=P/'scripts/validate_prd_v07.py';s=p.read_text()
assert "'0.7.0'" in s, 'requires original 0.7.0 checker'
s=s.replace("'0.7.0'","'0.7.1'").replace('v0.7.0','v0.7.1')
pos=s.index('def main():')
s=s[:pos]+s[pos:].replace("    c = Checks()", "    from hero_reference_v071 import Source, work_rate as hero_work_rate, resolve as hero_resolve, escort_score as hero_escort, validate as validate_heroes\n    ability = read_json(ROOT/'spec/hero-system-v0.7.json')\n    validate_heroes(ability, content, cfg)\n    c = Checks()",1)
s=s.replace("c.eq('basic meal Xun Yu', cooked_time(recipes['cook_basic'], 10800), 130)","c.eq('generic skill-based founding cooking', cooked_time(recipes['cook_basic'], hero_work_rate(ability, {'id':'worker','attributes':dict.fromkeys(ability['attribute_labels'],50),'skill_ids':[]}, 'cook', leaders=[Source(next(h for h in content['heroes'] if h['starting']), 'prefect', True)])), 127)")
s=s.replace("escort_score(30, 1, 1, heroes['zhaoyun']['attributes']), 59","hero_escort(ability, heroes['zhaoyun'],30,1,1), 63")
s=s.replace("escort_score(30, 1, 1, heroes['guanyu']['attributes'], 8), 67","hero_escort(ability, heroes['guanyu'],30,1,1), 69")
s=s.replace("ceildiv(5 * 8000, 10000), 4","ceildiv(5 * (10000-hero_resolve(ability,[Source(heroes['zhaoyun'],'commander',True)],'wounded_reduction_bp')),10000), 4")
s=s.replace("'06_HEROES_COLLECTION_AND_ARMY.md',", "'06_HEROES_COLLECTION_AND_ARMY.md',\n    '06A_ATTRIBUTE_AND_SKILL_SYSTEM.md',")
p.write_text(s)
p=P/'scripts/check_prd_v07_delivery.py';s=p.read_text().replace("'0.7.0'","'0.7.1'").replace('v0.7.0','v0.7.1')
s=s.replace("('附录C 确定性开局JSON',seed)","('附录C 确定性开局JSON',seed),('附录D 四维与技能库JSON',module.read_json(ROOT/'spec/hero-system-v0.7.json'))")
s=s.replace('十章正文、三份配置','十章与能力专章、四份配置')
s=s.replace("source_paths = paths + [", "source_paths = paths + [ROOT/'spec/hero-system-v0.7.json',ROOT/'scripts/hero_reference_v071.py',ROOT/'scripts/validate_hero_v071.py',")
s=s.replace('<title>小城志 PRD v0.7 ', '<title>小城志 PRD v0.7.1 ').replace('<strong>小城志 · PRD v0.7</strong>','<strong>小城志 · PRD v0.7.1</strong>')
p.write_text(s)
p=P/'docs/life-v0.7/06_HEROES_COLLECTION_AND_ARMY.md';s=p.read_text().replace('仅七星宝刀的政治+3迁为新规则政治+3','仅七星宝刀的旧魅力+3迁为新规则政治+3');p.write_text(s)
p=P/'docs/PRD.md';s=p.read_text().replace('**取消按武将名字触发加成','取消按武将名字触发加成').replace('\n\n没有把任务生产','\n\n**没有把任务生产');p.write_text(s)
p=P/'README.md'
if p.exists():
 s=p.read_text().replace('PRD v0.7.0','PRD v0.7.1').replace('三份JSON','四份JSON')
 heading='> 人物设计已更新为PRD v0.7.1：政治、智力、武力、统率＋每将1—5个标准技能引用；详见[能力规范](docs/life-v0.7/06A_ATTRIBUTE_AND_SKILL_SYSTEM.md)。这次是规格与Python参考结算更新，Swift游戏仍town-0.5＋desktop-0.1，尚未接入新能力系统。\n\n'
 first,sep,rest=s.partition('\n\n');p.write_text(first+sep+heading+rest)
p=P.parent/'.github/workflows/sanguo-prd-v07.yml';s=p.read_text()
needle="      - 'sanguo-town/scripts/validate_prd_v07.py'"
assert needle in s
s=s.replace(needle,needle+"\n      - 'sanguo-town/scripts/hero_reference_v071.py'\n      - 'sanguo-town/scripts/validate_hero_v071.py'")
needle='          python3 sanguo-town/scripts/validate_prd_v07.py'
assert needle in s
s=s.replace(needle,'          python3 sanguo-town/scripts/validate_hero_v071.py --output dist/prd-v07 2>&1 | tee dist/prd-v07/hero-check.log\n'+needle)
p.write_text(s)
print('Updated current checkers, full four-configuration export, and read-only CI; runtime unchanged.')
