# 桌面三国·小城志

**town-0.5 · 城市特色、分区城景与可解释治理｜PRD v0.5**

城池一点点变好，军团慢慢壮大；玩家只在重要方向上做决定。

这一批实现分项工程前置、五方针街区目标、16地块错落分区、太守事实规划记录与显式版本迁移。既有建筑、街区、人物和收藏保留；改方向只影响之后的投入，不瞬间换皮或拆城。仍是开发版，不是全部PRD已完成。

## 入口

- [PRD v0.5](docs/PRD.md) / [架构增量](docs/ARCHITECTURE.md)
- [本版玩法、入口与边界](docs/CITY_IDENTITY.md)
- [当前开发状态](docs/BUILD_STATUS.md) / [实际测试结果](docs/identity-test-report.json)
- [开发优先级](docs/IMPLEMENTATION_PLAN.md) / [分批交付记录](docs/UPLOAD_PROGRESS.md)
- [源代码](Sources) / [运行测试](Tests) / [构建说明](docs/DEVELOPMENT.md)

## 使用

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

新开局接受长期治理后采用新规则。旧存档保留原规则，进入主公府可明确确认升级；不自动重建存档。当前城市布局采用版本2，旧历史留影继续采用原布局。改方向与查看规划位于一个可展开面板，不是新的每日待办。

命令行`--identity`为town-0.5；`--town`为旧town-0.4；都不指定为growth-0.3。不要用旧版本的结果代替新版测试。HTML展示实际状态，不是M4录像。

## 验证与限制

[原生验证 run 35512949802](https://github.com/smart-earner/taptap-game/actions/runs/35512949802)：macOS 15.7.9 arm64／Xcode16.4／Swift6.1.2，Debug178项与Release同一178项通过，45个长期检查点、38项静态规格核对通过，开发.app已构建。被测源码为`c6b16c0d342ce74b708d989baa85dc883a259b13`；后续交付提交仅补文档与只读CI。

已有151项回归＋本次27项（特色规则14、布局兼容13），不能将Debug、Release、多平台复验相加。Linux Release178项及45点结果与Mac一致。M4 GUI、多屏、能耗、签名公证与完整产品体验仍未验收。

后期现金积累、普通建筑组合趋同、通用物流、自动跨城人事、完整战斗、骑乘及现实联动仍待完善。更换多个方针可以逐步建设综合城，不宣称路线永久互斥。固定方针的发展结果已有实际差异。

三国代码独立放在本目录；原诗词游戏页面与代码不改。临时写入型集成工作流已移除，日常CI只读构建和导出，不会自动改写主分支。
