# 开发与运行说明

## 1. 工具链

核心使用Swift 6语言模式、Swift Package Manager，无第三方依赖。当前实际验证工具链为Swift 6.2.1 / Linux x86_64；它不是Mac应用兼容性结论。M4 Mac使用包含Swift 6工具链的Xcode，确认`swift --version`与`xcode-select -p`指向正确开发环境。最低macOS目标暂定15。

从仓库根目录进入`sanguo-town`，或者在Xcode中打开本目录的`Package.swift`。不要运行仓库原诗词项目的npm发布脚本；两个项目互不依赖。

## 2. 自动化测试

```sh
cd sanguo-town
swift test
swift test -c release
python3 scripts/validate_spec.py
```

前两条是同一套运行测试的不同构建模式；第三条只是历史PRD静态检查。输出中的XCTest “0 tests”之后还有Swift Testing结果，以最终“40 tests passed”为本批计数，不把不同测试框架的标题混淆。

## 3. 无图形演示

```sh
swift run SanguoCLI --hours 6 --policy trade
swift run SanguoCLI --hours 6 --policy industry
swift run SanguoCLI --one-city --hours 24 --policy supply
swift run SanguoCLI --hours 6 --save /tmp/sanguo-demo/world.json
```

默认三城演示会由荀彧任都督，按适配任用同城太守。样例不包含战争、物流、卖货或开新城，因此国库不应凭空增加。输出中的资源是真实规则计算结果，不是预写剧情。

`--save`只写你给出的路径；存在有效档时继续该档，不强制重置。不要把演示档放进Mac正常开发存档目录。参数错误、损坏档或不支持版本返回非零退出码。单次推进超过七天按休整规则处理，不承诺全年经济仿真。

## 4. Mac窗口骨架

```sh
swift run SanguoMac
```

提供主公府、城市概览和菜单栏。默认正常一城开局，显示当前岗位、资源、五维中的关键项与职业经验；主公可以更改施政方针。首批无建造按钮，未完成的模块不伪装成可玩。

关闭窗口不等于退出；菜单栏可重新打开。Command-Q／退出菜单会等待已有快照保存。存档路径由系统Application Support目录生成，子目录为`SanguoTown-Development/world.json`。没有键盘、屏幕或行情权限请求。

## 5. 本机开发.app

```sh
bash scripts/build-macos.sh
open dist/SanguoTown-Development.app
```

脚本只在Apple Silicon Mac运行，生成本机ad-hoc签名的开发包；不是Developer ID签名、公证发行包，不应作为正式安装器分发。不要关闭Gatekeeper、SIP或公司管理策略来绕过失败。M4机型、内存、系统版本、SDK与错误信息需写入后续实测记录。

## 6. 存档故障恢复

主档损坏时应用显示错误，不自动新建或默默回滚。退出程序后先完整复制存档目录，再检查`world.json.bak1`到`bak3`。备份仍是相同结构，可由`SaveStore.decode`检查；明确选择有效备份后再将它复制为主档。不要边运行边覆盖文件。

原型不处理跨设备同时编辑，也不声称校验值是防作弊或加密。凭证、按键明细和真实投资信息不属于游戏存档。

## 7. 维护规则

规则变更同时更新`WorldState.currentRules`、测试和架构差异说明；已有存档不按未知新规则勉强运行。跨城调任必须先实现旅行与交接，不能移除拒绝判断换成瞬移。新增对外动作必须经过GameEngine权限和事务入口。

保持所有变更在`sanguo-town/`内。当前没有新增Actions工作流，也没有宣称远端CI通过。CI后续启用时用只读仓库权限、无需发行密钥的核心测试；签名与发布单独审查。
