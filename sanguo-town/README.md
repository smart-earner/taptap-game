# 桌面三国·小城志

**PRD v0.3 / 架构 v0.1 / 首批代码 core-0.1**

一城任太守，多城托都督；你定方向，部属把事情办成。

本目录独立于仓库原有《数字华容道·诗词版》。现已进入正式编码：包含可编译的Swift核心、命令行演示、40项运行测试和Mac窗口骨架。**这是G0与部分G1开发切片，不是完整游戏或已签名发行版。**

## 文档入口

- [软件架构设计书](docs/ARCHITECTURE.md)
- [当前实现与测试状态](docs/BUILD_STATUS.md)
- [开发、运行与本机打包](docs/DEVELOPMENT.md)
- [完整PRD](docs/PRD.md)
- [100项原应用验收计划](docs/ACCEPTANCE.md)
- [开发阶段](docs/IMPLEMENTATION_PLAN.md)
- [本轮运行测试报告](docs/core-test-report.json)

## 运行核心与演示

需要Swift 6工具链。Mac应用目标要求macOS 15或以上；Linux只构建核心与命令行。

```sh
cd sanguo-town
swift test
swift run SanguoCLI --hours 6 --policy trade
swift run SanguoCLI --hours 6 --policy industry
```

演示默认加载明确标注的三城测试场景，展示都督同城任免、太守岗位调整和产出差异；`--one-city`使用正常的一城代理太守开局。未指定`--save`时不写存档。完整游戏的新建城市、跨城物流、战斗、收藏与养成分支尚未完成。

## 在M4 Mac上构建窗口骨架

```sh
swift run SanguoMac
# 或制作本机开发.app（不是公证发行包）
bash scripts/build-macos.sh
```

本轮已在Swift 6.2.1 / Linux x86_64通过Debug与Release各40项Swift测试；Mac代码仅作语法解析，**未在macOS SDK编译或M4实机运行**。请按开发说明检查真实Mac构建结果，不能把Linux测试等同于Mac兼容性或能耗通过。

## 历史资料与原静态检查

```sh
python3 scripts/validate_spec.py
```

原57项静态检查仍通过，但只验证原PRD和夹具，不启动完整游戏。原100项应用验收仍为`not_run`。`MANIFEST.json`、`docs/delivery-status.json`与旧静态报告是上一批文档交付记录；本批源码以`docs/core-test-report.json`与Git提交为准，不冒充旧清单已覆盖新增文件。

核心没有联网、键盘采集、实际持仓读取或证券下单。未创建服务器，没有调用大模型。发布前仍需真实Mac测试、玩法平衡、素材和签名公证审查。
