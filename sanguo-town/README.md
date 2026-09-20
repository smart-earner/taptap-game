# 桌面三国·小城志

**town-0.4 开发版｜Mac / Apple Silicon｜PRD v0.4**

城池逐渐变好，玩家只在重要方向上决定。已实现太守持续建设、真实施工、分阶段街区、军团渐进整备、基础收藏和地区合作；不是全部PRD或正式发行版。

## 开始

需要macOS 15及以上、Swift 6 / Xcode工具链。直接运行与本机打包：

```sh
cd sanguo-town
swift test
swift run SanguoMac
# 或生成ad-hoc开发.app（未公证）：
bash scripts/build-macos.sh
```

进入城市窗口，接受长期治理。已有growth存档可在主公府选择“启用长期街区发展”，资产保留；不要在文件里手改规则版本。主公府中的收藏、人事、地区合作均为可选详情，日常建设无需逐项确认。

## 文档与证据

- [当前可玩内容与限制](docs/TOWN_0_4.md)
- [实际开发和测试状态](docs/BUILD_STATUS.md)
- [分批上传进度](docs/UPLOAD_PROGRESS.md)
- [PRD](docs/PRD.md) / [架构](docs/ARCHITECTURE.md)
- [代码](Sources) / [测试](Tests)
- [151项原生测试、90日矩阵与开发包构建](https://github.com/smart-earner/taptap-game/actions/runs/35509429163)

## 加速验证，不等于真实试玩

```sh
swift run SanguoGrowth --town --matrix --output dist/town-matrix
swift run SanguoGrowth --town --days 90 --cadence 3 --legion 60 --output dist/town-preview
```

浏览器打开`dist/town-preview/city-growth.html`看同一存档各时点城景；不是Mac实机录像。省略`--town`运行旧growth切片，不能混称新版测试。

## 边界

地区战斗目前是有限军力检验，不是完整战术战场；新城通过预付合作合同接纳，不含逐车施工；贸易仅有粮食援助与渡口酒出口，未覆盖全部商品。坐骑已有收藏与配备登记，骑乘动画未完成。完整培养、精修美术、按键和行情仍待开发。没有任何工作文字采集或真实证券下单。

151项是不同运行测试的总数，Debug/Release和不同平台的复验不相加。M4实机GUI、能耗与正式签名公证尚未验收。旧MANIFEST仅记录早期文档上传，不是当前代码校验清单；checkpoint目录只是可追溯备份。

所有游戏源文件在本目录。根目录原诗词游戏不变；`.github/workflows`仅增加本项目的构建与源文件备份任务。
