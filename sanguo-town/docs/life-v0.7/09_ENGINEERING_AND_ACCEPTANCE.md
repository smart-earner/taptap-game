# 09 工程、保存与验收
**PRD v0.9.0，rules hero-town-0.9.0，format4，layout6。新运行用例全部NOT_RUN。**
## 9.1 单一引擎
沿用SanguoLife/原生投影/Host，不新建浏览器经济旁路。新profile读取hero-town-v0.9.json；10实物/6配方/30人物/20工种/90星技记录。旧四维和岗位权重锁定依赖SHA256；legacy_skill_ids仅出处，不混入新能力计算。
创建独立SanguoTown-HeroTown09目录和saveID。旧format1/2、v0.8 format3、preview1不自动迁移、不覆盖、不替换规则号。未知版本/损坏hash拒绝写入，保留原文件。本轮PRD不改变正在运行的.app。
## 9.2 必需持久对象
|对象|必要字段及不变量|
|---|---|
|World|format/rules/contentHash/saveID/time/revision/sequence；单世界时钟|
|GoldWallet|balance/initial/minted/spent；非负整数，来源可追到金锭消耗|
|SoulWallet|balance/disassembled/exchanged；非负整数，绝不自动修改|
|OwnedHero|heroID/star/sourceDrawID或founding/arrivalState/arrivalAt/bedReservation；含在途唯一权益|
|HeroResident|heroID/location/home/guestBed?/task/cargo/rest/jobXP；本体唯一，不能分解|
|DuplicateCardLot|id/heroID/count/locked/originDrawIDs或exchangeReceipt；不代表劳动力|
|GachaState|poolVersion/rngState/nonLegendCount/totalDraws；0≤nonLegendCount≤19|
|DrawReceipt|commandID/price/results[new或duplicate]/RNG前后/保底前后/poolHash；同id同结果|
|CultivationReceipt|commandID/selectedLots/consumedCards/starBeforeAfter/soulsDelta；一次性消费|
|SkillSnapshot|heroID/star/skillID/metric/event/value/contentHash；旧阶段不回算|
|AdminLease|sourceHeroID/taskID/completedAt/expiresAt；实际劳动、无自身双计|
|Lot/Storage/Order|原有批次、容量、输入输出预留、WIP、来源/去向、阶段快照；无料不生产|
|Construction/Meal/Story/Memory|原有分段/消费去重/只读演出/历史快照不变量继续适用|
金币/将魂/卡数量用Int64，0..10^12，checked arithmetic；任何溢出整事务拒绝。时间0..315360000，单次离线推进≤2592000秒。
## 9.3 命令与权限
Envelope={id:UUID,expectedRevision,payloadHash,principal,action,payload}；成功回执持久化后发布。
|action|principal / payload|检查|
|---|---|---|
|createCity|player / slot,acceptedAutoManagement|新slot、一次性200金币，不覆盖|
|recruitDraw|player / count=1或10,poolVersion|金币、池版本、非全满星、追赶/并发锁|
|starUp|player / heroID,targetStar,cardSelection?|只升一星、同名未锁足额、已有本体权益|
|disassembleCards|player / lotID+quantity列表,confirmed:true|重复卡非本体、未锁、非空、有界、预览hash一致|
|exchangeSouls|player / heroID,quantity|已拥有未满星、1..10、余额、剩余到5星缺口|
|setCardLock|player / lotID,locked|合法卡来源、存在且有数量|
|advanceWorld/planOrders|system|无抽卡/培养钱包权限，仅真实生产和城务|
|setDisplay/pinMemory|player|只读经济、历史不重演|
旧setWish/手排/投资审批/手动技能/外贸/养殖/装备/军务命令FEATURE_DISABLED。禁止系统伪造player或以“优化”为由培养。
NO_GOLD、POOL_COMPLETE、UNKNOWN_POOL、INVALID_COUNT、INVALID_CARD、CARD_LOCKED、INSUFFICIENT_CARDS、MAX_STAR、NOT_OWNED、NO_SOULS、EXCHANGE_LIMIT、STALE、DENIED_SCOPE、OVERFLOW、PERSISTENCE_FAILED分别返回明确details。
## 9.4 原子性与恢复
水位推进→幂等查询→检查revision/权限→克隆候选→扣账/生成/状态更新→全不变量→临时文件校验→原子替换及3滚动备份→发布回执→播放动效。
相同id/payload返回旧回执；相同id不同payload拒绝；STALE不自动代替用户重新支付。所有抽卡结果和RNG与扣币同一次保存；动画不掷骰。培养消费与星级/将魂同事务，失败一项全回滚。
Receipt幂等索引不可因普通日志4096条裁剪而删除；每段最多10000，封段保留索引。120秒自动保存，抽卡/培养/退出立即保存。
恢复备份需明确用户确认丢失后续进度并备份当前；离线本机不承诺防人为回档抽卡，不接在线经济。正常崩溃重启不可重抽/重复消费。
## 9.5 离线与性能
离线按同一任务/班次/供餐/金炉链，最多30日正常补算，余时安全休整冻结模拟义务，不追罚。不抽卡、不升星、不分解、不兑换。粮食与燃料不足按真实条件停产，金币目标满足就不新开单。
同抽卡RNG初态、城镇seed及同命令水位轨迹，1秒/120秒/按日分段应一致；仅给同公开城镇seed不保证不同存档抽卡相同。不同FPS、跳过揭晓、关闭故事不改经济。
参考M4/16GB：桌面15fps、单核平均≤8%、隐藏≤2%、内存≤500MB、30日补算≤20秒；需实测，不写成已通过。

## 9.6 v0.9运行验收（全部NOT_RUN）
|ID|必须断言|
|---|---|
|GC01|开局5人/200币/10实物/3新增基础设施；重建slot不重复本金|
|GC02|金矿60人工产2000矿，不直接发币；满输出停|
|GC03|炉2矿+.5木→1锭，60/120/20，原料到场/被动释人/收尾有人|
|GC04|运输途中0新增币，完整1锭卸到府署+10币并消耗锭；重放不重复|
|GC05|未来两周期基本木保护、缺粮优先、币目标2000停新订单但保留在制|
|GC06|99币拒单抽、999拒十连；合法扣100/1000，保存失败钱包/RNG/结果不变|
|GC07|概率边界6999/7000/9499/9500，档内拒绝采样无取模偏差|
|GC08|19次非传奇后必传奇；重复传奇重置；退出/跨天不重置|
|GC09|十连第一张新人、后续同名是重复，最多一个本体；开局5也出重复|
|GC10|动画跳过/中途关闭/双击/同命令重发结果不变不重扣|
|GC11|新卡30秒到城，真实走路，没床进酒馆；下一餐名单正确|
|GC12|首日连续25新人供餐/临时床/自动扩建无死锁、无隐藏劳力|
|GC13|2/3/4/5星分别1/2/3/4同名卡；不扣金币/经验、不消费本体|
|GC14|锁卡/少卡/错误人物/5星升星拒绝且无部分消费|
|GC15|分解10/30/100将魂，未满星可明确分解但有警告；默认零勾选|
|GC16|本体ID分解、锁卡分解、负数/重复lot选择、越界/溢出全部拒绝|
|GC17|兑换40/120/400，已拥有、量1..10、到5星缺口上限；无自动升星|
|GC18|100循环分解兑换不套利；锁定卡也计到5星已有量|
|GC19|1/3/5解锁与2/4强化；高星有实际技能，不读取legacy技能|
|GC20|6个签名原语分别真实触发/错误岗位无效/上限与向上向下取整|
|GC21|工作中升星不回算旧产出/原料/快照，不取消携货|
|GC22|太守/离线不能抽卡、升星、分解、兑换；长期不培养仍可经营|
|GC23|全30人5星后收费按钮/接口关闭，余卡币魂保留，城市继续|
|GC24|固定RNG/命令同水位分段一致，随机样本≥100万普通抽验证档位/人物分布，保底样本单列|
|GC25|5/10/20/30人、1/3/5星混合、低资源/连续十连50日供餐休息与金币速率|
|GC26|坏hash/未知格式/磁盘失败/备份恢复/旧档目录隔离|
|GC27|一日离线培养钱包不变；金币仅真实矿炉来源，非墙钟赠送|
|GC28|不显示头顶姓名、培养确认/锁卡、概率/保底/重复说明、键盘与减少动态效果|
静态验证报告必须标static_contract_only及application_cases_executed=0，不把Python公式/样例当Swift运行通过。
GC25正常轨迹最近4餐≥95%、每人每cycle连续休息≥600秒；低资源3cycle内恢复≥95%，否则FAIL，不凭空补资源。记录每千金币粮木人工成本、必要任务最长等待、卡片成长分布，不能只报未崩溃。
## 9.7 交付顺序
先真实金链与安全供给→事务/RNG/抽卡→重复卡与手动培养→星技与自动经营→原生表现→长时与概率/恢复验收。
每步附specHash/engineCommit/seed/RNG初态/命令轨迹/expected/actual/platform/status；PRD提交不宣称已编译或实现新玩法。
