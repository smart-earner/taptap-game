# 桌面三国·小城志

**town-0.5 · 城市特色、分区城景与可解释治理｜PRD v0.5**

城池一点点变好，军团慢慢壮大；玩家只在重要方向上做决定。

本版实现分项工程前置、五方针街区目标、16地块错落分区、太守事实规划记录与显式版本迁移。既有建筑、街区、人物和收藏保留；改方向只影响后续投入，不瞬间换皮或拆城。仍是开发版，不是全部PRD已完成。

## 入口

- [PRD v0.5](docs/PRD.md) / [架构增量](docs/ARCHITECTURE.md)
- [本版玩法与边界](docs/CITY_IDENTITY.md)
- [开发状态](docs/BUILD_STATUS.md) / [实际测试报告](docs/identity-test-report.json)
- [实施计划](docs/IMPLEMENTATION_PLAN.md) / [分批交付](docs/UPLOAD_PROGRESS.md)
- [源码](Sources) / [测试](Tests) / [构建说明](docs/DEVELOPMENT.md)

## 运行

```sh
cd sanguo-town
swift test
python3 scripts/validate_spec.py
swift run -c release SanguoGrowth --identity --matrix --output dist/identity-matrix
swift run -c release SanguoGrowth --identity --policy trade --days 90 --cadence 3 --legion 60 --output dist/identity-preview
# 以下要求macOS SDK：
swift run SanguoMac
bash scripts/build-macos.sh
```

新开局接受长期治理后采用新规则；旧存档在主公府明确确认升级，拒绝不丢存档。当前城景采用分区布局，旧留影仍使用原布局。暂停后点击“恢复原有治理”延续原方针、预算和工程，不创建新的授权额度。

`--identity`为town-0.5；`--town`为town-0.4；都不指定为growth-0.3。不要用旧规则结果代替本版测试。HTML是实际状态导出，不是M4录像。

## 验证

最终被测运行代码：`19a8ffd9c0a47d0b2a8de74a48df462a2c449f33`。

[最终Mac复验 run 35513614059](https://github.com/smart-earner/taptap-game/actions/runs/35513614059)：macOS15.7.9 arm64／Xcode16.4／Swift6.1.2，Debug178项与Release同一178项通过；45个长期检查点、38项静态规格核对通过；含暂停恢复修正的开发.app已构建。原城景集成验证为[run 35512949802](https://github.com/smart-earner/taptap-game/actions/runs/35512949802)。

178项为151项旧回归＋27项新规则／布局测试。恢复问题扩充了既有测试，不重复计数。Linux最终Release同套178项通过，固定输入的45点结果与Mac一致。后续交付提交只刷新文档并删除临时写入工作流，不改变被测运行代码。

## 边界

后期现金积累、普通建筑组合趋同、通用物流、都督自动跨城任用全流程、完整战斗、骑乘及现实联动仍需完善。分区是固定矢量模板，不是最终美术。反复主动转型可形成综合城，路线不是永久互斥。

用户M4窗口、多屏、睡眠和能耗仍未实测；开发包仅ad-hoc签名，未公证。测试总数不是全部PRD通过率。

原诗词游戏代码与页面保持不变。三国日常CI只读构建和导出，临时写入型集成工作流已删除，不会自动修改主分支。
