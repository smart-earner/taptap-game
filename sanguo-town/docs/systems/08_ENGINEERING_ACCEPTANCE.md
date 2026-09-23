# S08 引擎、存档与验收

PRD v0.9.0 · 系统化整理：2026-09-21。规则不因拆分而改变。

## 开发入口

- 职责：命令信封、权限校验、原子保存、回执幂等、离线、数据不变量；v0.9为GC01—GC28，v0.10增量为GC29—GC36。
- 数值定位：[唯一参数源](../../spec/hero-town-v0.9.json)中的 spec_version、rules_version、save_format、layout_version、dependency_sha256。不复制一套独立参数。
- 现有代码定位：LifePersistence.swift、LifeGachaValidation.swift、LifeGacha.swift；SanguoLifeCLI/GachaCheck.swift（未注明目录时为 Sources/SanguoLife；仅定位，不代表全部实现）。
- 验收范围：GC01—GC35（合同集合，不代表全部已执行），v0.9断言见§9.6，v0.10断言见§9.8。
- 对外依赖：为S01—S07提供单一引擎提交边界；业务规则仍归各自系统，不在保存层另写一套。
- 最小阅读：[总索引](../PRD.md) → 本文件 → 仅涉及的[接口合同](CONTRACTS.md)；修改存档或命令再读S08。
- 实现证据见[预览实现报告](../GOLD_TOWN_IMPLEMENTATION.md)，不要把下列合同当作已实现清单。

下文保留旧条款编号，方便核对原PRD；旧章节号的系统归属见[迁移索引](MIGRATION.md)。

<!-- source: 09_ENGINEERING_AND_ACCEPTANCE.md / 09-intro -->
<a id="sec-09-intro"></a>

## 09 工程、保存与验收
**PRD v0.9.0，rules hero-town-0.9.0，format4，layout6。新运行用例全部NOT_RUN。**

<!-- source: 09_ENGINEERING_AND_ACCEPTANCE.md / 9.1 -->
<a id="sec-9-1"></a>

### 9.1 单一引擎
沿用SanguoLife/原生投影/Host，不新建浏览器经济旁路。新profile读取hero-town-v0.9.json；10实物/6配方/30人物/20工种/90星技记录。旧四维和岗位权重锁定依赖SHA256；legacy_skill_ids仅出处，不混入新能力计算。
创建独立SanguoTown-HeroTown09目录和saveID。旧format1/2、v0.8 format3、preview1不自动迁移、不覆盖、不替换规则号。未知版本/损坏hash拒绝写入，保留原文件。本轮PRD不改变正在运行的.app。

<!-- source: 09_ENGINEERING_AND_ACCEPTANCE.md / 9.2 -->
<a id="sec-9-2"></a>

### 9.2 必需持久对象
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

<!-- source: 09_ENGINEERING_AND_ACCEPTANCE.md / 9.3 -->
<a id="sec-9-3"></a>

### 9.3 命令与权限
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

<!-- source: 09_ENGINEERING_AND_ACCEPTANCE.md / 9.4 -->
<a id="sec-9-4"></a>

### 9.4 原子性与恢复
水位推进→幂等查询→检查revision/权限→克隆候选→扣账/生成/状态更新→全不变量→临时文件校验→原子替换及3滚动备份→发布回执→播放动效。
相同id/payload返回旧回执；相同id不同payload拒绝；STALE不自动代替用户重新支付。所有抽卡结果和RNG与扣币同一次保存；动画不掷骰。培养消费与星级/将魂同事务，失败一项全回滚。
Receipt幂等索引不可因普通日志4096条裁剪而删除；每段最多10000，封段保留索引。120秒自动保存，抽卡/培养/退出立即保存。
恢复备份需明确用户确认丢失后续进度并备份当前；离线本机不承诺防人为回档抽卡，不接在线经济。正常崩溃重启不可重抽/重复消费。

<!-- source: 09_ENGINEERING_AND_ACCEPTANCE.md / 9.5 -->
<a id="sec-9-5"></a>

### 9.5 离线与性能
离线按同一任务/班次/供餐/金炉链，最多30日正常补算，余时安全休整冻结模拟义务，不追罚。不抽卡、不升星、不分解、不兑换。粮食与燃料不足按真实条件停产，金币目标满足就不新开单。
同抽卡RNG初态、城镇seed及同命令水位轨迹，1秒/120秒/按日分段应一致；仅给同公开城镇seed不保证不同存档抽卡相同。不同FPS、跳过揭晓、关闭故事不改经济。
参考M4/16GB：桌面15fps、单核平均≤8%、隐藏≤2%、内存≤500MB、30日补算≤20秒；需实测，不写成已通过。


<!-- source: 09_ENGINEERING_AND_ACCEPTANCE.md / 9.6 -->
<a id="sec-9-6"></a>

### 9.6 v0.9运行验收（全部NOT_RUN）

实际执行状态以BUILD_STATUS为准；这里的“全部NOT_RUN”是原PRD验收合同标题，不得用静态检查冒充运行通过。

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

<!-- source: 09_ENGINEERING_AND_ACCEPTANCE.md / 9.7 -->
<a id="sec-9-7"></a>

### 9.7 交付顺序
先真实金链与安全供给→事务/RNG/抽卡→重复卡与手动培养→星技与自动经营→原生表现→长时与概率/恢复验收。
每步附specHash/engineCommit/seed/RNG初态/命令轨迹/expected/actual/platform/status；PRD提交不宣称已编译或实现新玩法。

<a id="sec-9-8"></a>

### 9.8 v0.10 迁移对象与增量验收（未实现）

目标rules=hero-town-0.10.0、format5、layout7。format4迁移时保留原文件及滚动备份，先校验v0.9 contentHash，再把旧全城满意度复制为每名现有常住武将的初始happiness；缺字段取70。原30名内容、OwnedHero、星级、卡lot、将魂、金币、RNG及保底原样保留，poolVersion仍为permanent-1；只有60人内容包完整且hash通过后才原子切换permanent-2。迁移为每名现有常住武将建立稳定单人Household，绝不自动配婚或生育。旧住宅实际已住人数若超过对应新院落户位，超额的已入住者得到一人一份只可退不可新增的`legacy_occupied_lease`，保留原位置、供餐和休息；太守建好空院落后按heroID顺序原子迁居并注销旧租约。旧租约不是可供新人预约的空户位，迁移不得送新楼、新资源或新居民。迁移失败继续用原档，不得留下半扩城、半新卡池状态。

几何迁移按旧权威plotID升序遍历已建、在建和已投料地块，按建筑用途映射到增量JSON类别：`house→H`，农庄/林地/矿点/冶金坊/工造院等生产物流→`P`，府署/粮仓/酒馆/医舍等服务→`S`，景观休闲→`L`，路桥→`I`。在开局8×5已解锁矩形中选择该类别最小的未占`parcelID`；同一旧plotID的建筑、WIP、预留、居民归属与成长册引用一起换键，建立持久`legacyPlotID→parcelID`映射，不能依帧率或遍历容器顺序漂移。若某类已建/在建地块超过开局该类空格，迁移必须失败并保持原档，不能删除建筑、覆盖别的地块或提前解锁。新院落`unitID=house:<parcelID>:<1..4>`；旧屋原占用者按heroID升序先占有效户位，剩余者得到`legacy:<heroID>`旧租约。guest保留原真实客床，`unitID=null`。

新增或扩展持久对象：

|对象|必要字段及不变量|
|---|---|
|OwnedHero|arrivalState增加WAITING_RESIDENCY；paidAt与heroID形成稳定候任顺序；候任仍可培养但无resident实体。|
|HeroResident|happiness、七维快照、lastHappinessReason、workloadDutyS、householdID、residencePlotID、unitID（酒馆客床可空）；只有FORMAL/GUEST计常住。|
|Household|householdID、memberPersonIDs、residencePlotID、unitID、createdAt；v0.10每户恰一个`hero:<heroID>`成员，成员ID不得重复归户；预留未来`family:<id>`成员命名空间，婚恋/生育运行关闭。|
|ResidentialUnit|unitID、parcelID、level、occupantHouseholdID；同一户位至多一户，院落等级限制户位数与人位数；旧占用租约单列且不可分配新人。|
|CityGrowth|residentHardCap只允许30→40→50→60；completedBreakthroughIDs不可重复；每次完成回执可追溯材料/人工。|
|FoodState|当前缺粮tier、连续覆盖计数、supplyRecovery、admissionPaused；不能另存第二个隐藏效率惩罚。|
|Layout|layout7固定12×7共84块标准地，类别矩阵与增量JSON逐格一致；分期解锁8×5、10×5、10×6、12×7，住宅许可8→10→13→15；技术许可和实际建筑完成分开。|
|TaskStageSnapshot|happinessBefore、happinessModifierBP、protectedRecoveryJob、finalRateBP；进行中不回算。|
|HealthCondition|heroID、conditionID、startedAt、triggerEvidence、workModifierBP、blockedJobs；每人最多1条，无永久损伤。|
|ClinicTreatment|treatmentID、patientHeroID、physicianHeroID、bedID、phase、work/rest进度、receipt；完成与清状态/放床同事务。|

|ID|必须断言|
|---|---|
|GC29|常住武将硬上限初始30；超限新人进入WAITING_RESIDENCY，不占户位、人位、客床/食物/劳力但可培养；合法住处、4Nforecast、未来两餐≥95%和路线全部满足后按paidAt/heroID原子入住。正式入住须户位与人位均空；酒馆临住须有真实客床。|
|GC30|三次突破前置、成本、阶段投料和效果完全匹配增量JSON；缺粮暂停、重复完成幂等；上限只按30→40→50→60变化，解锁网格与住宅许可依次为8×5/8、10×5/10、10×6/13、12×7/15，地块不提前出现。|
|GC31|permanent-2恰60个唯一heroID，总稀有度20/24/16；新增30人均有四维、视觉身份和3技能；原池、保底、RNG、卡和星级迁移不变；全60人5星才POOL_COMPLETE。|
|GC32|逐人七维权重合计10000bp，公式和升降上限逐边界验证；85/70/50/30/29效率档正确；阶段快照不回算，城市平均不覆盖个人。|
|GC33|95%、80%、60%边界及连续计数正确；短缺只经幸福减速一次；恢复岗位负向修正为0；连续两餐≥95%退出恢复，无死亡/叛逃/掉星/免费粮。|
|GC34|以30/40/50/60常住各运行50日，含低资源、连续十连和离线分段；最近4餐正常轨迹≥95%，每人每cycle连续休息≥600秒，候任不消费，分段/FPS/重启状态一致。|
|GC35|劳损/轻伤只在精确边界触发且每人/每城限额正确；医舍1/2/3级2/4/6床，医生和患者真实占用；治疗/在家恢复时长、队列、换人、断路、保存失败与离线分段一致，无药材/金币/卡消费及永久损伤。|
|GC36|84格类别与坐标逐格匹配增量JSON，最终配额15/24/12/12/21；15座3级院落恰有60户位、120人位。60名单身武将可一人一户入住且无重复归属/超额；空容量不生成家属、饭食或劳力。format4超额占用旧屋迁移为只退不增的旧租约，原居民不丢失；迁居原子释放租约或客床并锁定新户位/人位，保存失败回滚。|

v0.10静态校验必须核对增量JSON的基线SHA256、三次上限连续性、84格类别/阶段容量/15院落与60户120人位、幸福权重=10000、缺粮区间无缝覆盖0..10000、医舍容量/费用/治疗边界及GC29—GC36均为NOT_RUN。静态通过仍不能宣称上述引擎用例已执行。

<a id="sec-9-9"></a>

### 9.9 本地调试日志合同

通过`scripts/run-godot.sh`启动的本地Debug试玩默认设置`SANGUO_DEBUG_LOG=1`；正式分发未设置该变量时不得持续写详细诊断。日志采用UTF-8 JSONL，每行一个完整对象。桥接stdout默认只返回协议JSON；Godot子进程调用同时带`--godot-response-b64`时只返回单行ASCII Base64，由Godot完整解码为UTF-8再解析JSON，避免大份中文快照在进程管道字节边界被拆坏。错误响应也遵循同一编码模式；日志失败不得中断经营或污染回执。

经营引擎写入存档目录`debug/engine-debug.jsonl`，至少记录请求开始/结果/错误，并在任务、工程、工坊、昼夜发生变化或每30模拟秒记录完整世界诊断：时间与班次、每名常住武将的任务或空闲原因、健康限制、当前步骤、资源总量/可用量/仓库量/在途量、生产消费累计、工程投料与进度、工坊输入输出、供餐、开放饭点和最近城务事件。Godot写入同目录`debug/godot-debug.jsonl`，记录请求、快照应用、速度、居民动作、路线点数、工程和界面桥接错误。

两类日志单文件上限8MiB，保留5个轮转文件；不得无限增长。错误中必须保留人类可读detail。日志属于开发诊断，不进入权威存档checksum，不改变RNG、任务规划、资源结算或玩家城务记录。

<a id="sec-9-10"></a>

### 9.10 v0.12 正式存档身份与直升迁移

本次交付的正式身份为 `hero-town-0.12.0`、format 7、layout 7、`createCity.auto_manage_v12`；内容哈希固定覆盖 v0.9 基础包、v0.10 住宅增量、v0.11 战役增量、v0.12 经济和60人名册五份数据。v0.10 的format 5和v0.11的format 6此前只是未发布的目标，**不得伪造中间存档**：现存format 4正式城镇在同一事务中直接升至7。旧试玩目录和旧规则读档仍受支持，但不能被误判成新版正式档。

迁移先按旧身份、旧内容哈希和旧校验和完整解码，在内存候选副本中补共享院落和12城战役（原来已有的则原样保留），最后切换规则、授权和内容哈希并再次验证；只有候选整体通过才由同一存档写入路径原子保存，旧文件作为`bak1`保留。新format 7校验要求名册阶段、金币再平衡账、健康、layout7共享院落和战役状态全部存在。迁移前已有的金币/将魂、抽卡RNG与回执、武将和星级、住宅占用、实物批次与预留、工程、伤病、战报和现实时间水位均不重置；新战役仅在原档没有战役时以迁移当下现实时间开局，过去离线天数不追溯计算。失败继续保留原文件及备份，不创建半新半旧世界；重复打开不重启战役、不赠资源或再迁移。UI继续沿用原用户存档目录以让玩家找回同一座城，不因目录名带09而新建空城。

验收：旧format4副本→候选升级→保存/重载与`bak1`逐字节比对；重复升级幂等、未知高版本拒绝；已有战役和无战役两种旧档均测。规则身份升级不等于经济与30日战争已通过，仍须跑P/G/C/W/U/S全部闸门。
