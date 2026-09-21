# 桌面三国·小城志

**实际运行：life-0.7.2-v1 单城生活试玩｜设计基线：PRD v0.7.2｜旧版 town-0.5 / desktop-0.1 保留**

这次包含真实Swift运行代码和原生Mac界面，不是只有PRD。第一段生活链：粟的播种/浇灌/成熟/收割 → 实体搬运 → 厨房加工 → 居民实际消费；另有基础建设、真实入城、夜巡、开城木印、30将宝鉴与统一招募状态机。

## 入口

- [本批能玩什么、怎么打开、哪些仍未完成](docs/LIFE_V072_V1.md)
- [实际完成度与测试](docs/BUILD_STATUS.md) / [机器可读报告](docs/life-v072-test-report.json)
- [完整PRD](docs/PRD.md) / [资源精简与30将设计](docs/SLIM_V0_7_2.md)
- [生活核心源码](Sources/SanguoLife) / [只读城景](Sources/SanguoLifeVisual) / [21项新增测试](Tests/SanguoLifeTests)

## 打开试玩

macOS15及以上、Apple Silicon。开发包只有ad-hoc签名，未公证，不要关闭系统安全保护。

打开应用，在菜单栏选择 **城市生活 · 新版试玩**；首次点击 **接受默认保供 · 开始生活版小城**。在新窗口点 **铺满桌面**显示完整桌面层城景；需要管理时仍在这个普通窗口操作。原菜单中的主公府、旧版城景、成长册和旧桌面设置仍属于旧存档，不控制生活版。

新生活版使用独立 `~/Library/Application Support/SanguoTown-Life072/world.json`，不会自动迁移或覆盖 `SanguoTown-Development` 中的原城。老存档升级、完整备份恢复界面和正式发行格式仍需后续验收。桌面模式默认关闭；本批显示选择尚不跨重启持久化。

```sh
cd sanguo-town
python3 scripts/export_life_catalog.py --check
swift test
# 实际单城模拟，不是规格算术检查：
swift run -c release SanguoLifeCLI --seconds 86400 --cadence 120 --seal --preview --output dist/life-day1
# 仅macOS：
swift run SanguoMac
bash scripts/build-macos.sh
```

`export_life_catalog.py`从受校验的0.7.2设计生成随应用分发的8物资/4配方/30人物/22技能配置。不是客户端启动时访问网络。构建脚本将配置放入.app并自检，离开开发源码目录仍可读取。

## 已验证与范围

[实际Mac运行35560805806](https://github.com/smart-earner/taptap-game/actions/runs/35560805806)：macOS15.7.9 arm64 / Xcode16.4 / Swift6.1.2；原有201项+新增生活21项=222项，Debug与Release均通过；原生界面编译、开发包、搬迁后的配置读取与签名校验通过。一天与七天模拟已执行；一天按120秒与86400秒查看，最终世界JSON一致。Linux同一日终状态也一致。

**这不是全部PRD完成。** 目前没有生活版养猪/肉源、完整军团、装备、通用跨城、完整特色路线和30名独立精修造型；部分武将发现所需设施尚未接齐。30人目录已实际加载，不等于所有获取条件或美术均已完成。旧版长周期测试不能代替生活版90日验证。用户M4实际窗口、桌面合成、能耗和长时体验尚未验收。

临时源码传输检查点和有写入权限的集成工作流已移除；历史提交保留，日常CI只读测试打包。仓库根目录原诗词游戏未改。
