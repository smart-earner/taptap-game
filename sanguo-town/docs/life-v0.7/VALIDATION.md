# v0.9 规格验证记录
日期：2026-09-21。范围仅当前完整PRD、参数、引用、基础算术和反例；未执行v0.9 Swift运行验收。
命令：`python3 scripts/validate_hero_town_v09.py`。
结果：379项静态检查通过，0失败，含12项负面变体；application_cases_executed=0，GC01—GC28均NOT_RUN。
[机器报告](hero-validation.json)记录spec SHA256与逐条结果。
本地全文：`dist/prd-v09/PRD-v0.9-complete.md`，含总入口、全部11个原路径分章及完整参数。
CI优先检查v0.9；历史v0.8的403项静态成绩只在[归档](../reference/baseline-0259545/life-v0.7/VALIDATION.md)保留，不并入当前成绩。
培养明确为玩家手动：升星、分解、兑换不由太守或离线执行。静态通过不代表概率分布实测、经济节奏或游戏已实现。
