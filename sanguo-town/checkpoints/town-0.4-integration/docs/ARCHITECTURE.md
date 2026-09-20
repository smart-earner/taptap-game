# 架构补充 v0.2｜对应PRD v0.4

日期：2026-09-20。本稿定义下一批实现契约，不表示代码已经迁移。既有完整架构保存在[ARCHITECTURE-v0.1.md](reference/ARCHITECTURE-v0.1.md)。继续采用纯Swift单写入模拟、命令校验、SwiftUI/AppKit入口与SpriteKit表现，不重写已验证核心。

## 1. 产品变化引起的结构变化

现有TownArt从岗位容量派生设施，只能支撑示意。新城景必须由真实建筑、项目、住户和营地快照驱动。不得用“图画好了”代替建筑入账。

| 模块 | 新增责任 | 仍然禁止 |
| --- | --- | --- |
| SimulationCore | 建筑实例、项目事件、劳力/原料/输出容量预留 | 从动画帧生成经济 |
| Governance | 持续发展计划、普通项目串行/并行选择、自动再投资 | 每个工程重新问主公 |
| Presentation | 将不可变CityAppearanceSnapshot转为街景 | 写库存、写经验、补造不存在的建筑 |
| Memory | 按因果时点记录城市快照和决定引用 | 截取真实桌面或冒充历史画面 |
| LegionGrowth | 已批准编制内征募、训练、整备及营区状态 | 扩大未授权军团或敌对对象 |
| ProposalAggregator | 全势力滚动窗口、主题合并、维持现状 | 每城独立制造提醒配额 |

## 2. 命令与事件

新命令候选：SetDevelopmentDirection、StartConstruction、PauseConstruction、ResumeConstruction、CancelConstruction、ApproveLegionTarget、PinCityMemory。只有命令层可改资产；必须带commandID、expectedRevision、authorityPath、policyVersion与scopeID。

施工启动原子校验：地点和地块可用 → 类型获批 → 可支配预算与材料足够 → 劳力可分配 → 全部预留 → 持久化 → 发布事件。任一失败整笔回滚。完成时把预留转实际消费、建筑转运营、释放项目位与劳力，事件只入账一次。

事件候选：ConstructionStarted、ConstructionPhaseChanged、ConstructionPaused、BuildingOpened、NeighborhoodChanged、LegionStageChanged、CityMemoryCaptured。事件依据真实模拟工时，不依据SKAction完成回调。更改方向只重排未提交动作；在建工程按已约定的取消/交接规则处理。

## 3. 必需数据契约

BuildingInstance包含id/cityID/plotID/type/level/operationState/visualVersion。ConstructionProject包含buildingID、effectiveWork、requiredWork、inputReservation、assignedLabor、phase、policyVersion和completedTransactionID。

NeighborhoodState记录组成建筑、人口与服务证据；CityAppearanceSnapshot记录可见实例、库存档位、在城角色和暂停原因，只读。CityMemory保存不可变快照、因果时间、镜头、内容版本、事件引用，不能只存一个以后会变化的cityID。

LegionGrowthPlan保存批准编制、目标用途、现役/伤兵/在途、训练、预算、停止条件。Approval范围与实际兵力分离。DecisionBudget保存滚动72/168小时窗口和主题键，数据以模拟时间计算，不因反复开窗重置。

## 4. 时间与资源顺序

同一时点先处理到期产出/到货及已经完成的工作，再处理明确顺序的用户命令、民生供给和已有责任，最后规划新预留、启动新项目与普通生产。写入者唯一，入库不重复；出行人物不能同时在工坊加成。

普通建设位2、代表工程位1只限制项目数，劳力仍共用。功能地块16不等于装饰实例总数。数值和渲染读取同一施工阈值0/0.15/0.45/0.80/1.00；暂停不推进有效工时。

## 5. 离线与成长册

当前core-0.1仍为7日。实现30日目标时单独提高规则版本并备份旧档，说明旧水位与新上限如何迁移。不得用当前权限追溯启动过去未授权战争。

正常推进、有限排空和安全休整分开；排空只处理已完整承诺的有限行动。7/30/60/90日记忆节点是观察点，不发奖励、不更改经济。不能用离线结束画面填充全部历史。

## 6. 兼容与验证

旧存档没有BuildingInstance，不能把已有jobCapacity一对一猜成玩家已经付费完成的建筑。迁移必须建立显式兼容映射，保留原库存和岗位，新增真实建设只能从一个可验证的升级点开始；无法安全转换则保留旧档并提供新测试档，不静默覆盖。

保留原70项代码测试；新增运行测试先覆盖工程事务、劳力共享、暂停与取消、视觉真值、成长册历史、编制与在途、离线水位。PRD的CG用例仍为待运行要求，静态检查不替代这些测试。

本轮只是规格和架构影响同步，未改运行代码，也没有重新宣称Mac/M4实测通过。
