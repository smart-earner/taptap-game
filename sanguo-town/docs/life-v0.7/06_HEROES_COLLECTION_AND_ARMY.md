# 06 三十武将、招募、培养与收藏
**PRD v0.8.0。常住全武将，5位开局 + 25位招募。**

## 6.1 全量角色表
四维按政/智/武/统排列，技能ID取锁定技能库。属性是游戏设定。starting人物不再执行任何招募。表中的T为招募层，min为已拥有数量；只限制发现资格，不能作为额外隐形收费。
|ID/姓名|四维|技能ID|默认偏好|招募模板/T/min|
|---|---|---|---|---|
|xunyu 荀彧|94/88/35/55|agriculture,cookery,appeasement,kings_counsel|food|founding/0/0|
|zhaoyun 赵云|62/74/94/92|patrol,drill,escort,dragon_courage|logistics|founding/0/0|
|lusu 鲁肃|86/84/40/70|commerce,logistics,diplomatic_plan|trade|trade/0/5|
|liang 诸葛亮|92/96/35/85|construction,metallurgy,restoration,logistics,sleeping_dragon|craft|craft/0/5|
|guanyu 关羽|60/72/96/90|rationcraft,drill,escort,martial_sage|guard|route/0/5|
|zhangfei 张飞|42/55/97/88|gathering,construction,escort,thunder_roar|supply|founding/0/0|
|caocao 曹操|94/92/72/96|agriculture,logistics,commerce,drill,rearguard|food|supply/0/5|
|liubei 刘备|84/78/76/82|appeasement,agriculture,logistics|food|founding/0/0|
|sunquan 孙权|88/81/64/84|commerce,logistics,patrol,drill|trade|trade/0/5|
|simayi 司马懿|91/97/36/93|logistics,commerce,rearguard,drill|food|supply/1/8|
|guojia 郭嘉|74/97/29/70|escort,rearguard,logistics|guard|route/1/8|
|jiaxu 贾诩|85/96/28/72|commerce,rearguard,logistics|trade|trade/1/8|
|pangtong 庞统|85/96/36/82|construction,metallurgy,restoration,logistics|craft|craft/1/8|
|xunyou 荀攸|89/95/30/75|rationcraft,logistics,rearguard|food|supply/1/8|
|chenqun 陈群|96/83/26/55|appeasement,agriculture|food|supply/2/12|
|manchong 满宠|86/82/64/80|patrol,construction,rationcraft|guard|route/2/12|
|zhangzhao 张昭|94/86/24/48|commerce,appeasement,logistics|trade|trade/2/12|
|huangyueying 黄月英|80/94/30/55|carpentry,metallurgy,restoration|craft|founding/0/0|
|zhouyu 周瑜|85/95/71/96|drill,escort,logistics,metallurgy|guard|route/2/12|
|luxun 陆逊|90/95/65/94|drill,rearguard,agriculture,logistics|food|supply/2/12|
|lumeng 吕蒙|73/85/82/90|drill,escort,patrol|guard|route/3/18|
|zhangliao 张辽|65/78/92/94|drill,escort,patrol,rearguard|guard|route/3/18|
|xuhuang 徐晃|58/72/91/88|rationcraft,drill,rearguard|guard|route/3/18|
|xiahoudun 夏侯惇|70/65/90/86|gathering,construction,drill|supply|field/3/18|
|xuchu 许褚|28/40/98/70|gathering,rearguard|supply|field/3/18|
|machao 马超|40/58/97/88|patrol,escort,drill|guard|route/4/24|
|huangzhong 黄忠|58/68/94/87|drill,escort,rearguard|guard|route/4/24|
|weiyan 魏延|52/73/92/90|patrol,rationcraft,escort|guard|route/4/24|
|ganning 甘宁|43/70/94/86|patrol,escort,logistics|guard|route/4/24|
|lvbu 吕布|24/38/100/92|drill,escort,gathering|guard|route/4/24|
所有30人都可做基础工作，不存在普通人口50属性兜底，也不需要每工种凑一名专属武将。六类偏好仅同优先任务排序。职业XP、属性、skillID三层分开；固定技能1—5项、最多1特色，暂不学技/洗练/手动放招。

## 6.2 招募配置可直接执行
每位非开局人物按上表获得固定模板，不能按姓名走特殊引擎分支。净等待在准备劳动完成时开始；未发现只是目录，不占人/访客实体。
|模板|必须满足的实际发现条件|三段等待秒|三段现金|第二段物料|
|---|---|---|---|---|
|field|harvested_lots>=1|300/1800/300|10/20/20|grain2|
|supply|consecutive_full_meals>=4|300/2400/600|15/25/20|meal4|
|trade|building_market>=1 且 external_settlements>=3|600/3600/600|20/40/30|grain2|
|craft|building_workshop>=1 且 forge_batches>=1|600/5400/900|25/50/35|tools2|
|route|building_station>=1 且 consecutive_full_meals>=4|600/3600/600|20/40/30|rations4|
|feast|building_tavern>=1 且 public_meals_consumed>=16|300/2400/600|15/25/20|meal4|
条件键含义：harvested_lots不同收割结算数；consecutive_full_meals连续餐覆盖100%；external_settlements不同外部订单结清数；forge_batches真实器材批次；public_meals_consumed真实常住用餐份数；building_x为已完工级别。没有登录/开图鉴计数。
T0..4的钱乘数1/1/2/2/3；等待乘数1/2/2/3/3；物料不乘。每段实际经办60准备+30交接人工，使用merchant（接待/共事）与courier（邀留）权重。三段净等待外部联系，不把未拥有候选当免费工人。
完整流程 UNDISCOVERED→DISCOVERED→AUTHORIZED→STAGE_WAIT_INPUT→PREPARE→CONTACT_WAIT→HANDOFF→STAGE_COMPLETE，重复三段后→ARRIVING(300秒)→RESIDENT。阶段准备开始现金/输入转消费，输出是进度而不是新资源；首两段无候选劳力。
选心愿必须展示总上限：sum(三段钱)×T钱乘数、各阶段材料、净等待之和×T等待乘数、270基准人工秒、最后300旅行秒；不含排队/路程，不能报保证到达时刻。一次授权总价，逐段冻结当前阶段资金，锁quoteHash；超预算拒绝，不默许追价。
邀留PREPARE前查04章供给、1床、常住<30、唯一heroID以及未来到餐预测，同时预留bedID。开始邀留后这床不能给别人；到达时原子prospect→resident、消费预留、分配住所、加入下一餐。场景如提前出现候选必须是同一prospect，不能在到任再造一份。

## 6.3 切换/暂停/重放
最多1主动心愿（名将/武器/马/木印共享）、3关注。切换只停止旧目标的新阶段，已开始段安全完成并停在边界；已出发的人必须抵达保留床位。未开始可释放现金/物料/床；已消费不退款；关闭游戏不重置等待和prospectID。开局五将任何招募命令返回ALREADY_OWNED。
最终阶段取消须明确确认放弃未消费预留，已ARRIVING不允许抹除角色；可在到达后调整偏好，不自动退人。全部25人一城和平可达；没有“先有这个角色才能开启其招募所需工作”的环。

## 6.4 木印与六兵器
木印：治理被接受后可选10铜+木2，公共木作360人工秒；完成唯一founders_seal，官署展示，无倍率。
|ID/名称|发现|铜|外联秒|修复人工秒|材料|装备四维|
|---|---|---:|---:|---:|---|---|
|silver-spear 银纹长枪|workshop1|50|600|300|木2铁2|统2武2|
|dragon-spear 龙胆亮银枪|赵云已拥有+workshop1|480|14400|900|铁12器材2|统3武4|
|crescent-blade 青龙偃月刀|关羽已拥有+defense1|520|21600|1080|铁15木3|武6|
|serpent-spear 丈八蛇矛|张飞已拥有+industry1|480|21600|1080|铁12木4.5|武6|
|qinggang 青釭剑|外部结清3+academy1+workshop1|560|28800|1200|铁12器材3|智4武2|
|seven-star 七星宝刀|academy1+E08已读+workshop1|580|36000|1500|铁10器材4|智3政3|
两阶段：联系花floor(总铜×40%)，60准备+净等待+30交接，生成唯一不可装备原件；修复花余款和表内材料，原件进WIP，真实修复完成变成可装备物。只能在修复席完成，不因有卡片就拥有武器。
每人最多1武器/1坐骑，各属性封顶100；未跨整数效果门槛显示0贡献。唯一物不出售、不合成吞掉；装备移交同城且双方非任务锁，实际持有位置一致，不生成多份。

## 6.5 四马
|ID/名称|发现|铜|联系秒|被动驯养秒|人工秒|路径食粮|个人空载加速bp|
|---|---|---:|---:|---:|---:|---:|---:|
|yellow-horse 黄骠马|stable1|120|1800|7200|300|1.5|500|
|red-hare 赤兔|黄骠已拥有+外部3次|600|28800|43200|1200|5|1000|
|dilu 的卢|黄骠已拥有+water1|500|21600|36000|1000|4|800|
|jueying 绝影|黄骠已拥有+road1|560|28800|43200|1200|5|1200|
联系40%预款，60准备/30交接；驯养余款，人工前后各一半，食粮在准备时完整消费，中间被动。井须可达，无水/草库存。联系结束生成唯一马实体并由真实马夫牵入预留马位；到位后驯养。
驯养路径已含食粮，不重复收普通照料；入藏后每cycle粮0.25+30人工。缺料等、不死不追债，新出行暂不享速度加成；照料恢复后恢复。只加实际带马的个人空载路段，不加全城物流/板车。马不是肉。
所有藏品为8资源报价，不允许后台回读旧木构/草/酒。完整藏品参数同样收入新JSON，UI只读报价。

## 6.6 军务边界与宝鉴
v0.8不创建无名士兵/军团/伤兵/出征。barracks训练位供已拥有武将120秒守备演练，priority60，按有效人工累积guardXP，不提升另一个train等级、不叠额外奖励；粮食按普通人餐窗消费。
宝鉴四态未发现/已发现/进行中/已拥有；详情优先显示住处/正在做/下一站/偏好，其次四维技能。军团专用技能在当前版本明确标未启用，不允许解释为已加工作效率。开局5人直接已拥有，其余25人显示逐项条件缺口/已付阶段/预计最少剩余时间。获得入账不依赖揭晓。
兵器在藏架或本人身上，马在马厩/路上，木印在官署，角色在真实地图；卡片展示不增加物品。
