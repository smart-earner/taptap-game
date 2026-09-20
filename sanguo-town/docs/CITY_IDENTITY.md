# town-0.5｜城市特色、分区布局与太守安排

## 已实现范围

本批在town-0.4上添加显式规则迁移，不抹去原存档。核心为CityIdentity.swift；分区画面为TownLayout.swift，界面为CityIdentityView.swift。

- 五个方针对八类街区指定不同深度。各轨至少一阶段，重点轨到三或二。旧资产不降级，已开工按原合同完成。
- 水利依农田、安居依民居、工造依工坊等相关设施。仍先建立集市收入渠道，不要求五种无关设施全齐。
- 以粮食覆盖、住房、器材与批准军团需求比较合法候选；采购和开工整体提交，被拒方案不部分花钱。
- 保存每城12条实际规划：原方针、当时负责人、依据、未选项、预留与真实完成时点。只需查看，不新增审批。
- 固定16地块采用错落分区，道路、建筑位置、深度与人物行走一致；过去快照保留过去布局。
- 太守前往官署读简，不再一律在官署与城门往返。仍是模块化矢量原型，不是商业美术完成。

## 入口

新开局首次接受长期治理直接采用新规则；旧growth或town存档在主公府查看可选升级说明，明确确认后采用town-0.5。继续旧规则不会丢存档。已经升级的城市在可展开的“城市方向与太守安排”中改方向或看最近执行。

第一次规则迁移会改变当前布局，但不重画旧留影，不把这次展示变化算成新建房屋。规则降级不可直接覆盖存档，应使用保留的旧版本备份。

## 运行

```sh
swift test
swift run -c release SanguoGrowth --identity --matrix --output dist/identity-matrix
swift run -c release SanguoGrowth --identity --policy trade --days 90 --cadence 3 --legion 60 --output dist/identity-trade
# macOS SDK:
swift run SanguoMac
bash scripts/build-macos.sh
```

--identity才是本版规则；--town保留town-0.4，省略二者为growth-0.3。HTML预览是Swift状态渲染结果，不是Mac窗口录屏。

## 明确边界

本批首先改善街区路线，不宣称普通建筑组合永久互斥。主动多次转型可逐步形成综合城；已建内容不拆除。后期现金积累、所有货品的物流、跨城自主选拔完整计划、完整战斗、骑乘、自动配备、片区相机和真实M4能耗仍需完善。

原151项基线测试加14项特色规则及13项布局／兼容测试，最终平台结果与提交依据单独记在identity-test-report.json。测试数量不是全部PRD通过率。本文件描述代码范围，不提前声称尚未完成的原生构建已经成功。
