# 桌面三国·小城志

**PRD v0.3 · Mac M4 · 主公决策与分层治理版**

一城任太守，多城托都督；你定方向，部属把事情办成。

本目录独立保存三国桌面经营游戏的产品需求与开发资料，不修改仓库原有《数字华容道·诗词版》。目前交付的是文档、测试配置与检查脚本，**不是已经可运行的游戏**。

## 文档入口

- [完整PRD](docs/PRD.md)
- [100项应用验收计划](docs/ACCEPTANCE.md)
- [开发顺序与工作包](docs/IMPLEMENTATION_PLAN.md)
- [审查、来源与未决事项](docs/REVIEW_NOTES.md)
- [版本变化](CHANGELOG.md)
- [上传记录](docs/delivery-status.json)

## 原型配置

- [原型配置](spec/prototype-config.json)
- [三城测试初始状态](spec/three-city-fixture.json)
- [结构化验收用例](spec/acceptance-cases.json)
- [静态检查结果](docs/static-validation.json)

## 静态检查

在本目录内运行，需要Python 3.10及以上：

```sh
python3 scripts/validate_spec.py
```

检查仅涵盖配置结构、编号、容量、部分算术与文档关联，不启动游戏，也不代表通过M4实机、自治效果、经济平衡或应用验收。100项应用验收仍标记为 `not_run`。

## 范围与状态

首发设计面向macOS / Apple Silicon原生arm64，使用独立Swift模拟核心及SwiftUI / AppKit / SpriteKit界面。核心为太守经营单城、都督管理城市群与军团、主公处理重要决策，保留武将、名器与神驹收藏。按键和自选股故事为可关闭扩展，不包含工作文字采集或真实证券交易。

本次GitHub入库保存可阅读、可版本管理的文本源与配置。Word阅读版和原始ZIP为聊天中另行提供的附件，未在本目录中伪装为已上传文件。规格仍需原型及实机验证；不把设计写成已实现功能。
