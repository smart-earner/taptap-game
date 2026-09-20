# 桌面三国·小城志

**visual-0.2 · Mac分层人物与街景 / 模拟规则保持core-0.1**

一城任太守，多城托都督；你定方向，部属把事情办成。

已加入文官、武将、工匠三种2D分层造型、行走／转向／工作、道路移动与前后遮挡。正常城景读取实际居城和岗位；“动作样板”独立演示、不改变存档。不是完整游戏，也不是3D角色。

## 快速入口

- [人物与动画实现、边界和运行方式](docs/ANIMATION.md)
- [软件架构书](docs/ARCHITECTURE.md)
- [当前开发状态](docs/BUILD_STATUS.md)
- [PRD](docs/PRD.md)
- [构建说明](docs/DEVELOPMENT.md)
- [源码](Sources) / [测试](Tests)
- [完整应用验收计划，仍未执行](docs/ACCEPTANCE.md)

## 运行

在本目录内使用Swift 6工具链：

```sh
swift test
swift run SanguoCLI --hours 6 --policy trade
swift run SanguoPreview dist/animation-preview
# 用浏览器打开 dist/animation-preview/animation-preview.html
# 以下仅macOS：
swift run SanguoMac
bash scripts/build-macos.sh
```

Mac菜单栏选择“显示城市概览”，可切换真实城景／动作样板、暂停动画以及样板兵器。预览HTML使用同一Swift骨架与姿态导出，不是Mac实机录像。开发包未公证。

## 验证边界

本地Linux上70项Swift测试通过（原核心40＋表现层30，Debug／Release复验同一套），HTML预览另做浏览器检查。Mac arm64上的同一70项测试也通过，SwiftUI／SpriteKit编译和开发.app打包成功：[实际Actions记录](https://github.com/smart-earner/taptap-game/actions/runs/35484492023)。M4交互、能耗、多屏与正式签名发布仍需实机验证。原100项应用验收没有因此通过。

骑乘、完整战斗动画、收藏装备实际读写与培养树尚未实现；核心建设和物流也仍待开发。人物表现不会改变经济收益或保存新角色。旧MANIFEST.json仅记录最初PRD入库，不能当作当前代码校验清单。

三国代码位于此独立目录；原诗词游戏不变。唯一目录外新增文件是只对三国路径触发的macOS CI工作流，不改原站点或发布流程。
