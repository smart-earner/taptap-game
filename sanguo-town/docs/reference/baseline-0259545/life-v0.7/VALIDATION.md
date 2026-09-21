# v0.8 规格验证记录
日期：2026-09-21。范围：完整原路径PRD、参数、引用、静态算术与反例；**未运行v0.8 Swift引擎**。

- 静态合同校验：403通过，0失败，含7项非法配置反例。
- 原GitHub基线归档：15份正文逐字节与3f89632相同，另保留本历史验证记录。
- 30将：5起始、25招募，六模板、五层人数门槛静态可达；这不是物资/时间/床位动态可达的证明。
- 应用HT01—HT32：32项NOT_RUN；UX01—UX08：8项NOT_RUN。
- 配方、报价、睡眠窗口、容量、依赖hash与当前文档相对链接校验通过；没有因此声称长期平衡或人物美术完成。

复现：`python3 scripts/validate_hero_town_v08.py`。生成：
- `dist/prd-v08/validation.json`：逐项证据与未运行用例。
- `dist/prd-v08/PRD-v0.8-complete.md`：总入口、11个分章、全部JSON的单文件本地研发副本。

旧v0.7检查脚本仅适用于旧提交；CI遇到v0.8配置改跑v0.8合同，同时继续跑锁定四维技能参考测试。历史验证记录见[原文](../reference/baseline-3f89632/life-v0.7/VALIDATION.md)。当前游戏交付范围仍见[BUILD_STATUS](../BUILD_STATUS.md)。
