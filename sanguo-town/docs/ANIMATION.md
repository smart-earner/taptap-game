# 人物与街景实现说明 · visual-0.2

## 本次交付

这是已经写入源码的2D分层矢量人物，不是头像平移，也不是3D模型。原创几何造型包括发髻／冠帽、五官、袍服／铠甲、腰带、披风、双臂、双腿与靴子。三种外观为文官、武将和工匠。

同一套Swift数据驱动两种输出：Mac客户端通过SpriteKit绘制；SanguoPreview导出HTML／SVG用于无Mac环境的造型与动作检查。HTML不是M4实机录像，也不能证明Apple SDK构建通过。

## 已实现的动作和交互

- 待机呼吸与眨眼；左右行走、停步和转向。
- 读简、挥锤、搬运、耕作、伐木、挥兵器的简易骨架姿态。
- 手持物绑定到前臂下的手部节点；工作时切换相应工具。
- 动作样板中可试装长枪／佩剑／空手；这里只修改外观，不发放或装备真实收藏。
- 文官／武将／工匠从起点沿预设道路前往目的地，停留工作后返回。没有合法路径就等待，不直线穿建筑。
- 用脚底所在的地面坐标排序，人物能被前景树木遮挡。首版仍是三分之四侧视的左右镜像，不含前后八方向逐帧素材。

骑乘、马匹骨架、完整战斗命中、角色专属立绘及正式收藏装备读取不在本批。动画里的挥击不会制造实际伤害。

## 真实城景与样板分开

城市概览默认读取真实WorldState：只展示选中城市的居住人物，依据当前岗位生成少量居民代表。代表ID以`representative:`开头，不加入核心人物列表，不增加人口，不冒充已经制作了每位劳动居民。

当前core-0.1尚无完整建筑实例，城景按照jobCapacity投影设施示意。没有器材产能的正常开局不会凭空出现已建工坊，而显示预留地。正式建筑系统接入后，应把设施投影改读建筑实例，而不是保留两套判定。

`动作样板`是独立TownProjection.demo。样板人物和工坊都是演示内容，界面持续标记“不改存档”。切换城市或样板会清理旧演员；刷新同一快照不重置人物的行走进度。未展示的人物不会因此失去核心工作能力。

岗位活动是表现抽象，不是每次挥锤即产生一件器材。生产、人物经验、时间补算仍只由SanguoCore结算。暂停动画、关闭城景、观看预览不能增加或扣除资源。

## 文件职责

| 文件 | 职责 |
| --- | --- |
| Sources/SanguoPresentation/VectorArt.swift | 与平台无关的几何树、变换、SVG序列化 |
| Sources/SanguoPresentation/CharacterRig.swift | 三种造型、关节骨架、动作与手持物切换 |
| Sources/SanguoPresentation/TownPresentation.swift | 只读投影、确定性道路搜索、演员状态机 |
| Sources/SanguoPresentation/TownArt.swift | 街景、设施、前景遮挡与同源SVG输出 |
| Sources/SanguoMac/TownScene.swift | SpriteKit适配、节点复用、可见性暂停 |
| Sources/SanguoPreview/Preview.swift | 导出36秒可暂停、拖动的离线预览 |
| Tests/SanguoPresentationTests/PresentationTests.swift | 30项表现层自动化测试 |

## 状态与时间

演员循环：待机 → 沿道路行走 → 目的地工作／停留 → 返回 → 原地休息。动画时间使用可见帧间隔，拒绝大于0.25秒的间隔；睡眠或长时间被遮挡后不会极速回放漏掉的小时数。步态相位由累计路程驱动，不依赖渲染帧计数。

Mac视图默认30FPS，在检查到低电量模式时设为15FPS。关闭、最小化、完全遮挡、应用隐藏、睡眠、用户会话失活或手动暂停时暂停视图；恢复时清空上一帧时间。失去键盘焦点不等于隐藏，故正常办公时可见的小城仍能活动。

系统减少动态效果开启时静态展示；菜单栏仍可访问。该代码已经通过macOS arm64编译；窗口交互、真实遮挡事件与能耗仍需实机验收，不能用编译或Linux测试代替。

## 运行

在`sanguo-town/`目录：

```sh
swift test
swift run SanguoPreview dist/animation-preview
# 打开 dist/animation-preview/animation-preview.html，无外部脚本、字体或网络请求。
# 需要逐帧素材时加 --frames，生成360个SVG帧。
swift run SanguoMac
# 菜单栏 → 显示城市概览 → 动作样板
```

HTML预览的前18秒选择长枪，后18秒选择佩剑；工作期间手持物自动切为工具。SVG姿态总览还包含挥击与搬运等动作。Mac中的试装下拉菜单可主动切换。

## 测试范围和证据

本批本地环境为Swift 6.2.1、Linux x86_64。Debug下40项原核心测试＋30项表现测试通过；Release复验仍为同一70项，不算140项不同测试。浏览器预览通过Linux Chromium检查，无JavaScript错误、无外部请求，测试暂停／拖动及减少动态效果。

新测试覆盖：关节ID与造型一致、手持物切换、有限姿态、走路左右腿交替、路径不可达、移动步长、工作后返回、刷新不重置、演员移除无残影、城市隔离、岗位代表、无工坊时不显示、暂停与睡眠、表现不改变世界数据。

GitHub工作流`.github/workflows/sanguo-town-macos.yml`只针对三国目录的变化，运行macOS arm64测试、SanguoMac构建和本地开发包打包，保存日志与预览。工作流定义存在不等于运行成功；实际状态以对应Actions run为准。开发包仅ad-hoc签名，没有Developer ID公证，不宣称为正式发行包。

原100项完整游戏验收仍未因人物样板而标为通过。多城物流、建设升级、战役、完整收藏和培养树保持原有待开发状态。原MANIFEST.json是最初PRD入库清单，不是当前源码的完整清单。

## 平台参考

- Apple SKView：pause、preferredFramesPerSecond与场景显示 https://developer.apple.com/documentation/spritekit/skview
- GitHub标准运行器标签与架构 https://docs.github.com/en/actions/reference/runners/github-hosted-runners

这些来源用于平台接口与CI选择；人物造型、骨架及玩法表现是本项目原创配置。没有搬用其他游戏素材或附带字体文件。

## macOS实际复验

[Actions run 35484492023](https://github.com/smart-earner/taptap-game/actions/runs/35484492023)在macOS 15.7.9／arm64、Xcode 16.4、Apple Swift 6.1.2上完成：Debug 70项测试、Release同一70项测试、SanguoMac原生SDK编译、ad-hoc开发包打包及预览导出全部通过。被测代码提交`0dfb09fbc36523b6afd85b2a97cea1fe80b01d51`。

首轮构建发现TownScene初始化缺少override，已经修正并保留失败日志。Actions产物包含环境记录、测试日志、开发.app的ZIP和HTML预览；保留期7天，过期可在自己的Mac按本页命令重新生成。此结果不是实际M4设备上的GUI点击、睡眠／多屏或功耗验收；开发包未经过Developer ID公证。
