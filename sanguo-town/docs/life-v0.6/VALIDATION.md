# PRD v0.6.0 规格交付与验证状态

日期：2026-09-20。**本次完成研发规格，不是完成life-0.6游戏实现。**

## 交付组成

- 主PRD入口与6份规范章节，覆盖生产、物流饭食、武将收藏、建设治理、工程迁移、开发验收。
- 3份JSON：life-v0.6、collections-v0.6、life-contracts-v0.6。
- 2份可重复运行的静态检查脚本。
- 70项应用验收定义，均NOT_RUN；22组可执行算术向量。
- 历史PRD v0.5及v0.6-draft原文已归档，旧运行代码不受修改。

## 已完成的验证

验证提交：`6a6db2d78428d90ab4d506141c490a3ff347dcf6`。

[GitHub Actions规格验证 run 35523287542](https://github.com/smart-earner/taptap-game/actions/runs/35523287542)成功；从其归档重新解压后，在本地再次执行两份脚本，结果一致：

| 检查 | 结果 | 不代表什么 |
|---|---:|---|
| 基础配置、引用、ID、配方与算例 | 292项PASS，0项FAIL | 不代表新Swift引擎已运行 |
| 跨章容量、归属、确定性种子与缺省契约 | 47项PASS，0项FAIL | 不代表长周期供需平衡已经验证 |
| 算术向量 | 22组，已包含在基础检查中 | 不重复计为额外应用测试 |
| 应用验收 | 70项计划，0项执行 | 全部NOT_RUN |
| M4真实桌面、能耗与交互 | 未执行 | 不沿用旧版结果冒充 |

验证产物artifact ID：10608908443；压缩包SHA-256：`0a673b793fbd4af356ff3387c2d1ca2ec6a80215c3575ad9f2b0ef869d137e1a`。CI产物有保留期限，规范、配置和脚本本身长期存于Git；产物过期后按下方命令可重建。

```sh
cd sanguo-town
python3 scripts/validate_life_spec.py --output dist/life-spec
python3 scripts/validate_life_contracts.py --output dist/life-spec
```

输出包括validation.json、contract-validation.json、golden-vectors.json、acceptance-plan.json和合并的PRD-v0.6-complete.md。acceptance-plan中的NOT_RUN不会由静态检查脚本改成PASS。

## 仍需开发验证的工作

当前运行规则仍town-0.5＋desktop-0.1。life-0.6须按L1—L4实现任务引擎、作物加工、饭食满意度、昼夜人物、六将效果、收藏与安全迁移，然后执行70项应用验收和30/60/90日运行矩阵。数值是明确的开发基线，但不是已经平衡完成的数值。

本文是交付记录，不改变之前已验证的游戏源码。新增CI仅contents: read，不自动改写源码或合并主分支。
