# PRD v0.5-d1 · 桌面融入模式增补

2026-09-20。对应桌面表现原型desktop-0.1；经营规则仍为town-0.5。本页补充PRD第17章，不宣布全部游戏或桌面兼容性验收完成。

> **下一版设计更新（未实现）：** 用户已改为整张桌面城市，增加工种协作、食物服务、昼夜作息和更高人数预算。参见[PRD设计增补 v0.6-draft｜全桌面城市生活与工种协作](PRD_CITY_LIFE.md)。新设计取代以下小城条的未来默认目标；本页仍准确记录desktop-0.1已经实现的行为，不能据此声称全桌面、96人或昼夜已经上线。

## 目标与操作

保留用户原壁纸，在壁纸层与图标层之间显示透明、无标题栏的小城。普通工作窗口在城景之前。首次默认关闭；玩家从城景窗口点击“融入桌面”，或从菜单栏选择“开启桌面融入模式”。管理、授权与调位置仍在普通窗口完成，不把桌面变成审批面板。

一块选定屏幕、一个选定城市、一个只读显示实例。菜单栏支持启用/隐藏、设置和动画暂停。设置支持屏幕、城市、宽度、水平与垂直位置以及左下/下方居中/右下预设。宽度初始780点，限定360—1440点并按实际屏幕可用范围缩小，不使用物理像素混算。保留12点边距，避开visibleFrame排除的菜单栏和Dock区域。

默认全程鼠标穿透，窗口不能成为key或main窗口，不用桌面上的按钮或拖拽区抢文件操作。暂不支持直接点击建筑、置顶浮窗或多屏同时复制显示。Settings里点“返回普通窗口”会关闭桌面模式；关闭设置窗本身不退出游戏。

## 状态与隐私

仅新增UserDefaults中的显示偏好，不写入WorldState，不新建GameSession或模拟心跳，不改生产、经验、军团或收藏。屏幕断开临时回退到可用主屏，保留原屏幕ID以便重连；无可用屏幕则隐藏。选择已失效城市时使用现存首城，不生成演示资产。

设置损坏回退到关闭状态；启用偏好、位置和大小随应用重启保留，但本原型不强行干预系统恢复普通窗口的行为。退出撤销动态层，不恢复/重设壁纸，因为本就没有改壁纸。无新增登录启动项，无辅助功能、输入监控或录屏权限，无壁纸图片/桌面文件/其他工作窗口读取。

## 表现与能耗边界

SpriteKit背景透明、隐藏人物名和建筑等级文字；移除整块天空山景，保留实际城池土地、道路、建筑、居民与阴影。地面仍为初版模块化矢量边缘，不是完整美术重制。

桌面上限12fps，低电量模式6fps；遵循减少动态效果。应用隐藏、窗口收起、系统睡眠/会话停用时暂停渲染。Finder透明图标层可能造成保守的遮挡报告，桌面模式暂不以occlusionState单独停画面；不读取其他窗口来判断。因而不能承诺被工作窗口盖住时完全零渲染，提供手动暂停/隐藏作为明确控制。

使用公开desktopWindow/desktopIconWindow层级与canJoinAllSpaces、stationary、ignoresCycle。未请求fullScreenAuxiliary或canJoinAllApplications。此为原型的分层意图，实际Finder、Show Desktop、Spaces、台前调度和不同macOS版本仍须实机验收；不保证覆盖全屏或锁屏，不保证屏幕共享隐身。

## 原型验收状态

原生测试覆盖7项窗口对象行为；跨平台测试新增16项，包括偏好回读、位置夹取、负原点外接屏、无屏回退、透明背景与只读渲染。完整测试、构建与日志见desktop-test-report.json。上述测试不代替M4的桌面图标点击、拖拽、显示桌面、多屏插拔、锁屏、合盖、长时间能耗与系统恢复窗口测试。

Mac包最低macOS15、Apple Silicon；ad-hoc开发签名，未Developer ID公证。系统阻止时不要关闭安全保护，保留普通窗口备用或按开发文档从源码本机构建。

公开API依据：[窗口层级](https://developer.apple.com/documentation/coregraphics/cgwindowlevelkey)、[NSWindow鼠标与焦点](https://developer.apple.com/documentation/appkit/nswindow)、[SpriteKit透明合成](https://developer.apple.com/documentation/spritekit/skview/allowstransparency)、[stationary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/stationary)。
