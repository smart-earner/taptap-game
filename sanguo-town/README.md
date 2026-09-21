# 桌面三国·小城志

**最新研发范围：PRD v0.7.2｜当前可运行：town-0.5＋desktop-0.1**

城池一点点变好，军团慢慢壮大；玩家只作重要方向、人事和扩张决定。

## 最新规格：减少系统，增加可收集内容

首版从17种物资收敛为8种，从4作物/10配方收敛为2作物/4配方；首批武将30名，但技能库仍22项、效果原语仍7种。开局仍荀彧＋15居民，不送满30将。

- **[当前PRD入口](docs/PRD.md)**：明确新规范覆盖范围与继承机制，避免新旧资源混用。
- **[收敛规范与完整30将表](docs/SLIM_V0_7_2.md)**：资源、工序、材料替换、食物、30将四维和技能、六种招募模板。
- [资源范围数据](spec/slim-v0.7.2.json) / [30将数据](spec/heroes-v0.7.2.json)。
- [继承的四维与标准技能公式](docs/life-v0.7/06A_ATTRIBUTE_AND_SKILL_SYSTEM.md)。

```sh
cd sanguo-town
python3 scripts/build_slim_v072.py --output dist/slim-v072
python3 scripts/test_slim_v072.py --output dist/slim-v072
```

生成器产出四份resolved配置及manifest；旧0.7.1配置保留原字节，作为SHA-256校验的输入，不再直接作为新生活版运行数据。未知材料或基线变化拒绝生成。不得把设计材料替换率套到玩家已有存档上。

本轮16项配置与Python参考测试通过；[只读CI run35556875019](https://github.com/smart-earner/taptap-game/actions/runs/35556875019)成功。覆盖8资源/4配方、30人/29路线、原6人不变、同数据改名能力一致、1—5技能、库存与床位等。没有执行新生活城市引擎、30人美术、长期平衡或M4能耗测试。

**这不是客户端更新。** 本轮未修改Sources、Tests或Package.swift，未接入新的资源链和武将系统。新增24人的图像、角色展示与原生接入仍有工作量，不能以目录完成代替游戏完成。

## 当前客户端及其历史证据

[桌面模式使用与边界](docs/PRD_DESKTOP_MODE.md) / [已实现状态](docs/BUILD_STATUS.md) / [原桌面测试报告](docs/desktop-test-report.json)。

现有desktop-0.1是透明、无标题栏、鼠标穿透的局部桌面城景，不修改壁纸，工作窗口在前，菜单栏管理。首次默认关闭，可在普通城景中点击“融入桌面”。它尚未变成新PRD中的完整生活地图。

```sh
# 以下要求macOS 15及以上、Apple Silicon和Swift6/Xcode SDK：
swift run SanguoMac
bash scripts/build-macos.sh
# 既有游戏回归，不验证新PRD未实现部分：
swift test
```

历史[Mac run35516594162](https://github.com/smart-earner/taptap-game/actions/runs/35516594162)验证了当时的201项测试与开发包，不是本次新资源/30将运行验收。开发包ad-hoc签名、未公证；用户M4上的真实Finder、多屏、Spaces、台前调度、睡眠和能耗未完成实机验收。未接入键盘或行情采集。

本轮工作限定在三国设计、配置、检查脚本及只读规格工作流；原诗词游戏不变。
