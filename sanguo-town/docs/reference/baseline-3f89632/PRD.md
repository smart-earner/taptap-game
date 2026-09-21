# 桌面三国·小城志 · PRD v0.7.2

## 首版收敛：8种物资、30名武将

**设计基线仍v0.7.2；截至2026-09-21，可运行代码已推进到life-0.7.2-v2单城生活与可选肉食供应。实际范围见[BUILD_STATUS](BUILD_STATUS.md)及[养殖增量](HUSBANDRY_V2.md)。这不等于完整PRD全部实现。**

城市长期成长、玩家只作重要决策的定位不变。17资源方案收敛为8种可堆叠物资、2种作物、4项加工；首批武将内容池30名。沿用四维、22技能与7效果原语，不增加24套人物例外。开局仍荀彧＋15居民。

本次实际实现的养殖链采用常备2头，尚未开放最终8头上限的规模管理。资源和配方仍使用已生成的0.7.2目录，没有为了这批动物新增库存。历史设计章节中的“当时未实现”属于交付时记录，当前完成度只以BUILD_STATUS为准。

## 当前规范与数据

- **[v0.7.2收敛规范与完整30将表](SLIM_V0_7_2.md)**：资源去留、配方、服务化用水、成本替换、饭食、种养、名单、招募模板、范围与迁移边界。
- [首版范围数据](../spec/slim-v0.7.2.json)：8库存、2作物、4配方、设计报价转换、旧基线校验值、禁止扩展项。
- [30将配置](../spec/heroes-v0.7.2.json)：四维、1—5技能、建议用途、发现条件和六个标准招募模板。
- [配置生成器](../scripts/build_slim_v072.py)与[配置/参考测试](../scripts/test_slim_v072.py)：从锁定基线生成四份有效配置，不读写用户存档。
- [四维与通用技能公式](life-v0.7/06A_ATTRIBUTE_AND_SKILL_SYSTEM.md)：旧章的六将数量由30将表取代。

运行实现的[打包配置生成器](../scripts/export_life_catalog.py)将受校验的有效数据装入SanguoLife/Resources/catalog.json，并与Mac包一起分发。不能一半读旧17资源表、一半读新8资源表；上游基线摘要改变时必须审查后更新，不能绕过校验。

## 继承机制与开发顺序

以下只继承收敛稿没有覆盖的机制。涉及旧物资、旧名单或对应设备，按有效配置替代，不由开发自行猜。

|章节|继续适用|
|---|---|
|[产品原则](life-v0.7/00_PRODUCT.md)|低打扰、城池是主角、无按月重置|
|[城市成长](life-v0.7/01_CITY_GROWTH.md)|容量/入住/服务分离，施工与预算|
|[人物与物流](life-v0.7/03_AGENTS_AND_LOGISTICS.md)|一人一任务、路径、班次、批次与原子交付|
|[饭食与财政](life-v0.7/04_FOOD_AND_ECONOMY.md)|真实消费、保护线、满意度、合法贸易|
|[治理与区域](life-v0.7/05_GOVERNANCE_AND_REGION.md)|权限、代理、到任、跨城；未完成范围不得提前显示完成|
|[收藏与军团](life-v0.7/06_HEROES_COLLECTION_AND_ARMY.md)|6器4马1木印、装备与军粮；人数和成本按新表|
|[特色工程](life-v0.7/07_CONTENT_AND_PROGRESSION.md)|四条长期工程与常驻机会；分批实际实现|
|[桌面表现](life-v0.7/08_DESKTOP_UI_AND_ART.md)|全桌面、默认96人绘制上限、真实工作、透明穿透|
|[工程与验收](life-v0.7/09_ENGINEERING_AND_ACCEPTANCE.md)|事务、幂等、保存、离线；旧资源算例先转换再验证|

完整72项产品验收不因当前246项实现回归自动通过。v1生活存档可显式启用v2养殖，经典旧城迁移仍未实现；禁止安装新包后静默覆盖原城。完整备份恢复界面、全30人可达性、长期平衡与M4实机体验仍按完成度文档逐项记录。

## 复现

```sh
cd sanguo-town
python3 scripts/build_slim_v072.py --output dist/slim-v072
python3 scripts/test_slim_v072.py --output dist/slim-v072
python3 scripts/export_life_catalog.py --check
swift test
swift run -c release SanguoLifeCLI --seconds 172800 --cadence 120 --husbandry --seal --preview --output dist/husbandry
```

前三项验证设计与打包配置；后两项实际运行Swift，不混淆静态检查和运行验收。Mac客户端另需macOS15+及Apple Silicon原生构建；M4人工验收和Developer ID公证未完成。
