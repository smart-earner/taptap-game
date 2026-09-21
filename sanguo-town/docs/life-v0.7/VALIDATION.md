# PRD v0.7.1 四维与技能库验证记录

本次是人物规格与Python参考实现验证，不是Swift游戏发布。软件仍town-0.5＋desktop-0.1。

验证输入提交：`b0a5915f6c73e4476cebeff42706e97643f1bfca`。
[实际运行记录](https://github.com/smart-earner/taptap-game/actions/runs/35555140138)

|检查|结果|范围|
|---|---:|---|
|能力配置与参考计算|18测试通过|四维、1—5技能、叠加、任职、重命名一致性|
|基础规格与数值参照|522通过，0失败|不是新城市引擎|
|跨文件、开局和全文导出|57通过，0失败|包含能力专章和第四份技能配置|
|新生活版应用验收|72项，全部NOT_RUN|不以参考计算代替|
|M4实机与新生活引擎|NOT_RUN|未改Sources、Tests、Package.swift|

人物数据已移除内嵌prefect/commander效果与按姓名的policy_fit；能力通过skill_id解析。反例是测试方法内的多组输入，不重复计成游戏测试。Python参考器还未与Swift世界状态、存档迁移或原生技能UI集成。当前存档不被修改，作物/饭食/城建/军粮基础参数不变。

## 复现

```sh
cd sanguo-town
python3 scripts/validate_hero_v071.py --output dist/prd-v07
python3 scripts/validate_prd_v07.py --output dist/prd-v07
python3 scripts/check_prd_v07_delivery.py --output dist/prd-v07
```

上一版0.7.0记录保存在Git历史；旧519/54规格检查及客户端201项运行测试都不代替本轮能力系统验收。CI仅提交到人物规格分支，不自动修改main；经回读核对后再手动合入。
