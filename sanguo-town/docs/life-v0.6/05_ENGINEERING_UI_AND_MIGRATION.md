# 05 全桌面表现、数据接口、存档迁移与实施分工

## 5.1 版本与职责边界

目标存档schemaVersion=5、rulesVersion=life-0.6、contentVersion=0.6.0、layoutVersion=3。运行代码目前仍town-0.5+desktop-0.1，前述版本仅为待开发目标。已有schema1—4保留独立解码路径；未知高版本只读报错，不按空存档重建。

新增SanguoCore/Life模块负责所有资源任务及事件；SanguoPresentation只读投影；SanguoDesktopHost继续只负责窗口承载；SwiftUI负责授权、查阅与错误显示。不得在SpriteKit.update、动画完成回调、卡牌揭晓或窗口打开回调里写资源和经验。预览、教学快进使用独立测试存档，不污染真实世界。

## 5.2 必须存在的数据结构

|实体|必需字段与类型|不可省略的不变量|
|---|---|---|
|LifeState|version:Int、epoch:Int64、seed:UInt64、cities字典、agents字典、tasks字典、lots字典、ledger、nextSequence:Int64|单一世界，无第二套城市经济|
|Agent|id:String、origin:{founding,immigration,hero,recruit,visitor}、cityID、personID?、homeID、role、shift、positionSegment、activeTaskID?、skills、restSeconds|同ID只在一城或一条旅程；一人一独占任务|
|WorkOrder|id、parentID?、kind、priority:Int、authorityID、consumerKey、workerID?、sourceID?、targetID?、state、createdAt、startedAt?、deadline?、remainingWorkBP:Int64、rateSnapshot:Int64、passiveDueAt?、inputReservations[]、outputSpaceReservation、recipeVersion、settlementID|WAIT输入不占工人；COMPLETE不得再扣/发|
|CargoLot|id、originLotID、resourceID、amount_mU:Int64、location:{stock,carried,wip,consumed}、locationID、ownerCityID、reservationIDs[]、originEventID|数量≥0；在途和在仓互斥|
|Storage|id、cityID、acceptedResourceIDs[]、capacityVolume_mU、lotIDs[]、reservedIncomingVolume_mU|在库体积+入库预留≤容量，预留不是新货|
|CropBed|id、farmID、cropID、state、growthSeconds:Int64、wateringMask:UInt8、activeTaskID?、harvestCycleID、seedOrigin|两次浇水分别至多完成一次，收割ID幂等|
|Animal|id、kind:{pig,collectionMount}、stage、segmentsDone、growthSeconds、careTaskID?、location、sourceContractID、lastCaredCycle|消费猪时销毁同一实例，马不进肉配方|
|MealWindow|id、cityID、cycle、offset、expectedAgentIDs[]、allocations、servedAmount_mU、deadline、closed|每消费者至多一份，已关账不重复降满意度|
|AppointmentPlan|id、authorityID、personID、sourceCity、targetCity、proxyID、lockedTargetOffice、state、arriveAt|到达前不任目标太守；缺代理不启程|
|Contract|id、kind、quoteVersion、buyer/seller、quantity、unitPrice、fee、reservedCash、carrierID、dueAt、state|回款/到货只发生一次，权限不随改策扩大|
|CitySnapshot|time、rulesVersion、layoutVersion、buildings、constructionStages、civicLevels、visibleLotSummary、agentLocations、lightingPhase、collectionsDisplayed|历史快照不引用当前状态重绘成新城|
|LedgerEntry|eventID、time、reasonCode、taskID、debits[]、credits[]、conversionRecipeID?、previousHash|材料转换写配方，非转换须同资源守恒|

枚举必须完整switch；未知资源/工种/状态拒绝写入并保留原文件。数量/工作/现金全部整数；所有乘法先检查Int64溢出，输入设置合理上限。remainingWorkBP=baseWorkSeconds×10000，推进dt时减dt×sum(workerRateBP)，完成事件采用ceil(remaining/rate)，最后一步不得负数。暂停/恢复不因分段推进丢舍入余量。

rate在新人工阶段或工作组成员改变时固化；成员变更先结算上一段贡献，不回溯。每人XP按实际有效劳动秒累计，不能因为加成替他计入未做的秒。转换记录只包括实际消耗的输入和合法输出，仓储移动不发配方奖励。

## 5.3 命令接口与统一事务

公共CommandEnvelope：id:String、expectedRevision:Int64、principal:{player,prefect(id),governor(id)}、action、issuedAt:Int64。用户命令发送前先advance到当前现实水位；系统规划命令使用当前模拟时间。重复id且内容相同返回原receipt，重复id但内容不同返回DUPLICATE_ID；版本不符返回STALE，不部分执行。

lifeAdopt(policy,investment)：仅玩家；运行迁移预检并原子保存。
setCityPolicy(cityID,policy)：玩家或授权都督；改变后续目标，不取消在途/在制。
setInvestment(style)：玩家；下一财政期生效。
setWish(itemID|null)：玩家；签完整路径上限，保留已启动阶段。
appointPrefect(cityID,personID)、establishDistrict(cityIDs,governorID,talentIDs)、authorizeAppointment(personID,destination)：对应岗位权限，不绕过旅行和代理。
authorizeLegion(cityID,capacity,totalCashCap)、authorizeRegion(goalID)：仅玩家；不自动批准战争或新城。
pauseNewDevelopment(bool)：玩家；只暂停新可选工程，不停止民用生产、食物、现有照料与已开工安全收尾。
pauseOrder(orderID)、cancelOrder(orderID)：玩家或本辖主管；只有该状态允许的取消方式。
equipUnique(itemID,personID|null)、lockPerson、lockPlot、rememberCity、removePinnedMemory：玩家；变更仅影响对应对象。
setDesktopPreferences、openCodex、openCity、setRenderQuality：本地显示偏好，不是WorldCommand，永不产生资源。

事务顺序：校验参数→校验版本/权限→克隆候选状态→预留与任务变更→完整不变量检查→序列化到临时文件→校验写入→原子替换并轮转3个备份→公布revision/receipt。落盘失败不能把候选状态发布给UI，也不能记录成功奏报。重新规划可以批量提交多个子单，但必须整批成功或整批回滚。

## 5.4 地图、道路与全桌面

逻辑世界1920×1080为制作坐标；窗口覆盖用户选定NSScreen.frame，按逻辑点布局，不把Retina像素当游戏路程。完整桌面层不是独占全屏，不压工作窗口、不改壁纸、不扫描桌面文件位置。主要建筑和工作点避开可用区的菜单栏/Dock，背景河流、郊野可以延伸到边界。16:10等屏幕扩大郊野留白，不拉伸建筑。

核心地块中心：0府署(1060,770)、1住宅(910,770)、2住宅备选(770,780)、3住宅备选(915,925)、4农庄(360,700)、5粮仓(540,600)、6集市(920,570)、7工造(1320,540)、8饭馆(1060,570)、9马厩(1540,400)、10驿站(1420,260)、11营地(1610,650)、12住宅备选(1060,925)、13仓储备选(610,800)、14农庄备选(360,460)、15工造备选(1320,800)。中心稳定，太守选功能用途时只在其可用类型槽内安排；旧存档迁移保留建筑所属slotID，不交换资产。

道路基线：纵向x={140,680,1200,1780}，横向y={200,380,640,840,1000}的20个交点；连接相邻交点形成固定图。建筑入口为中心(x,y-20)，先连接同x的最近水平道路投影，再连接该水平线相邻交点。农田床位在西侧郊野，按3列4行(180+60×col,300+70×row)，连接最近主路；林地(170,900)、井(720,600)、矿点(170,150)、采石点(370,150)、城门(1540,200)均有显式入口连接。路径按Dijkstra距离，同距按节点ID；无路就WAIT_ROUTE，不直线穿房。

这些是可执行布局基线而非最终美术。脚底可行走区域与建筑地面碰撞盒必须单独定义，屋顶遮挡不等于禁止通行。最少人工验收所有主要源→厨房/仓库/工地路线。人群允许±4单位视觉错位避免重叠，错位不增加经济路程；实际入口设备排队要进入模拟任务。

标准最多绘制96人、省电48、丰富160；动物24；不足不凑数。具名人物、携货者、工地工人、当前巡逻依次优先，随后按agentID稳定截取，不每帧随机换人。全桌面15fps、省电8fps、主动窗口30fps。人物参考高度38单位，目标逻辑高度不小于22点；屏幕太小提供可选关注片区，不能把人物缩成无法分辨的点。

全桌面照明只作用于城景节点，禁止黑色全屏层把用户壁纸整体罩黑。昼亮度1，晨/暮0.8，夜0.45；住宅有人且未睡前窗灯亮，睡眠后仅20%固定安全灯；岗亭与巡兵火把保持。灯光不用真实动态阴影作P0要求，优先预烘焙素材降低能耗。

## 5.5 行为和美术交付契约

每个taskType都必须配置：去哪、携带什么、工作动作、工作后物资出现在哪里、夜晚如何收尾。资源袋使用grainBag、logBundle、oreBasket、mealTray、rationCrate、waterBucket等确定类型；实际空载不显示满车。携带物数量可简化为1—4个图元，但inspect数据必须给真实数量。

农业：播种/浇水/成熟/收割/成袋四类可辨状态。猪：幼体/成长/待出栏/肉筐转化；收藏马：牵入/照料/安置，未开发骑乘时不让马贴在步行脚下。厨房：备料/炊煮/出餐/送餐；工地：四阶段结构；冶炼：投料/炉火/取锭；居民：通勤、工作、就餐、返家、睡眠；巡兵：领灯、巡更、驱离。逐帧细节可由美术调整，但不能改任务工时。

动画来自真实agent的状态与路径，只显示当前正常模拟时点。离线回来不补播30天。关窗口与绘制上限不会让任务“看不到就不做”。被动发酵无人值守时炉火/坛子状态保留，不安排一个永远站着却占用劳力的假工人。

小贼仅在cycle%10==0的夜晚尝试生成，使用保存seed与cityID/cycle计算0..99，<25才候选；最多1人，phase2280进入外侧道路，300秒内离开或被实际巡兵侦测。侦测半径100+城防每级20，巡兵必须实际靠近，不能只看是否建营地就判抓到。小贼不来自低满意度居民；首版无资产损失、无抓贼奖金、无用户点击收益。没有巡兵碰到就记录“可疑来客离开”，不能写成功抓捕。

## 5.6 UI：先知道在做什么，再愿意收藏

首次最多两项必要确认：接受长期治理与默认民生保护；选择或接受默认安民方针。命名和开城木印均可跳过。主屏三条：当前城在做什么、当前期待成果、最近真实成果；有阻塞用02章原因码。不开管理面板也能继续种粮、吃饭和建设。

菜单栏“看看我的城”打开普通可交互视图，桌面继续鼠标穿透。点人物只在这个视图可用，显示身份、任务、来源/去向、携带量和下一班次；不得为了查看穿透桌面偷偷增加输入监控权限。宝鉴入口一级可见，不藏在多层折叠菜单；卡片不是下拉名字。

条件未满足按钮要禁用并显示缺口。例如“青釭剑：未获银纹长枪”“军团：缺口粮12份”，不让用户点击后只返回一个通用错误。等待材料/被动生长显示不同进度。已获得卡片和物品在城内实际可见，不需领取；揭晓动画关闭后不丢东西。

## 5.7 迁移算法：不双产、不清档、不追溯重扣

先在旧规则下advance到用户同意时刻t，不推进未来。完整备份旧文件与hash，记录migrationID=saveID+sourceRevision+life-0.6。旧grain/wood/iron/wine/tools按1:1 mU放入对应新库位；没有肉、菜、熟食、猪、额外人，不凭迁移白送这些资产。旧总存量大于新容量时创建只读legacyOverflow容器，只允许出库、禁止新入库，直到自然消化；不删除溢出物。

常住人口N拆成确定性agent：已有具名人物在该城先占名额，剩余生成migration-{city}-{n}普通居民；N不足以包含现有具名人物时预检失败，提示修复存档，不静默增人口。原职位保持；当前旧版population*3/4劳力不再作为第二套生产者。

为兼容新生产链，迁移确认清单显式说明：已存在府署获得不可出售公共灶/木作桌、农庄获得留种圃/碾米位、城内获得公共井工作点。这些是规则兼容设施，不计“玩家花钱建成”的成果，不赠铜钱；旧存档已有场景照片不被重绘成新布局。

旧有限已付费/已开始义务放入legacyObligations：保留原quote、remainingWork、dueAt、reservedStock、moneySpent、output以及原结束条件。映射对应实际agent占用，不能同时接life任务；已承诺旧班次允许一次性跨夜收尾，标记grandfathered，不计新夜间休息罚分。只收尾这些旧义务，不再启用旧prepareBatches或定时自动卖酒循环。未开始且无实际付款的旧预测任务撤销，释放预留。

每条旧义务结束用桥接适配器把合法结果写进新账本一次，并移除对应旧资源预留。老工程占地不变，老收藏路径未完成的已授权阶段继续原版本成本，不按新招募表追扣。所有新的订单使用life-0.6报价，两个引擎绝不能同时自动生产同一时段。

最后检查总库存、所有预留、人口ID、官职、唯一物品和现金与迁移前一致（只发生已明确的库位/状态重分类）；完整写入schema5后才公布迁移成功。取消迁移不改原文件；磁盘失败保留原存档；重复migrationID返回已成功回执，不能再生成兼容设备或居民。

## 5.8 工程拆分和范围冻结

L1：数据结构、任务账本、四作物/十配方/16人餐食、相同输入的离线一致性。没有L1就不接表现，禁止旧产率+新小人双产。
L2：全桌面地图和主要劳动动作、搬运物件、前台任务查询，保留普通窗口。
L3：班次、回家、餐服、夜巡/外部轻事件，重新测试作息不降低基础保供可达性。
L4：六将效果、五条新招募、十件唯一藏品、开城木印、自动分层调任和成长册。
L5：逐车新城及更通用跨城生产协同，单独验收；0.6核心发行候选不依赖L5。L5按钮未完成前禁用并写“规划中”，不能假装已能使用。

0.6明确不做：完整三路战斗、多人联网、自由画路、疾病死亡、食物腐败、繁育、每日强制任务、股票/按键采集、自动换装、商业级骑乘精修。它们不是开发自由补充项，也不因本规格已有接口就声称功能完成。

## 5.9 性能、错误和发布边界

标准压力场景每城253人×3城、每城2048待办、32动物，只有选定城市绘制。模拟用事件队列与库存索引，禁止每个agent每帧跑全图寻路；道路无变化时缓存路线。超过计算预算分块推进但不能少结算、截断粮食或只用期末产率。每批最多10000事件后让出主线程；未追赶完显示“正在还原城务”，用户不能对旧revision下命令。

测试目标参考机为M4/16GB/macOS15+，不是已确认的用户具体配置。正常可见状态单核平均CPU目标≤8%、隐藏渲染暂停时≤2%、30日补算目标≤20秒、内存目标≤500MB；均须实际profiling，未达标不能把这些写成实测值。能耗优先于160人丰富档。

保存每120秒、重大命令/迁移/退出前执行；保留3备份和一份迁移前备份。解析失败、非法库存、未知schema均显示原始错误与“恢复备份”入口，恢复需确认目标时间，不自动清空。首次发布仍需Apple Silicon SDK构建、Finder鼠标穿透、多屏插拔、Spaces、睡眠及用户M4验收；静态规格脚本通过不替代这些。
