# 桌面三国·小城志

> 人物设计已更新为PRD v0.7.1：政治、智力、武力、统率＋每将1—5个标准技能引用；详见[能力规范](docs/life-v0.7/06A_ATTRIBUTE_AND_SKILL_SYSTEM.md)。这次是规格与Python参考结算更新，Swift游戏仍town-0.5＋desktop-0.1，尚未接入新能力系统。

**最新研发规格：PRD v0.7.1｜当前可运行：town-0.5＋desktop-0.1**

城池一点点变好，军团慢慢壮大；玩家只作方向、重要用人和重大扩张决定。

## 阅读最新完整PRD

- **[PRD v0.7完整入口](docs/PRD.md)**：十章规范、四份JSON及明确的开发验收。
- [城市成长与建设](docs/life-v0.7/01_CITY_GROWTH.md)：容量、入住、服务与需求驱动升级。
- [农牧加工](docs/life-v0.7/02_PRODUCTION.md) / [工种与物流](docs/life-v0.7/03_AGENTS_AND_LOGISTICS.md) / [饭食与财政](docs/life-v0.7/04_FOOD_AND_ECONOMY.md)。
- [太守、都督和三城](docs/life-v0.7/05_GOVERNANCE_AND_REGION.md) / [六将、收藏和军团](docs/life-v0.7/06_HEROES_COLLECTION_AND_ARMY.md)。
- [四条特色工程与常驻内容](docs/life-v0.7/07_CONTENT_AND_PROGRESSION.md) / [全桌面、美术和交互](docs/life-v0.7/08_DESKTOP_UI_AND_ART.md)。
- [工程、迁移和72项验收](docs/life-v0.7/09_ENGINEERING_AND_ACCEPTANCE.md) / [规格验证状态](docs/life-v0.7/VALIDATION.md)。

v0.7是下一版完整开发依据，不是对已实现软件改一个版本号。真实任务生产、全桌面生活地图、昼夜作息、饭食满意度、新武将效果及逐车新城仍需按V1—V5实际实现。所有新应用验收尚未运行，不能沿用旧201项运行测试给新规则背书。

```sh
cd sanguo-town
python3 scripts/validate_prd_v07.py --output dist/prd-v07
python3 scripts/check_prd_v07_delivery.py --output dist/prd-v07
```

以上输出完整阅读HTML/Markdown、数值和跨章报告、独立容量参照与NOT_RUN应用验收计划。不是Swift游戏仿真。旧v0.6入口原文归档，历史规格CI固定检出其原提交，避免混用新旧文档。

## 当前客户端

[桌面模式原型的使用与边界](docs/PRD_DESKTOP_MODE.md) / [已实现状态](docs/BUILD_STATUS.md) / [实际桌面测试报告](docs/desktop-test-report.json)。

现有desktop-0.1显示透明、无标题栏、鼠标穿透的局部桌面城景，不改壁纸，普通窗口在前，菜单栏管理。首次默认关闭，普通城景按钮“融入桌面”可开启；屏幕、关注城市、大小、位置在设置中调节。它还不是v0.7的完整1920×1080参考生活地图。

```sh
# macOS 15及以上、Apple Silicon和Swift6 / Xcode SDK：
swift run SanguoMac
bash scripts/build-macos.sh
# 核心回归（并不验证新PRD尚未实现的规则）：
swift test
```

现有运行源码验证为`abaaed75c66861dcb4542a242f312d330439eb95`及其未更改的后续文档提交。[原生测试run35516594162](https://github.com/smart-earner/taptap-game/actions/runs/35516594162)验证了当时的201项测试和Mac开发包；不是本轮新生活层的测试结果。

用户M4上的真实Finder点击、多屏、Spaces、台前调度、睡眠及能耗仍未完成验收。开发包ad-hoc签名、未公证。桌面原型受透明图标层遮挡报告影响，不保证被工作窗口覆盖时零渲染；可手动暂停。未接入键盘或行情采集。

本次只有PRD、配置与规格脚本/只读CI更新，没有修改Swift运行代码和原诗词游戏。不要以旧的演示包代替新生活版交付。
