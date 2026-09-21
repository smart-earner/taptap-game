# 桌面三国·小城志

新增本地试验入口：**Godot 3D 小城样板**，运行 `bash scripts/run-godot.sh`。使用独立存档及原 Swift 经营引擎；可玩范围、安装依赖和未完成项见 [Godot 样板说明](docs/GODOT_PREVIEW.md)。下文为原生活版发行说明，不代表 Godot 样板完成度。

**可运行：life-0.7.2-v2 单城生活与可选肉食供应｜PRD v0.7.2｜经典town-0.5 / desktop-0.1保留**

不是只有文档：真实居民播种、灌溉、采收、搬运、做饭、用餐、建设与夜巡。新版补齐付费购猪、实际牵入、照料、出栏、送肉到厨房和肉食饭消费，仍然只有8种资源。

## 打开体验

菜单栏 **城市生活 · 新版试玩** →首次 **接受默认保供 · 开始生活版小城** →「我的城」右侧 **让饭馆有肉菜 / 批准肉食供应…**。之后普通步骤由太守执行。牧栏和猪不会即时赠送；需要先完成饭馆，再实际建设、购买与成长。

窗口上方 **铺满桌面** 显示桌面层，鼠标穿透；管理和宝鉴仍在普通窗口。旧主公府/旧城景/旧桌面设置属于经典存档，不控制新生活版。

已有生活存档仅在明确批准养殖时升级format2；旧开发包不能打开新格式。独立路径 `~/Library/Application Support/SanguoTown-Life072/world.json`，原SanguoTown-Development城池不变。3份滚动备份不是永久旧格式归档；尚无完整恢复界面。

macOS15+、Apple Silicon。开发包ad-hoc签名，未公证；不要关闭安全保护。M4实机桌面兼容、能耗与长时体验仍未验收。

## 源码与事实状态

- [当前完成度与实际结果](docs/BUILD_STATUS.md) / [本批规则、成本和用法](docs/HUSBANDRY_V2.md)
- [养殖模型](Sources/SanguoLife/LifeHusbandry.swift) / [任务与物资接入](Sources/SanguoLife/LifeHusbandryRuntime.swift)
- [真实动物城景](Sources/SanguoLifeVisual/LifePigArt.swift) / [原生入口](Sources/SanguoMac/HusbandryPanel.swift)
- [本批与原有生活测试](Tests/SanguoLifeTests) / [机器验证报告](docs/husbandry-v2-report.json)
- [完整PRD](docs/PRD.md) / [8资源与30将设计](docs/SLIM_V0_7_2.md)

已验证源码 `2f30595bbca7678c7473f61b8ebe5bb0a9aea9d1`，[Mac运行35581321911](https://github.com/smart-earner/taptap-game/actions/runs/35581321911)。246项独立测试（原222＋新24），Debug/Release均通过；原生客户端、可搬迁开发.app、签名检查通过。2日不同查看间隔世界相同；7日真实规则仿真通过。不是全部PRD或M4人工验收。

```sh
cd sanguo-town
python3 scripts/export_life_catalog.py --check
swift test
swift test -c release
swift run -c release SanguoLifeCLI --seconds 172800 --cadence 120 --husbandry --seal --preview --output dist/husbandry
# 仅macOS15+ / Apple Silicon:
swift run SanguoMac
bash scripts/build-macos.sh
```

30人宝鉴已加载，不代表29条招募路径全已可达或30人独立美术已完成。完整军团、装备与坐骑、多城、五方针特色建设、旧城迁移等仍待开发。先前的[生活v1说明](docs/LIFE_V072_V1.md)与报告保留历史含义；当前以BUILD_STATUS为准。

本批核心、测试、界面分批上传，验证后集成；临时写入型工作流和传输检查点已清理，小提交保留在历史。日常CI只读测试和打包；仓库根目录原诗词游戏不变。
