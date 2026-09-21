# 09 工程结构、接口、迁移、验收与发布

## 9.1 目标版本和实现边界

目标schemaVersion=6、rulesVersion=life-0.7、contentVersion=0.7.1、layoutVersion=4。基线可运行软件为town-0.5＋desktop-0.1，旧单元测试只证明旧代码；本次PRD交付不改Swift运行源，不发新Mac包，不沿用旧201项宣称新生活层已通过。

历史schema1—4解码保留。schema5是未正式交付的life-0.6目标，若遇实验档必须按带manifest的实验迁移适配器处理；没有适配器就BLOCKED，不按旧格式猜。未知更高版本只读报错、保留原文件。

## 9.2 模块职责

SanguoCore/Life：配置校验、单位/账本、任务调度、生产、食品、服务、城市规划、标准属性/技能解析、区域、新城、迁移。SanguoPresentation：只读投影、路径插值、昼夜着色和动作。SanguoDesktopHost：屏幕、层级、穿透与显示设置。SanguoMac：查看与发授权命令；不能私下写库存。

开源目录中新增与更新的每批代码必须有对应自动测试、真实构建和BUILD_STATUS条目。优先V1真实食物链，不继续以旧自动产率＋新动画暂代实现。P0未实现的目标禁用并说明，不接受空回调按钮。

## 9.3 必须落实的数据对象

|对象|必需字段|不变量|
|---|---|---|
|LifeState|epoch:Int64,seed:UInt64,contentHash,cities,agents,orders,lots,devices,events,nextSequence|一个世界一个时钟；配置hash固定|
|CityLife|cityID,capacityPopulation,residentIDs,presentConsumerIDs,permits,metrics,food,treasuryAllocations|常住归属人口和实际在城就餐名单分开|
|Agent|id,origin,cityID/location,homeID,personID?,role,shift,activeOrderID?,route,cargo,jobXP,skillIDs,baseAttributes,legacyAttributes?,rest|一人一独占任务，一地或一条旅程|
|Order|id,parentID?,consumerKey,authorityID,kind,priority,state,workerIDs,createdAt,deadline,remainingWorkBP,rateSnapshot,passiveDueAt,recipeVersion,reservations|WAIT_INPUT不独占工人；完成一次|
|CargoLot|id,originLotID,resourceID,amount_mU,locationType,locationID,ownerRealm,allocatedCity,originEventID|数量非负；库存/携货/WIP互斥|
|Storage|id,acceptedTypes,capacity_uV,lotIDs,incomingReservations|在库＋预留入库≤容量，返货/旧档溢出例外只出不进|
|Device|id,buildingID,recipeIDs,activeOrderID?,inputLocation,outputLocation|被动时设备仍锁、工人释放|
|CropBed|id,cropID,state,growthSeconds,waterMask,harvestCycleID,activeTasks,outputReservation|同周期只收一次，缺水不倒退|
|Animal|id,kind,sourceContractID,state,segments,care,location|猪可消费、马不可匹配肉配方|
|MealWindow|mealID,expectedAgentIDs,allocation,served,quality,deadline,closed|每消费者最多1份；迁入名单不追溯|
|DevelopmentMetrics|windowStart,closedWindows,supply,delivery,utilization,occupancy,serviceCover|未到期需求不算失败；内部倒仓不算外部交易|
|Construction|id,quoteHash,plotID,phase,phaseDemand,work,spentCash,consumedMaterials,beneficiaryIDs|只有到场材料能投入，取消不双退|
|AppointmentPlan|id,personID,source,target,proxyID,officeReservation,bedReservation,state,trip|在途无两城太守特性|
|UniqueItem|id,definitionID,state,location,holderID?,lockedByTaskID?,history|同一实物只能在一地或一人手中|
|Army|commanderID,authorizedCap,actualAgentIDs,trainees,wounded,budgets,foodAccounts,training|没有授权不超编；预缴口粮不重复扣|
|Opportunity|id,eligibilityEvidence,state,authorityID?,resolvedAt?|常驻，已发现不因排队消失|
|FrontierProject|id,target,cashCap,materials,site,builders,supplyCap,deliveryIDs,state,settlerProspectIDs|不复制国库/居民，交接一次|
|Snapshot|id,time,cityID,versions,geometry,buildings,civic,agents,stocks,lighting,collections|历史不引用当前世界|
|LedgerEntry|eventID,time,reason,sourceRef,authorityID,debits,credits,recipeID?,previousHash|同资源移动守恒；转换按配方|

presentConsumerIDs是本城此时需要居民饭的实际人员，04章N用于饭食计算时取其数量；归属居民外出仍占原城人口/床位，但不在家中重复吃饭。在城军团用口粮账，外来宾客用购买账。返回或跨城到任从下一餐进入对应名单。

军团背囊为每位现役8体积、只装口粮的随身容器，不是给居民挑夫翻倍载重。6.7的随军辎重由这些真实士兵背囊承担，**不凭空产生军车或额外搬运工**：先每人装15份个人口粮，再将公共60份按agentID轮流分1份直至分完；30人每人17份=4.25体积，低于8。装载有quartermaster/porter任务，既定出征人可在领料点顺序自装；未装齐不能出发。行程中个人与公共消耗分别记账。

## 9.4 命令协议和错误

Envelope={id,expectedRevision,principal,action,issuedAt}。principal为player、prefect(personID)、governor(personID)。同id同payload返回原receipt；同id不同payload为DUPLICATE_ID；版本不同STALE，不部分扣费。操作在模拟推进至当前水位后执行。

命令必须包括：adoptLifeRules；setCityPolicy；setInvestment；setGrowthHold；setDistrictAuthority；appointPrefect；establishDistrict；planAppointment；setWish；equipItem；lockPerson/Plot；authorizeLandmark；authorizeLegion（编制/组建上限/周期军费）；authorizeRegion；authorizeFrontier（材料/现金/口粮/运费上限）；pauseOptionalDevelopment；pauseOrder/cancelOrder；pin/removeMemory。

显示动作setScreen/setQuality/setCamera/openCodex属于UserDefaults偏好，不是世界命令，无经济写入。暂停新发展只停止新可选项目，饭食、照料、原承诺和安全返货继续。单工程暂停和全局暂停语义分别显示。

错误码：INVALID_INPUT、UNKNOWN_VERSION、STALE、DUPLICATE_ID、DENIED_SCOPE、LOCKED_ENTITY、NO_BED、NO_CAPACITY、NO_ROUTE、NO_WORKER、OUT_OF_SHIFT、NOT_DELIVERED、NO_CASH、RESERVE_PROTECTED、WAIT_LIMIT、ALREADY_COMPLETED、PERSISTENCE_FAILED。UI显示具体缺口、合法后续，不用一个“失败”对话框糊弄。

事务：校验→候选状态→预留/任务/扣记变更→全不变量→写临时文件并校验→原子替换/备份→公布revision与receipt。落盘失败不能先更新屏幕为成功，不能先发完工音效。规划可以批量提交但整批成功或回滚。

## 9.5 参数加载与升级

`spec/life-v0.7.json`是生产/经济/容量数据；`spec/content-v0.7.json`是特色、事件与收藏；`spec/hero-system-v0.7.json`定义四维、工种权重、22技能与效果原语。人物只引用技能ID；未知效果、重复技能、非法范围阻止新规则写入。时间和整数单位不得硬编码到动画中。启动校验唯一ID、引用、非负、上下限、无环依赖、每配方输出可容纳、所有概率与比重范围、报价向量。校验失败停止新规则写存档，旧版仍可打开。

已开始订单保留quote/recipe/rate/remainingWork/输出快照，热更新不重扣和不改变过去工时。若任何规则从0.7.1变更，发布contentVersion补丁并列出受影响向量。模拟中不直接读用户可随意编辑的未签配置；开发配置模式另有profile与明显标识，不污染正常档。

能力迁移另按06A执行：四个旧键逐项保留，旧魅力仅写legacyAttributes；已开始阶段/出征不重算；按explicitMigrationMap添加初始skillIDs一次，不按显示姓名匹配。技能学习、洗练、手动放招默认关闭。

## 9.6 安全迁移与旧义务

先用旧引擎推进至同意时刻t并保存，备份旧文件/hash。创建migrationID=saveID+sourceRevision+targetVersion。预检人口包含所有已有人物、位置可映射、库存非负、唯一装备无冲突。失败保留旧档和具体错误，不通过白送人口或清零修复。

旧grain/wood/iron/wine/tools按同mU映射；没有的肉/菜/饭/猪/马/钱不赠。旧库存超新共享体积则进legacyOverflow，只出不进，直到自然消化。已有府署附公共灶/木作、农庄附留种圃/碾米、城内公共井为显式兼容设施，清单说明、不计玩家亲建成就。旧照片保留旧layout。

人口按已具名personID先分配，剩余以migration-{city}-{i}创建确定性普通agent；源档人数不足包含具名人则失败。已有军团按原实际人数转换确定性recruit IDs，不额外增加，迁入无第二份招募奖励。

旧已付费/已开始义务进入legacyObligations，固化原remainingWork、dueAt、reserved、材料、预计合法输出和终止条件；分配真实agents，占用后不能同时做life任务。仅这批旧义务可按原承诺一次性跨夜收尾，标grandfathered，不给新睡眠罚分。停止旧自动生产和售酒循环，不再让旧prepareBatches产生新任务。

无实际付款且未开始的旧预测单撤销并释放预留。旧收藏已授权路径继续旧报价的承诺段，下一新任务才用0.7，不因新卡更便宜/贵追退追扣。所有结果通过桥接结算ID一次进入新账本。

迁移时设置新epoch=t。前两个居民餐窗照常产生真实需求，但满意度只记录不下调，帮助无旧熟食存量的档启动公共灶；不凭空发饭，第三窗起正常规则。新开局无此迁移豁免。迁移后保存schema6成功才切主档指针；重复migrationID不重复生成兼容资产。取消/失败继续旧规则，不能两个引擎同时运行。

## 9.7 离线、日志与性能

正常离线最多2592000秒（30现实日），按同一事件队列推进，不用期末产率乘时长。超出区间仅完成资源已全承诺且余下真实时长够的有限任务；不能借收尾再开新采收、餐食、养殖、财政、事件循环。冻结餐食负担、满意度、迁入、小贼；恢复后沿原许可继续未来生活，不补罚离开期间未吃的饭。

大计算每10000事件让出主线程；未追赶完禁用世界写命令并显示恢复进度，可继续看最后保存城景，不将它标实时。路径按路网版本缓存，按需求建事件，禁止每agent每帧扫描全地图。

内存保留最近4096条详细事件，旧记录压缩为每周期按来源/资源/配方的汇总与hash链；当前订单、预留、未履约合同、唯一物历史不得淘汰。完成taskID采用按对象的单调sequence水位防重放，玩家命令回执单独保留（上限10000，达到上限导出分段而非丢幂等记录）。照片60自动+20固定，固定超限询问，不自动删。

每120秒保存，重大命令/迁移/退出前保存；3滚动备份与1迁移前档。未知schema/坏校验/写盘失败不清档。恢复备份显示目标时间与会丢的后续进度，需确认。

M4/16GB/macOS15+作为参考测试机，不声称是用户的完整配置。目标桌面15fps、丰富档仍≤160人；平均单核CPU≤8%、停止绘制≤2%、内存≤500MB、30日3城补算≤20秒，仅是测量目标。M4不同型号、显示器与系统需记录具体值，未测标NOT_RUN；不因编译通过填PASS。

## 9.8 自动验收向量

以下均为新规则的**应用验收计划NOT_RUN**。规格脚本可以验证其中算术与容量子式，不能自动把整条Swift/GUI用例改PASS。每条应用记录必须含caseID、specHash、engineCommit、fixtureHash、seed、platform、输入命令、expected、actual、status与错误。

|ID|给定与操作|预期|
|---|---|---|
|PR01|水稻无等班等料从t0完整种植|t7390田边48000稻谷、仓0，只发一次|
|PR02|水稻50%无水等待1000秒|停在3600有效生长，补水20劳动后继续|
|PR03|粟/青菜/草从空床，无等班|3745/2815/1900秒分别16粮/12菜/20草|
|PR04|48稻谷完整12次mill|36粮12草，720人工秒，不叠旧产率|
|PR05|田边64容积已有20稻，试预留48|拒绝完整批次，未消费水或种子|
|PR06|幼猪六段后屠宰，重放完成|17280被动180照料90加工，8肉，animal只终结一次|
|PR07|树采完无补植等7200|不再生；补植30后才开始新7200|
|PR08|厨师basic齐料，无等待|60+60+15=135秒，4粮2水1木→16饭|
|LG01|粮8、装4、负重960，装卸各10|t10源4携4，t40到、t50目标4；t49不可吃|
|LG02|一脚夫4体积装原木|最多2份，不是4份；饭最多16份|
|LG03|新入库占了别人预留容量|拒绝新单，不删旧在途货|
|LG04|目的失效且源满|返货缓冲只出不进，批次总量不变|
|LG05|一个agent被2订单抢占|只一个activeOrder，另单等待|
|LG06|十轮规划同consumerKey|缺口不翻十倍，设备不被无料父单占满|
|LG07|切48/96/160显示人数和关窗|同时间物流、库存、XP完全相同|
|LG08|运输中跨夜|实际送到/返源再回家，货不清零，人不瞬移|
|FD01|16居民一个cycle全家常|32饭、粮8水4木2；厨师150人工/120被动|
|FD02|餐后179/180/181秒卸餐|前两者计该餐，181保留后用不追填|
|FD03|N16，E64，取1粮酿酒|拒绝；同粮变4民用饭允许|
|FD04|无肉菜但家常足|C100，正常生活，不判饥荒|
|FD05|C/H/R100,Q40,D/S60，当前70|目标84，普通下一73，安抚且覆盖≥95%则74|
|FD06|两餐C<90%，随后两餐≥95%|进入/退出保供，农业/饭/物流不减速|
|FD07|外出居民同时在家名单|校验拒绝重复消费；按旅程口粮一次|
|FD08|居民吃16饭＋外客2肉菜|居民收入0，外客实际交付收入8，未交付不收|
|CT01|空屋刚建好|只增容量，未批准迁入不生居民|
|CT02|两家庭候选争最后2床且名将预留1|只合法计划成功，不超床、不偷邀留床|
|CT03|有粮但未送，厨房I高|优先修物流，不据此升级灶位|
|CT04|厨房U高、I低、积压2窗|允许扩灶候选，但仍要权限/现金/材料|
|CT05|民居1升2两普通工人|240铜，木24构8石8器2，14400工作秒→7200有效秒|
|CT06|只第一段材料到工地|只能做20%段，未到第二段不能出屋顶|
|CT07|切兴商到备战|已建商街不降，在制按原报价，不自动开战|
|CT08|特色3阶段完成重放/改方向|效果各一次，旧外观保留，不免费重建|
|HR01|新开局|16=荀彧1普通15，仅荀彧已加入|
|HR02|荀彧太守普通厨师basic|A厨政=91，主管410＋庖厨400＋王佐600；rate11410，53+60+14=127；产出16不变|
|HR03|鲁肃买10粮含2运费|39铜，不把运费打折|
|HR04|同键太守与都督效果|取较大不相加；不同键总rate受上限|
|HR05|施工中途诸葛亮上任|原人工段不回算；新builder段主管380＋营造400＋卧龙800=1580，rate11580（普通L1，无其他项）|
|HR06|同件兵器分给两人/在途换装备|拒绝冲突，不产生分身|
|HR07|赵云30人训练1城防1护送|score63成功；护送4，一身是胆减伤20%，基础5伤→4，出发后换人不改|
|HR08|普通指挥C50V59I50装备武力+2|武力分从0到1；未跨门槛时显示0增量|
|GV01|每天/3天/7天访问同命令轨迹|同截止完整状态一致，不发访问奖励|
|GV02|投资额度用完后切方针和恢复|本期额度/现金不刷新|
|GV03|对外购粮应急80预算、单价4费2|最多19份78铜，不能买20份82铜|
|GV04|自动人事目标只增7分/8分|7不调；8还需源代理、总分、冷却、锁检查|
|GV05|任太守在途与到达边界|源代理/目标旧任连续，目标交接完成才新任有效|
|GV06|跨城货已出未到|源不可再用、目的不可提前吃，无内部贸易收入|
|GV07|新城分批运料+建造+8人到达|只一次交接，不复制600铜；留下木8粮32水16|
|GV08|新城施工口粮不足且无及时补给|停工安全返程，保留工地，不继续无限施工|
|CL01|木印已完成后回看/重复命令|唯一1件、只花10铜木2、无数值加成|
|CL02|换心愿时旧段已开|旧段安全结束，不退费用/不续下一段|
|CL03|招募最后阶段无床|该段不开不扣，既有进度保留|
|CL04|猪与赤兔误入同肉配方|类型校验拒绝，马永不产肉|
|CL05|E08来信已读重复触发|letter_read一次、0资源奖励、不催答|
|CL06|12类事件多项同刻满足|反馈入史、线索入宝鉴、战略卡受全局限额|
|CL07|30人出发12小时护送|每人15口粮＋公用60，共510，背囊容量足，出发前实际装齐|
|CL08|军团招募预缴2口粮/人|消费从个人预缴扣完才向库索取，不双扣|
|SV01|旧档拒绝迁移|原规则继续，无新饭食/昼夜经济|
|SV02|五类旧库存含预留及在途迁移|守恒重分类，无新旧双产或免费肉/人|
|SV03|旧库存体积超新仓|只出不进溢出容器，不截断|
|SV04|迁移写盘失败/重复migrationID|原文件保留；成功重复不生设备居民|
|SV05|30日+1秒/90日一次离线|30日正常，后仅合法有限收尾，不追缴餐食罚分|
|SV06|坏schema/非法资源/缺字段|阻止写入，具体错误，不能清档重建|
|SV07|截止同刻先卸货再关闭餐窗|计入本餐；新迁入从下一餐算|
|SV08|随机事件seed不变不同渲染档|候选/追逐结果与经济一致|

## 9.9 人工体验与集成验收（仍NOT_RUN）

|ID|测试方式|通过条件|
|---|---|---|
|UX01|无说明看新开局15分钟|能说明谁在采、搬什么、饭到哪；至少一项可见真实成果|
|UX02|隐藏名字看六将/六器四马|轮廓能区分，不只是颜色文字替换|
|UX03|追踪一批粮、一段修复、一趟军需|图像与账本同源，没有后台产率旁路|
|UX04|观察完整昼夜|回家休息、夜巡和照明可辨，夜班确实白天休息|
|UX05|桌面Finder拖拽/显示桌面/Spaces/台前调度/全屏应用|不抢焦点、不拦桌面操作，不覆盖系统安全画面|
|UX06|多屏插拔、负原点、不同缩放|画面不失踪，不改变路程或收益|
|UX07|M4工作一天、合盖、恢复、30日补算|记录真实CPU/能耗/耗时，满足目标或明确FAIL，不用估算充实测|
|UX08|比较5方针30/60/90日及12人口军团夹具|记录食物覆盖、堵塞时长、有效交付、收入来源、城景差异和操作次数；不是只看没崩溃|

参数容量矩阵为居民16/64/150×军团0/30/60/90共12组，至少覆盖最少资源与正常供给两种起点。长周期45点=5方针×访问1/3/7日×30/60/90；与人工8项分别报告，不重复当同一批通过数。

## 9.10 发布与工作包

V1先交LifeLedger、TaskScheduler、Crop/Recipe、Meal与无图集成测试，再接真实状态画面；V2接作息/养殖/20工种与诊断；V3接服务驱动城建和12阶段特色；V4接六将/藏品/军团；V5接自动人事/三城/逐车安置。每包都同步规范条目、代码、运行测试与失败边界，先小提交保存，再验收入运行目录。

静态脚本校验数字、引用、黄金算例、源容量与文档完整性，输出static_report；应用caseID默认NOT_RUN，只有真正跑了对应实现才改状态。未做的新生活版禁止沿用旧Mac包名和旧测试数量宣传。

GitHub Actions仅contents:read检查与导出，不自动修改源码或主分支。本文档完成不是游戏完成；后续功能实现需要真正的Swift开发、SDK构建和M4体验证据。
