# 桌面三国·小城志

**desktop-0.1：可选桌面融入模式｜经营规则town-0.5｜PRD v0.5及桌面增补**

城池一点点变好，军团慢慢壮大；玩家只在重要方向上做决定。

本批新增透明、无标题栏、鼠标穿透的桌面城景。保留原壁纸；普通窗口在前，管理从菜单栏进入。默认关闭，点击普通城景中的“融入桌面”，或菜单栏“开启桌面融入模式”。位置、大小、屏幕和关注城市在“桌面城景设置…”调整；随时回到普通窗口。不是始终置顶，也不是更换系统壁纸。

## 入口

- [桌面模式需求、使用方法与兼容边界](docs/PRD_DESKTOP_MODE.md)
- [PRD v0.5](docs/PRD.md) / [架构](docs/ARCHITECTURE.md)
- [town-0.5玩法与边界](docs/CITY_IDENTITY.md)
- [最新开发状态](docs/BUILD_STATUS.md) / [桌面测试报告](docs/desktop-test-report.json)
- [原经营测试报告](docs/identity-test-report.json)
- [源码](Sources) / [测试](Tests) / [构建说明](docs/DEVELOPMENT.md)

## 运行

```sh
cd sanguo-town
swift test
python3 scripts/validate_spec.py
# macOS15及以上、Apple Silicon、Swift6 / Xcode：
swift run SanguoMac
bash scripts/build-macos.sh
```

首次从普通窗口接受治理，新显示模式不会自动迁移旧存档。开城后点“融入桌面”；露出桌面即可查看。需要决定方向时从菜单栏打开主公府。只改显示偏好，不改WorldState，不重复计算收益。仅一块屏幕显示一个选定城市。重启记住偏好，但不强行阻止系统恢复普通窗口。

## 本批实际验证

被测源码：`abaaed75c66861dcb4542a242f312d330439eb95`。

[macOS原生run 35516594162](https://github.com/smart-earner/taptap-game/actions/runs/35516594162)：macOS15.7.9 arm64／Xcode16.4／Swift6.1.2，Debug201项与Release同套201项通过，45个经营检查点通过；原生客户端和开发.app构建成功。201=既有178＋跨平台显示16＋原生窗口对象7。Linux只执行其中194项，不含AppKit窗口测试。

## 明确边界

这是桌面层原型，不是全部游戏或发行验收完成。窗口层级、鼠标穿透属性及面板复用已做原生对象测试；用户M4上的实际壁纸合成、桌面图标拖拽、Spaces、台前调度、全屏、睡眠和能耗仍待实测。透明图标层使遮挡检测不完全可靠，桌面模式12fps（低电量6fps），可手动暂停；不承诺被工作窗口完全覆盖时零渲染。

不读取壁纸图像、桌面文件或工作窗口，不请求输入监控或录屏。没有新增键盘与行情联动。开发包只作ad-hoc签名，未公证，内部经营版本仍0.5.0。系统阻止时不要关闭安全保护，可按构建说明从源码本机构建。

后期经济、通用物流、都督完整跨城任用、完整战斗、骑乘与培养分支仍是既有待办；本批未修改这些规则。原诗词游戏页面与源码不变，CI保持只读。
