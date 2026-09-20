# 桌面三国·小城志

**产品规格：PRD v0.4「长期养城·轻决策」｜现有代码：visual-0.2 / core-0.1**

城池一点点变好，军团慢慢壮大；玩家只在重要方向上做决定。

本次是需求重排，不是运行版本升级。优先做真实建设、街区成长、低频决策和自动整军，再扩展多城、培养、收藏与现实联动。60—90日是首轮调参观察范围，不是已通过的长期测试或强制通关期限。

## 阅读入口

- [PRD v0.4：城池成长与轻量玩法](docs/PRD.md)
- [架构影响与现有代码边界](docs/ARCHITECTURE.md)
- [重新排序的开发工作包](docs/IMPLEMENTATION_PLAN.md)
- [40项v0.4验收计划](docs/ACCEPTANCE.md)
- [设计参数与观察场景](spec/city-growth-v0.4.json)
- [当前编码状态](docs/BUILD_STATUS.md)
- [人物动画说明](docs/ANIMATION.md) / [构建说明](docs/DEVELOPMENT.md)
- [历史PRD v0.3](docs/reference/PRD-v0.3.md)

## 当前可运行内容

基础生产、太守调岗、部分任用与经验、存档，以及2D人物与街景表现已经有源码。真实建筑项目、长期城建、军团养成、30日离线和成长册仍待实现。原70项Swift测试与Mac构建记录是visual-0.2的证据，不代表v0.4验收通过。M4实机交互和能耗仍未测试，开发包未公证。

```sh
# 在 sanguo-town 目录内
python3 scripts/validate_spec.py      # v0.4文档/规格检查，不运行游戏
swift test                          # 现有源码测试，不覆盖新需求
swift run SanguoCLI --hours 6 --policy trade
swift run SanguoPreview dist/animation-preview
# 以下仅macOS：
swift run SanguoMac
bash scripts/build-macos.sh
```

新参数文件不是现有游戏自动加载的配置。现有客户端离线上限仍为7日，本版提出30日目标。旧`spec/prototype-config.json`、`spec/acceptance-cases.json`、`docs/static-validation.json`、`MANIFEST.json`保留历史身份，不作为当前规格或代码校验清单；旧脚本在Git历史中可查。

默认不采集输入、不联行情，游戏不读取工作文字或真实账户。源码只在本目录；本轮不修改原诗词游戏、Sources、Swift测试和CI工作流。Word阅读版在对话单独交付，Git保存Markdown和规格文件。
