#!/usr/bin/env python3
"""Bounded one-shot updates to existing PRD chapters; no Sources or save files."""
from pathlib import Path
import json,re
P=Path(__file__).resolve().parents[2]
def get(p):return (P/p).read_text()
def put(p,s):(P/p).write_text(s)
def edit(p,a,b):
 s=get(p);assert a in s,(p,a[:60]);put(p,s.replace(a,b))
lib=json.loads(get('spec/hero-system-v0.7.json'));cfg=json.loads(get('spec/life-v0.7.json'));content=json.loads(get('spec/content-v0.7.json'))
assert lib['spec_version']=='0.7.1'
labels=lib['attribute_labels'];names={s['id']:s['name'] for s in lib['skills']}
p='docs/life-v0.7/06_HEROES_COLLECTION_AND_ARMY.md';old=get(p)
assert '## 6.1 开局与六将五维' in old
prefix='''# 06 初期武将、培养、收藏与军团

**0.7.1修订：人物仅存四维和1—5个技能引用，不再内嵌太守/统帅效果。全部公式见[06A四维与标准技能系统](06A_ATTRIBUTE_AND_SKILL_SYSTEM.md)。这不是已经接入运行版的声明。**

## 6.1 开局与六将四维

新开局16常住居民=荀彧1＋普通15；荀彧直接任初城太守。没有免费赵云或随机十连。已拥有角色、ID和履历全部保留。政治/智力/武力/统率均0—100，数值与技能均为游戏设定，不是历史能力评定。

|ID|人物|政治|智力|武力|统率|初始技能（★特色；计入总数）|
|---|---|---:|---:|---:|---:|---|
'''
for h in content['heroes']:
 a=h['attributes']; skills='、'.join(('★' if next(s for s in lib['skills'] if s['id']==x)['kind']=='signature' else '')+names[x] for x in h['skill_ids'])
 prefix+=f"|{h['id']}|{h['name']}|{a['administration']}|{a['strategy']}|{a['valor']}|{a['command']}|{skills}|\n"
prefix+='''
普通居民四维默认50且初始无特技，仍具备全部基础工作资格；普通/未来武将也用同一公式。没有“非名将不能建城”的门槛。每将拥有1—5项、至多1项特色，5是总上限而非5个通用加1个专属；本批数量是4/4/3/5/4/4，不把所有名将统一塞满。

## 6.2 属性、任职和技能的关系

属性决定相关工作的基础适配，职业熟练度来自有效劳动，技能库决定额外专长，职位/真实位置决定作用范围。人物记录里禁止prefect、commander、trait或effects数值对象；只能引用skill_ids。供给保护、基础调度、睡眠与安全运输不需要技能解锁。

厨政不再读取“是否荀彧”，采购不再读取“是否鲁肃”，护送不再读取“是否关羽”。通用EffectResolver按事件、职位、工种、效果族和上限结算。任何新名字使用相同数据都会得到相同结果。特色技能也是库中的普通定义，不是主引擎中的人物分支。

具体22项技能、20工种权重、适用/不适用场景、去重、上限、快照、培养边界与验收均在06A。招募、资源配方、作物成熟、行动成本与以下收藏路径保持不变；仅七星宝刀的魅力+3迁为新规则政治+3，旧档原属性另存。

'''
s=prefix+'## 6.3 '+old.split('## 6.3 ',1)[1]
s=s.replace('五维','四维').replace('武勇','武力').replace('智谋','智力').replace('魅力+3','政治+3')
s=s.replace('有效关羽统帅8','本次技能库解析后的escort_score（上限10）')
s=s.replace('示例30人、训练1、城防1：基础45；赵云92/94/74加8+4+2得59；关羽90/96/72加8+4+2+8得67。','示例30人、训练1、城防1：基础45；赵云92/94/74的属性加14、护送技能加4，总63；关羽90/96/72的属性加14、护送4与武圣6相加10，总69。去掉技能的同属性人物都只得59。')
s=s.replace('成功基础伤兵5，失败12；赵云实际统帅乘0.8向上取整即4/10。','成功基础伤兵5，失败12；伤兵=ceil(基础伤兵×(10000-wounded_reduction_bp)/10000)。技能一身是胆提供2000基点时为4/10；不检查统帅名字。同族保全1000与一身是胆2000取2000，不相加。')
s=s.replace('采购优惠不叠鲁肃','采购优惠与通用属性/技能报价取较低的合法价格，不叠乘')
put(p,s)
for f in (P/'docs/life-v0.7').glob('*.md'):
 if f.name in ['VALIDATION.md','06A_ATTRIBUTE_AND_SKILL_SYSTEM.md']:continue
 f.write_text(f.read_text().replace('五维','四维').replace('武勇','武力').replace('智谋','智力').replace('内政','政治').replace('0.7.0','0.7.1'))
p='docs/life-v0.7/03_AGENTS_AND_LOGISTICS.md';s=get(p).replace('|ID/职责|主属性|','|ID/职责|属性权重|')
for j in cfg['jobs']:
 label='＋'.join(labels[k]+str(v//100)+'%' for k,v in j['attribute_weights_bp'].items())
 s=re.sub(r'(\|'+re.escape(j['id'])+r'[^|]*\|)[^|]+\|',lambda m:m[1]+label+'|',s)
a=s.index('A为工种主属性');b=s.index('\n任务人工剩余=',a)
s=s[:a]+'''A_job=floor(Σ四维有效值×job.attribute_weights_bp/10000)，装备只改持有者四维，单项封顶100。本人属性加成=max(0,A_job-50)×20（上限1000基点）；职业熟练度L1—L5加成=(L-1)×100，与具名战法/特技槽完全不同。

rateBP=clamp(10000+本人属性+职业熟练度+主管属性+适用技能+设施-低满意惩罚,8000,14000)。主管属性对本工种用相同A_job，max(0,A_job-50)×10（上限500）；都督减半后与太守取较大，不叠。具名技能按06A解析，同族取最大、异族加总后上限1200。任何人的名字不进入公式。人工阶段开始快照，不改配方产量、材料、自然成熟或发酵时间。'''+s[b:]
s=s.replace('不加基础四维','不加基础四维，也不解锁或提升skill_ids中的战法/特技');put(p,s)
p='docs/life-v0.7/04_FOOD_AND_ECONOMY.md';s=get(p)
s=s.replace('荀彧太守正向上限5，都督额外恢复折半为+1，同键取较大','适用技能happiness_rise_extra按06A增加正向上限（额外上限2）；至少95%餐食覆盖才生效，都督先向下取整折半，同族取最大')
s=s.replace('荀彧变75','有安抚特技且本餐覆盖≥95%时变74；名为荀彧但无安抚时仍73')
s=s.replace('鲁肃普通采购折扣8%，费用2铜不打折；山地铁价合作-5%与鲁肃取较低合法报价，不叠乘','普通资源采购用实际经办人/太守/都督的商贸加权属性折扣及通商等标准技能；合计≤10%，2铜费用不折。具体取整、来源去重见06A；山地铁价合作-5%与属性/技能报价取较低合法报价，不叠乘');put(p,s)
p='docs/life-v0.7/05_GOVERNANCE_AND_REGION.md';s=get(p);a=s.index('基础任用分B=');b=s.index('\n\n都督每',a)
s=s[:a]+'''基础太守分B=floor(政治×0.5+智力×0.3+统率×0.2)，只用原始四维，装备不触发行政调任。都督候选参考分=floor(统率×0.4+政治×0.4+智力×0.2)；统帅参考分=floor(统率×0.6+武力×0.3+智力×0.1)，不取代玩家任命。

取消“安民荀彧+8”等按姓名加分。方针适配F按hero-system JSON中的policy_fit_job_weights_bp，计算候选作为太守对相关工种提供的主管属性＋适用work_rate_bp：F=floor(10×Σ方针工种权重×该工种加成/(10000×1700))，范围0—10；评估时用基础属性、L1，不读取装备。报价/巡逻/军事等非劳动效果在推荐面板另列，不暗加排名。最终太守候选分=B+F。所有候选一套公式；保供保护先于分数，低分代理照常能治理。'''+s[b:]
s=s.replace('主属性、agentID','本工种加权属性A_job、agentID');put(p,s)
edit('docs/life-v0.7/08_DESKTOP_UI_AND_ART.md','合法赵云/街巷加成','适用patrol_speed_bp技能/街巷加成（不按姓名）')
p='docs/life-v0.7/09_ENGINEERING_AND_ACCEPTANCE.md';s=get(p)
s=s.replace('普通下一73，荀彧75','普通下一73，安抚且覆盖≥95%则74')
s=s.replace('56+60+14=130，材料与16产出不变','A厨政=91，主管410＋庖厨400＋王佐600；rate11410，53+60+14=127；产出16不变')
s=s.replace('原人工段不回算，新段有效+1200','原人工段不回算；新builder段主管380＋营造400＋卧龙800=1580，rate11580（普通L1，无其他项）')
s=s.replace('score59成功；基础5伤→4','score63成功；护送4，一身是胆减伤20%，基础5伤→4')
s=s.replace('role,shift,activeOrderID?,route,cargo,skills,rest','role,shift,activeOrderID?,route,cargo,jobXP,skillIDs,baseAttributes,legacyAttributes?,rest')
s=s.replace('`spec/content-v0.7.json`是特色、事件与收藏。','`spec/content-v0.7.json`是特色、事件与收藏；`spec/hero-system-v0.7.json`定义四维、工种权重、22技能与效果原语。人物只引用技能ID；未知效果、重复技能、非法范围阻止新规则写入。')
s=s.replace('人物效果','标准属性/技能解析')
s=s.replace('## 9.6 安全迁移与旧义务','能力迁移另按06A执行：四个旧键逐项保留，旧魅力仅写legacyAttributes；已开始阶段/出征不重算；按explicitMigrationMap添加初始skillIDs一次，不按显示姓名匹配。技能学习、洗练、手动放招默认关闭。\n\n## 9.6 安全迁移与旧义务');put(p,s)
p='docs/PRD.md';s=get(p).replace('v0.7.0','v0.7.1').replace('三份JSON','四份JSON').replace('十章和','十章及能力专章和').replace('十章规范','十章＋能力专章').replace('五维','四维').replace('武勇','武力').replace('智谋','智力')
needle='|[核心数值](../spec/life-v0.7.json)|'
s=s.replace(needle,'|[06A 四维与标准技能系统](life-v0.7/06A_ATTRIBUTE_AND_SKILL_SYSTEM.md)|20工种权重、通用任职属性收益、1—5技能槽、22技能库、7效果原语、叠加/迁移/扩展|\n|[能力系统配置](../spec/hero-system-v0.7.json)|四维标签、工种权重、岗位评分、标准技能与能力白名单|\n'+needle)
s=s.replace('六将效果/叠加/快照','六将四维/技能ID/叠加/快照')
s=s.replace('本轮没有升级游戏运行代码','本轮仅修订人物规格与可执行参考计算，没有升级游戏运行代码')
s=s.replace('没有把任务生产','取消按武将名字触发加成，政治、智力、武力、统率使用统一公式；每将1—5项通用/特色技能均从库中引用。\n\n没有把任务生产')
s=s.replace('python3 scripts/validate_prd_v07.py','python3 scripts/validate_hero_v071.py --output dist/prd-v07\npython3 scripts/validate_prd_v07.py');put(p,s)
p='docs/PRD_CITY_LIFE.md';s=get(p).replace('v0.7.0','v0.7.1');put(p,s)
print('Synchronized active PRD, not historical versions; no Swift game changes.')
