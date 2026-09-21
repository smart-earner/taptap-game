# 09 工程接口、数据、保存与验收
**PRD v0.8.0。目标rulesVersion=hero-town-0.8.0，contentVersion=0.8.0，saveFormat=3，layoutVersion=5。**
本章为待实现接口合同，不声称旧Swift已经满足。当前运行基线life-0.7.2-v2 format2独立保留，测试246项仍属旧版。

## 9.1 模块与单一来源
沿仓库现有SanguoLife/原生Presentation/Host分层：配置与验证、确定性账本/调度、农业/加工、食品/生活、城市/财政、名将/招募/收藏、故事投影与Mac窗口宿主。新增HeroPreferences、AdminLease、StoryProjection；不重建另一套浏览器经济旁路。
新配置spec/hero-town-v0.8.json固定8资源/2作物/4配方/30人物/20工种与6组/22技能引用、开局、建设、招募、藏品、工程。依赖hero-system-v0.7.json的技能与权重、heroes-v0.7.2.json的四维技能，必须匹配记录的SHA256；只复用白名单字段，不复用旧人口/配方/招募门槛。
加载时拒绝未知版本、字段/ID、负数、缺键、重复人物/技能、超界四维、双特色、非法岗位引用、容量不足、配方输出不可存、不可达路径和循环招募条件。JSON与正文冲突阻止发布；不能忽略某文件静默继续。导出catalog用新的显式profile，不覆盖旧catalog来冒充兼容。

## 9.2 必需数据模型
|对象|字段（均需持久化，除派生展示）|不变量|
|---|---|---|
|World|saveID,format,rulesVersion,contentHash,epoch,time,seed,revision,nextSequence,cities,heroes,orders,lots,ledger|一世界一时钟；本版一城|
|HeroResident|heroID,origin,cityID,homeID,location,attributes,skillIDs,jobXP,preference,office?,activeTaskID?,cargo,rest|heroID必填且全世界唯一；无普通居民|
|HeroPreference|mode,group?,setAt,revision|prefer必须6类之一，其他模式group为空|
|AdminLease|officeID,sourceHeroID,completedAt,expiresAt,taskID|真任务完工后生成；到期/入睡/卸任失效；不自加成|
|Prospect|heroID,state,tier,profile,stage,quoteHash,paidCash,consumed,authorityID,bedReservation?,arriveAt?|同hero不同时在resident；founding不可招募|
|Order|id,consumerKey,authorityID,priority,state,workerIDs,deadline?,workBP,rateSnapshot,passiveDueAt?,reservations|同人不能双占；无料父单不锁人|
|Lot|id,originLotID,resourceID,quality?,amount_mU,location,originEventID|只一位置；meal有合法品质；库存非负|
|Storage|id,capacity_uV,acceptedTypes,lots,incomingReservations|stock+incoming≤capacity；返货缓冲只出不进|
|Device|id,recipeIDs,activeOrderID?,inputID,outputID|PASSIVE仍占设备，不占工人|
|Crop|id,cropID,state,growth_s,waterMask,harvestCycleID,outputReservation|每床同周期只产一次|
|Animal|id,kind,sourceContractID,state,segment,care,location,leadTaskID?|pig可终结，horse不可肉用|
|MealWindow|mealID,expectedHeroIDs,allocations,served,quality,deadline,closed|一人一餐最多1份|
|Construction|id,plotID,quoteHash,phase,workBP,consumed,cashReserved,beneficiaryIDs|只到场物料可投入；COMPLETE一次加容量|
|UniqueItem|id,definitionID,state,location,holderID?,taskLock?,history|同物只能一持有者/位置|
|StoryEvent|id,storyID,sourceEventID,heroIDs,createdAt,snapshot|只读经济；回放不执行生产；稳定去重|
|Memory|id,versions,time,camera,geometry,heroSnapshots,lighting,sourceEventID,pinned|历史不引用当前人物补画|
|Receipt|commandID,payloadHash,revision,result,error?,ledgerRefs|相同命令返回原结果；不可重复扣费|
访客单独Visitor(contractID,location,expiresAt)，不可传给劳动接口。跨城、Army、Frontier不进入v0.8可写模型；输入带这些对象报FEATURE_DISABLED，不悄悄丢弃后保存。

## 9.3 命令协议（明确输入/输出）
Envelope={id:UUID,expectedRevision:Int64,principal:player|system,action,payload,issuedAt:Int64}。
|action|payload|必要检查与生效|
|---|---|---|
|createHeroTown|seed,acceptedBaseCare,saveSlot|独立新档，槽不存在；不能覆盖旧slot|
|setCityPolicy|cityID,policy|5枚举；只改未来优先，不拆建筑|
|setInvestment|mode|3档；下财政窗生效，不刷新预算|
|setDevelopmentHold|recruitment:Bool,expansion:Bool|停新阶段，基础生活继续|
|setHeroPreference|heroID,mode,group?|已拥有/6类校验；完成安全段后用于调度|
|appointPrefect|heroID,proxyHeroID?|真实在城；建05章交接计划，非立即租约|
|setWish|kind,targetID,totalCashCap,materialsCap|唯一心愿、合法发现条件、完整报价；同档无重复收费|
|setWatch|targetID,enabled|最多3；不花费、不产生任务|
|authorizeLandmark|projectID,quoteHash,cashCap,materialsCap|三阶段总预算、条件与权限合法|
|authorizeHusbandry|enabled,budgetPerWindow|预算≤40、固定窗口；关闭只停新买|
|equipItem|itemID,heroID?|唯一、在城、无任务锁；空目标放入兼容藏架|
|pauseOrder/cancelOrder|orderID|按阶段安全矩阵；已在途不消失|
|pinMemory|memoryID,pinned|固定≤20，不自动删置顶|
|restoreBackup|backupID,expectedCurrentHash,confirmed|明确用户确认会丢失的后续进度，保留旧文件|
authorizeLegion/authorizeRegion/authorizeFrontier/establishDistrict始终FEATURE_DISABLED。
显示设置setScreen/setCamera/setFPS/reducedMotion只写用户偏好，不入经济账；暂停动效≠暂停模拟。CLI/GUI走同一命令接口。
成功Receipt={id,revision,result,affectedIDs,ledgerRefs}；失败含code/details/currentRevision，不部分扣费。
错误：INVALID_INPUT、UNKNOWN_VERSION、STALE、DUPLICATE_ID、DENIED_SCOPE、FEATURE_DISABLED、ALREADY_OWNED、ALREADY_COMPLETED、NO_BED、NO_CAPACITY、NO_ROUTE、NO_WORKER、OUT_OF_SHIFT、NOT_DELIVERED、NO_CASH、RESERVE_PROTECTED、LOCKED_ENTITY、WAIT_LIMIT、PERSISTENCE_FAILED。
同id同payload返回原receipt；同id不同payload拒绝；过期revision返回STALE与新revision，不自动重试付费命令。

## 9.4 事务与状态机
推进到命令水位→校验→候选状态克隆→预留/扣账/建任务→全不变量→临时文件校验→原子替换+滚动备份→发布revision/receipt/声音。任何落盘失败全部回滚，不能先在界面显示成功。
生产/运输/招募/施工状态分别见02/03/06/01，不允许前端直接将state设为COMPLETE。每完成事件有稳定eventID、settlementID，重放只返旧回执。
工作量整数BP秒，物资mU，体积uV；价格与分段取整方向固定。所有速率/报价/输出在任务阶段开始快照，配置更新不回算在制；任何修改只走新版本明示迁移。
任务取消：未消费预留全释放；已携货交付或返源；已投料加工不可退原料保产物；施工只退未用；招募已ARRIVING不撤掉人；猪已加工不能恢复动物再留肉。

## 9.5 新旧存档隔离
format1/2由旧引擎读写；format3拒绝自动导入。入口显示“创建武将小城（保留原城）”，新saveID与独立目录；旧城按钮仍可用。切换时先保存当前城，并保证仅被选世界推进，后台未选城的时间策略遵其原版本，不由新引擎代算。
不得用普通居民改名、删除15人或压成5将迁移。将来迁移另需映射方案/预算/携货/动物/装备/未完成义务验收，本版没有“试试看”迁移按钮。
未知更高format/损坏hash拒写、保留原文件；不能清档补一份新城伪装修复。每120秒自动保存，重大命令/退出立即保存；3滚动备份。恢复需用户确认目标时间和进度损失，恢复前再备份当前。
存档manifest含contentHash与依赖hash。没有相应旧引擎/规则时只读说明，不强行用最新参数打开。

## 9.6 离线与性能
最多2592000秒正常事件模拟；超30日的剩余时段直接安全休整，冻结模拟time/负担/任务，不开新循环也不补罚；记录wallRestedSeconds，恢复从已结算simulationTime继续，防止“有限收尾”又长出无限新订单。
一次推进、每120秒、每1/3/7日访问同种子同命令必须规范化世界一致（剔除wallRestedSeconds、UI偏好、日志采集时间）；任务、XP、余额、人物不可不同。每10000事件让出UI；追赶中禁世界写操作、可看标注的旧快照。
详情日志4096，旧账压缩为每周期汇总+hash；未完成义务和唯一物历史不能淘汰。receipt每段≤10000，封段另存不可丢幂等键。
参考机M4/16GB/macOS15+，桌面15fps、单核平均CPU≤8%、停止绘制≤2%、内存≤500MB、30日单城补算≤20秒；均为实测目标而非声称通过。

## 9.7 自动测试矩阵（全部应用状态初始NOT_RUN）
每条必须输出caseID/specHash/engineCommit/fixtureHash/seed/platform/commandTrace/expected/actual/status。
|ID|输入|必须断言|
|---|---|---|
|HT01|create默认新城|恰5位指定hero、400铜、初始库存、5床，无普通居民/隐藏劳力|
|HT02|重复创建同slot/commandID|拒绝覆盖或返回旧receipt，不再发资产|
|HT03|同hero并发两任务/重复招募|最多一任务一身份；开局5将均ALREADY_OWNED|
|HT04|5人自动运行2周期，无手排|按时食用每餐5份、真实生产运输、一人兼岗不并行|
|HT05|改偏好时携4粮|先安全交货，货守恒，不瞬移或丢失|
|HT06|rest_optional所有人|基本供给仍执行，可选停；无行政租约不死锁|
|HT07|行政30秒完成t30|lease到630；t629新任务有效/t630失效；自身不吃主管来源|
|HT08|行政中睡眠/卸任|清租约；旧阶段snapshot不回算；无人免费接职|
|HT09|basic无等待rate10000|70秒，1粮+.25木→4饭，库存不增16|
|HT10|hearty/ration/forge|100/160/195秒；输入输出按JSON、品质正确|
|HT11|粟/稻无路程夹具|3745秒16粮/7390秒36粮在田边，仓0；无矿料稻谷旁路|
|HT12|4粮载重路960，装卸10有仓吏|t10源扣/t40到/t50目的可用；无仓吏入仓t60|
|HT13|N5、E20，1粮可选外售|拒；同粮做4饭允许；Rfood不把生粮当即食|
|HT14|餐点+179/+180/+181到饭|前两者计本餐，181不追填，饭不消失|
|HT15|五人2餐+4份批量补库|10份被吃，批次按缺口ceil，最多超3.999，不丢余料|
|HT16|低餐覆盖2次/恢复2次|进入/退出保供，均不死人或制造资源|
|HT17|满5床首位候选最终邀留|缺床等待且该阶段不扣；建床后继续；到达一次、下一餐才计|
|HT18|依次招募25人和平轨迹|全部可达无循环、30唯一；tier/报价/消费/床位正确|
|HT19|切心愿/重启CONTACT_WAIT|已付不重扣，等待保留，旧段安全完不续；ARRIVING保床|
|HT20|house升2两人rate10000|120铜木16石4、1800人工、900有效秒；缺下一段物料停|
|HT21|特色反复完成/换方针|一次效果不叠，已建保留，不招普通士兵|
|HT22|两猪六段/重放加工|总3粮、360照料、各17280成长、2×8肉；不重复生成|
|HT23|暂停购猪/跨财政窗|既有照料继续，额度仅固定窗刷新，马不能作肉|
|HT24|原价粮应急预算40+费2|最多9粮38铜；改方针不刷余额/预算|
|HT25|故事开/关、帧率8/15/30|经济/任务/XP逐字节一致，故事0资源0XP|
|HT26|全部人休息、故事参与者不在场|不造人、不延迟睡眠；无夜巡无损失|
|HT27|所有地块工作点对路径|无穿建筑，无不可达必须源；相机缩放不改路长|
|HT28|5/10/20/30人×5方针×正常/低资源|50日事件模拟，记录供餐/休息/资金/堵塞，不能只报未崩溃|
|HT29|1/120秒及1/3/7日分段到30日|规范化状态一致；超过30日安全休整无额外扣餐|
|HT30|落盘失败/坏hash/未知格式/restore|原文件可恢复，无乐观发布、无自动清城|
|HT31|6武器4马木印全路径|唯一、正确材料、装备锁/位/移动有效性，和平可达|
|HT32|军团/跨城手写命令|FEATURE_DISABLED，现金/物料/revision不因失败改变|
HT28的50日是单次长时压力夹具，需逐段每段≤30日调用模拟，不与单次离线封顶混淆。动态门槛：正常供给最近4餐≥95%且每人每cycle休息≥600；必要无路/无工死锁>600秒必须恢复或判FAIL。低资源允许短期缺餐但必须真实原因并在3cycle内恢复≥95%，不许补资源伪造。
静态验证器只覆盖结构、依赖、层级可达、报价、配方和容量算术，输出STATIC_PASS；上述任何一条实际Swift未跑仍NOT_RUN。

## 9.8 人工与交付
UX01：无说明15分钟能认出至少3开局人物、复述1人当前工作，看见首餐、采收和施工进展。UX02：独立30人/6武器/4马不是同形换色。UX03：追一批饭能区分生产发运到货消费，图像账本同源。UX04：完整昼夜回家、晚巡可解释，暂停演出不改供给。
UX05：Finder拖拽、显示桌面、Spaces、全屏、台前调度、负原点多屏插拔不抢焦点；UX06：键盘/对比度/减少动效通过；UX07：M4持续8小时与合盖恢复、实际能耗及30日补算记录；UX08：一周回访是否关心具体人物，原话记录，不以策划推测填PASS。
工作包顺序：数据/校验→独立存档/身份→五人调度/行政/食物→真实投影→招募/财政/施工→收藏/养殖→故事/工程/桌面→长时与人工。每包提交对应caseID证据、失败边界和BUILD_STATUS。
规格提交不编译新.app，不声称HTML已改；运行代码提交后才执行Swift Debug/Release与原生UI验收。
