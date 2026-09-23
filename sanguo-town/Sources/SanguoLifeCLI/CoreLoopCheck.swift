import Foundation
import SanguoLife

enum CoreLoopCheck {
    static func run() throws {
        var passed=0
        func check(_ value:Bool,_ message:String) throws {
            guard value else {throw LifeError.invalid("CORE LOOP FAILED: \(message)")}
            passed+=1
            print("PASS \(message)")
        }
        let catalog=try LifeCatalog.bundled()
        let oldFragments=(0..<24).map { index in
            LifeWarSquad(id:String(format:"old-%02d",index),kind:"infantry",survivors:1,
                         cityID:"00",gearOrigin:"fixture")
        }
        let freshSquads=(0..<20).map { index in
            LifeWarSquad(id:String(format:"new-%02d",index),kind:index==19 ? "sapper":"infantry",
                         survivors:10,cityID:"00",gearOrigin:"fixture")
        }
        let allSquads=oldFragments+freshSquads
        let sortie=LifeWarContract.sortieSquadIDs(allSquads,capacity:200,needsSapper:true)
        let used=allSquads.filter{sortie.contains($0.id)}
        try check(sortie.count==20 && sortie.contains("new-19") &&
                  used.reduce(0){$0+$1.survivors}==200 &&
                  allSquads.filter{!sortie.contains($0.id)}.reduce(0){$0+$1.survivors}>=10,
                  "terminal sortie takes twenty full squads including sappers while keeping ten real defenders")
        let limitedSortie=LifeWarContract.sortieSquadIDs(allSquads,capacity:85,needsSapper:true)
        let limitedCount=allSquads.filter{limitedSortie.contains($0.id)}.reduce(0){$0+$1.survivors}
        try check(limitedCount==85 && limitedSortie.count<=20 && limitedSortie.contains("new-19"),
                  "sortie respects hero command capacity and fills unused seats with surviving fragments")
        try check(LifeWarContract.recoveryWaitReason(until:3_601,now:0).contains("约2小时") &&
                  LifeWarContract.recoveryWaitReason(until:1,now:0).contains("约1小时") &&
                  !LifeWarContract.recoveryWaitReason(until:3_601,now:0).contains("UTC"),
                  "war recovery explains its remaining time without exposing an internal epoch")
        var runtime=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true,rngSeed:1)
        let legacyWorld=runtime.world
        let migrationDirectory=FileManager.default.temporaryDirectory.appendingPathComponent("sanguo-v12-migration-\(UUID().uuidString)")
        defer {try? FileManager.default.removeItem(at:migrationDirectory)}
        let migrationStore=LifeSaveStore(url:migrationDirectory.appendingPathComponent("world.json"))
        try migrationStore.save(legacyWorld)
        let oldBytes=try Data(contentsOf:migrationStore.url)
        var promoted=try LifeRuntime(catalog:catalog,world:LifeSaveStore.decode(oldBytes))
        try promoted.enableFormalV12(realUTC:12_345)
        try check(promoted.world.format==LifeV12Contract.format && promoted.world.isCurrentHeroTown &&
                  promoted.world.heroTown?.contentHash==LifeV12Contract.contentHash &&
                  promoted.world.heroTown?.courtyard != nil && promoted.world.campaign?.startedUTC==12_345 &&
                  promoted.world.gacha==legacyWorld.gacha && promoted.world.treasury==legacyWorld.treasury &&
                  promoted.world.lots==legacyWorld.lots,
                  "format-four town promotes to v0.12 with a real campaign but without changing cards, coins or stock")
        let promotedWorld=promoted.world
        try promoted.enableFormalV12(realUTC:99_999)
        try check(promoted.world==promotedWorld,
                  "repeating the v0.12 migration cannot restart war or duplicate the upgrade")
        try migrationStore.save(promoted.world)
        try check(try migrationStore.load()==promotedWorld &&
                  Data(contentsOf:migrationStore.url.appendingPathExtension("bak1"))==oldBytes,
                  "an atomic v0.12 save retains the exact legacy bytes as the first backup")
        let archiveName="world.json.pre-v012-"
        let archives=try FileManager.default.contentsOfDirectory(at:migrationDirectory,includingPropertiesForKeys:nil)
            .filter{$0.lastPathComponent.hasPrefix(archiveName)}
        try check(archives.count==1 && Data(contentsOf:archives[0])==oldBytes,
                  "the version-four bytes are durably archived outside the rotating backup slots")
        for _ in 0..<4 {try migrationStore.save(promotedWorld)}
        try check(Data(contentsOf:archives[0])==oldBytes &&
                  Data(contentsOf:migrationStore.url.appendingPathExtension("bak1")) != oldBytes,
                  "ordinary v0.12 autosaves cannot overwrite the pre-upgrade archive")
        var futureWorld=promotedWorld
        futureWorld.format=8
        try check((try? LifeSaveStore.encode(futureWorld))==nil,
                  "unknown future save formats are rejected instead of silently rebuilt")
        var wrongLegacy=legacyWorld
        wrongLegacy.heroTown!.contentHash="tampered"
        try check((try? LifeRuntime(catalog:catalog,world:wrongLegacy))==nil,
                  "a legacy content-hash mismatch cannot enter the v0.12 migration")
        var warLegacy=runtime
        try warLegacy.enableSharedCourtyards()
        try warLegacy.enableWar(realUTC:777)
        let existingCampaign=warLegacy.world.campaign
        try warLegacy.enableFormalV12(realUTC:99_999)
        try check(warLegacy.world.isCurrentHeroTown && warLegacy.world.campaign==existingCampaign &&
                  warLegacy.world.wallUTC==777,
                  "a format-four town with an existing campaign keeps every war clock and point on promotion")
        try check(LifeHappinessContract.workModifierBP(happiness:95,job:"miner") == 500 &&
                  LifeHappinessContract.workModifierBP(happiness:70,job:"miner") == 0 &&
                  LifeHappinessContract.workModifierBP(happiness:50,job:"miner") == -500 &&
                  LifeHappinessContract.workModifierBP(happiness:30,job:"miner") == -1_000 &&
                  LifeHappinessContract.workModifierBP(happiness:20,job:"miner") == -1_500 &&
                  LifeHappinessContract.workModifierBP(happiness:20,job:"cook") == 0 &&
                  LifeHappinessContract.workModifierBP(happiness:20,job:"porter") == 0,
                  "shared happiness changes optional work rate without slowing the minimum food-and-care chain")
        let quotedWood=runtime.world.projects.values.filter{!$0.completed}
            .reduce(Int64(0)){$0+$1.materials["wood",default:0]}
        try check(runtime.world.goldFuelWoodReserve==Int64(runtime.world.gacha!.stars.count)*250+quotedWood,
                  "gold smelting protects the S03 two-cycle meal wood and unfinished project quotes")
        var remoteBuffer=runtime
        try remoteBuffer.enableWar(realUTC:0)
        var bufferWorld=remoteBuffer.world
        let capitalIronBefore=bufferWorld.capitalGatheringStock(.iron)
        let globalIronBefore=bufferWorld.amount(.iron)
        let capitalToolsBefore=bufferWorld.capitalGatheringStock(.tools)
        let globalToolsBefore=bufferWorld.amount(.tools)
        let capitalRationsBefore=bufferWorld.capitalGatheringStock(.rations)
        let globalRationsBefore=bufferWorld.amount(.rations)
        bufferWorld.lots["remote-iron-fixture"] = .init(id:"remote-iron-fixture",origin:"fixture",
                                                       location:"war-01",resource:.iron,amount:4_000)
        bufferWorld.initial["iron",default:0]+=4_000
        bufferWorld.lots["remote-tools-fixture"] = .init(id:"remote-tools-fixture",origin:"fixture",
                                                        location:"war-01",resource:.tools,amount:4_000)
        bufferWorld.initial["tools",default:0]+=4_000
        bufferWorld.lots["remote-rations-fixture"] = .init(id:"remote-rations-fixture",origin:"fixture",
                                                          location:"war-01",resource:.rations,amount:4_000)
        bufferWorld.initial["rations",default:0]+=4_000
        try check(bufferWorld.amount(.iron)==globalIronBefore+4_000 &&
                  bufferWorld.capitalGatheringStock(.iron)==capitalIronBefore,
                  "frontier iron cannot satisfy the capital mine and forge buffer without transport")
        try check(bufferWorld.amount(.tools)==globalToolsBefore+4_000 &&
                  bufferWorld.capitalGatheringStock(.tools)==capitalToolsBefore &&
                  bufferWorld.amount(.rations)==globalRationsBefore+4_000 &&
                  bufferWorld.capitalGatheringStock(.rations)==capitalRationsBefore,
                  "frontier tools and rations cannot satisfy capital production or expansion buffers")
        var academyWorld=runtime.world
        academyWorld.heroTown!.city.civics["academy"]=1
        academyWorld.lots["academy-fixture-tools"] = .init(id:"academy-fixture-tools",origin:"fixture",
                                                            location:"warehouse",resource:.tools,amount:5_000)
        academyWorld.initial["tools",default:0]+=5_000
        var academy=try LifeRuntime(catalog:catalog,world:academyWorld)
        var inFlightStudy:LifeWorld?
        for moment in stride(from:30,through:7*2_880,by:30) {
            try academy.advance(to:Int64(moment))
            if academy.world.tasks.values.contains(where:{$0.kind=="study"}) {
                inFlightStudy=academy.world
                break
            }
        }
        try check(inFlightStudy != nil && academy.world.amount(.tools,at:"warehouse")<academyWorld.amount(.tools,at:"warehouse"),
                  "an actual academy seat starts only after consuming a real tool fraction")
        let studyTask=inFlightStudy!.tasks.values.first{$0.kind=="study"}!
        let priorStudySeconds=inFlightStudy!.agents[studyTask.worker]!.workSeconds[studyTask.subject,default:0]
        let remainingStudySeconds=(studyTask.due-inFlightStudy!.time)
            + studyTask.steps.dropFirst(studyTask.step+1).reduce(Int64(0)){$0+$1.seconds}
        var reloadedStudy=try LifeRuntime(catalog:catalog,world:LifeSaveStore.decode(LifeSaveStore.encode(inFlightStudy!)))
        try reloadedStudy.advance(to:inFlightStudy!.time+remainingStudySeconds)
        try check(reloadedStudy.world.counters["study_completed",default:0]>0 &&
                  reloadedStudy.world.agents[studyTask.worker]!.workSeconds[studyTask.subject,default:0]==priorStudySeconds+300 &&
                  reloadedStudy.world.counters["study-cycle.\(studyTask.worker)"]==Int(inFlightStudy!.cycle),
                  "academy practice survives reload and awards only completed job experience once")
        var sickAcademyWorld=academyWorld
        for heroID in sickAcademyWorld.agents.keys {
            sickAcademyWorld.heroTown!.health!.conditions[heroID] = .overwork(heroID:heroID,time:0,cycle:0,duty:1_800,rest:0)
            sickAcademyWorld.heroTown!.health!.homeRecoveryLastAt[heroID]=0
        }
        var sickAcademy=try LifeRuntime(catalog:catalog,world:sickAcademyWorld)
        try sickAcademy.advance(to:1_380)
        try check(!sickAcademy.world.tasks.values.contains(where:{$0.kind=="study"}) &&
                  sickAcademy.world.counters["study_completed",default:0]==0,
                  "injured residents never take an academy seat before their health recovers")
        try check(runtime.world.storages["delivery-1"]?.capacity==16_000_000 &&
                  runtime.world.heroTown?.city.attachments["delivery"]==1 &&
                  runtime.world.amount(.meal,at:"delivery-1")==0,
                  "the founding meal depot is a real empty sixteen-volume container")
        var oldDepotWorld=runtime.world
        oldDepotWorld.storages["delivery-1"]=nil
        oldDepotWorld.heroTown!.city.attachments["delivery"]=2
        let oldDepotLots=oldDepotWorld.lots
        let oldDepotBytes=try LifeSaveStore.encode(oldDepotWorld)
        let recoveredDepots=try LifeRuntime(catalog:catalog,world:LifeSaveStore.decode(oldDepotBytes))
        try check(recoveredDepots.world.storages["delivery-1"]?.capacity==16_000_000 &&
                  recoveredDepots.world.storages["delivery-2"]?.capacity==16_000_000 &&
                  recoveredDepots.world.lots==oldDepotLots,
                  "loading an older built-delivery save reconstructs empty depots without granting meals")
        var mealDepotWorld=runtime.world
        mealDepotWorld.lots["depot-fixture-meal"] = .init(id:"depot-fixture-meal",origin:"depot-fixture",
                                                            location:"kitchen-out",resource:.meal,amount:20_000)
        mealDepotWorld.produced["meal",default:0]+=20_000
        var mealDepot=try LifeRuntime(catalog:catalog,world:mealDepotWorld)
        var sawRealDepotHaul=false
        for moment in stride(from:30,through:900,by:30) {
            try mealDepot.advance(to:Int64(moment))
            if mealDepot.world.tasks.values.contains(where:{$0.kind=="haul" && $0.target=="delivery-1" && $0.resource == .meal}) ||
                mealDepot.world.amount(.meal,at:"delivery-1")>0 {sawRealDepotHaul=true}
        }
        try check(sawRealDepotHaul,
                  "a porter reserves and carries cooked meal lots to the depot rather than conjuring stock")
        var depotDispatchWorld=runtime.world
        for (id,lot) in depotDispatchWorld.lots where lot.resource == .meal {
            depotDispatchWorld.lots[id]!.location="delivery-1"
        }
        let stagedMeals=depotDispatchWorld.amount(.meal,at:"delivery-1")
        var depotDispatch=try LifeRuntime(catalog:catalog,world:depotDispatchWorld)
        var sawDepotToHome=false
        for moment in stride(from:30,through:900,by:30) {
            try depotDispatch.advance(to:Int64(moment))
            if depotDispatch.world.tasks.values.contains(where:{$0.kind=="haul" && $0.subject=="delivery-1" && $0.target=="home-meals" && $0.resource == .meal}) ||
                (depotDispatch.world.amount(.meal,at:"delivery-1")<stagedMeals && depotDispatch.world.amount(.meal,at:"home-meals")>0) {
                sawDepotToHome=true
            }
        }
        try check(sawDepotToHome,
                  "a porter dispatches existing depot meals to an empty home container")
        let roster=runtime.definition!
        try check(roster.heroes.count==60 && Set(roster.heroes.map(\.id)).count==60 &&
                  runtime.catalog.heroes.count==60 && runtime.world.gacha?.rosterTarget==30,
                  "thirty new identities are catalogued while the opening pool remains thirty")
        try check((0...3).map{roster.availableHeroes(phase:$0).count}==[30,40,50,60] &&
                  LifeV12Roster.load().heroes.allSatisfy{$0.attributes.count==4},
                  "the same permanent pool opens ten real heroes after each population breakthrough")
        var completedPhase=runtime.world.gacha!
        completedPhase.stars=Dictionary(uniqueKeysWithValues:roster.availableHeroes(phase:0).map{($0.id,5)})
        let oldComplete=completedPhase.isComplete
        completedPhase.rosterPhase=1
        try check(oldComplete && !completedPhase.isComplete && completedPhase.poolVersion(formal:true)=="tavern-standard-v12-p1",
                  "a thirty-hero completion reopens only after the next roster phase")
        var legacy=runtime.world
        legacy.gacha!.rosterPhase=nil
        let migrated=try LifeRuntime(catalog:catalog,world:legacy)
        try check(migrated.world.gacha?.rosterPhase==0 && migrated.world.gacha?.pity==legacy.gacha?.pity,
                  "an older formal save gains the phase marker without resetting pity")
        var growth=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true,rngSeed:7)
        try growth.enableSharedCourtyards()
        var growthWorld=growth.world
        let growthIDs=roster.availableHeroes(phase:0).map(\.id).sorted()
        for heroID in growthIDs where growthWorld.agents[heroID]==nil {
            let hero=roster.hero(heroID)!
            var resident=growthWorld.agents["liubei"]!
            resident.id=heroID;resident.name=hero.name;resident.heroID=heroID
            resident.origin="recruited";resident.node="tavern";resident.home="tavern"
            resident.dining="guest-meals";resident.taskID=nil
            growthWorld.agents[heroID]=resident
            growthWorld.gacha!.stars[heroID]=1
            growthWorld.owned.append(heroID)
            growthWorld.heroTown!.ownedHeroes[heroID] = .init(heroID:heroID,star:1,sourceDrawID:"fixture",
                                                                arrivalState:"resident",arrivalAt:nil,bedReservation:"tavern-1.guest")
            growthWorld.heroTown!.courtyard!.households[heroID] =
                .init(id:"household:\(heroID)",memberPersonIDs:["hero:\(heroID)"],
                      residencePlotID:"tavern-1",unitID:nil,createdAt:0)
        }
        growthWorld.projects["repair"]!.completed=true
        growthWorld.projects["repair"]!.phase=4
        growthWorld.projects["repair"]!.completedWork=growthWorld.projects["repair"]!.totalWork
        growthWorld.projects["repair"]!.allocatedWork=0
        growthWorld.heroTown!.city.civics["water"]=2
        growthWorld.heroTown!.city.qualifiedWindows["breakthrough.stable"]=2
        growthWorld.happiness=75
        growthWorld.foodCoverage=10_000
        growthWorld.meals=(0..<4).map{index in
            .init(id:"growth-fixture-\(index)",at:0,deadline:0,expected:growthIDs,
                  served:Dictionary(uniqueKeysWithValues:growthIDs.map{($0,40)}),closed:true)
        }
        for index in growthWorld.heroTown!.city.plots.indices where
            growthWorld.heroTown!.city.plots[index].kind=="house" &&
            growthWorld.heroTown!.city.plots[index].developmentPermit {
            let plotID=growthWorld.heroTown!.city.plots[index].id
            growthWorld.heroTown!.city.plots[index].level=3
            growthWorld.heroTown!.city.plots[index].capacity=8
            growthWorld.heroTown!.city.plots[index].service=10_000
            let parcel=growthWorld.heroTown!.courtyard!.parcelByPlotID[plotID]!
            for slot in 1...LifeLayout7.units(for:3) {
                let unitID="house:\(parcel):\(slot)"
                if growthWorld.heroTown!.courtyard!.units[unitID]==nil {
                    growthWorld.heroTown!.courtyard!.units[unitID] =
                        .init(id:unitID,parcelID:parcel,plotID:plotID,occupantHouseholdID:nil)
                }
            }
        }
        growthWorld.gacha!.houseLevels=Array(repeating:3,count:8)
        growthWorld.buildings["house"]=8
        var civicWorld=growthWorld
        civicWorld.heroTown!.city.civics["defense"]=1
        civicWorld.lots["fixture-civic-grain"] = .init(id:"fixture-civic-grain",origin:"fixture",
                                                        location:"warehouse",resource:.grain,amount:120_000)
        civicWorld.initial["grain",default:0]+=120_000
        civicWorld.lots["fixture-civic-rations"] = .init(id:"fixture-civic-rations",origin:"fixture",
                                                          location:"warehouse",resource:.rations,amount:10_000)
        civicWorld.initial["rations",default:0]+=10_000
        var civicOpening=try LifeRuntime(catalog:catalog,world:civicWorld)
        try civicOpening.advance(to:780)
        civicWorld=civicOpening.world
        civicWorld.foodCoverage=10_000
        civicWorld.nextPlan=810
        var civic=try LifeRuntime(catalog:catalog,world:civicWorld)
        try civic.advance(to:810)
        let civicKinds=Set(civic.world.tasks.values.map(\.kind))
        try check(["civic_clean","civic_watch","civic_drill"].allSatisfy(civicKinds.contains) &&
                  civic.world.amount(.rations,at:"warehouse")<10_000,
                  "spare residents take real sanitation, ward and ration-paid drill shifts only after primary work")
        let assignedRations=civic.world.amount(.rations,at:"warehouse")
        civic=try LifeRuntime(catalog:catalog,world:LifeSaveStore.decode(LifeSaveStore.encode(civic.world)))
        try check(civic.world.amount(.rations,at:"warehouse")==assignedRations &&
                  civic.world.tasks.values.contains{$0.kind=="civic_drill"},
                  "reloading an in-progress civic shift does not charge military rations twice")
        try civic.advance(to:1_950)
        try check(civic.world.civicDutyCount("clean")>0 && civic.world.civicDutyCount("watch")>0 &&
                  civic.world.civicDutyCount("drill")>0,
                  "civic hygiene, safety and defense count only completed shifts")
        var staleCivic=civic.world
        staleCivic.time=3*2_880
        try check(staleCivic.civicDutyCount("clean")==0 && staleCivic.civicDutyCount("watch")==0 &&
                  staleCivic.civicDutyCount("drill")==0,
                  "unrenewed civic effects expire instead of becoming a permanent free bonus")
        var nearCapWorld=growthWorld
        let omitted=Array(growthIDs.filter{growthWorld.agents[$0]?.origin=="recruited"}.suffix(2))
        for heroID in omitted {
            nearCapWorld.agents[heroID]=nil
            nearCapWorld.gacha!.stars[heroID]=nil
            nearCapWorld.owned.removeAll{$0==heroID}
            nearCapWorld.heroTown!.ownedHeroes[heroID]=nil
            nearCapWorld.heroTown!.courtyard!.households[heroID]=nil
        }
        var nearCap=try LifeRuntime(catalog:catalog,world:nearCapWorld)
        try nearCap.advance(to:30)
        try check(omitted.count==2 && nearCap.world.agents.count==28 &&
                  nearCap.world.projects["breakthrough.1"] != nil &&
                  nearCap.world.gacha?.rosterPhase==0,
                  "twenty-eight real residents may start the first priced breakthrough without finding the last two rare cards")
        growth=try LifeRuntime(catalog:catalog,world:growthWorld)
        try growth.advance(to:30)
        try check(growth.world.projects["breakthrough.1"]?.materials ==
                    ["wood":24_000,"stone":16_000,"tools":4_000] &&
                  growth.world.projects["breakthrough.1"]?.totalWork==7_200 &&
                  growth.world.gacha?.rosterPhase==0 &&
                  growth.world.heroTown?.courtyard?.unlockedColumns==8,
                  "the governor starts a real four-stage 30-to-40 project without unlocking the next pool early")
        var kitchenWorld=growth.world
        for level in 1...2 {
            var completed=kitchenWorld.projects["breakthrough.1"]!
            completed.id="breakthrough.\(level)";completed.kind="breakthrough_\(level)"
            completed.targetLevel=level;completed.phase=4;completed.completed=true
            completed.totalWork=level==1 ? 7_200:10_800
            completed.completedWork=completed.totalWork;completed.allocatedWork=0
            kitchenWorld.projects[completed.id]=completed
        }
        kitchenWorld.gacha!.rosterPhase=2
        kitchenWorld.heroTown!.courtyard!.unlockedColumns=10
        kitchenWorld.heroTown!.courtyard!.unlockedRows=6
        for index in kitchenWorld.heroTown!.city.plots.indices where kitchenWorld.heroTown!.city.plots[index].kind=="house" {
            let number=Int(kitchenWorld.heroTown!.city.plots[index].id.dropFirst(6))!
            kitchenWorld.heroTown!.city.plots[index].developmentPermit=number<=13
        }
        var kitchen=try LifeRuntime(catalog:catalog,world:kitchenWorld)
        try kitchen.advance(to:60)
        try check(kitchen.world.projects["attachment.kitchen.2"]?.materials == ["wood":8_000,"stone":4_000,"tools":1_000] &&
                  kitchen.world.stations["kitchen-2"]==nil,
                  "the second kitchen is a priced post-breakthrough project, not a free parallel cooker")
        try kitchen.advance(to:5_000)
        try check(kitchen.world.projects["attachment.kitchen.2"]?.completed==true &&
                  kitchen.world.stations["kitchen-2"] != nil &&
                  kitchen.world.heroTown?.city.attachments["kitchen"]==1 && kitchen.world.foodCoverage<9000,
                  "the food-recovery governor finishes the second kitchen despite a poor meal window")
        var sixtyWorld=growth.world
        for level in 1...3 {
            var completed=sixtyWorld.projects["breakthrough.1"]!
            completed.id="breakthrough.\(level)";completed.kind="breakthrough_\(level)"
            completed.targetLevel=level;completed.phase=4;completed.completed=true
            completed.totalWork=[7_200,10_800,14_400][level-1]
            completed.completedWork=completed.totalWork;completed.allocatedWork=0
            sixtyWorld.projects[completed.id]=completed
        }
        sixtyWorld.gacha!.rosterPhase=3
        sixtyWorld.heroTown!.courtyard!.unlockedColumns=12
        sixtyWorld.heroTown!.courtyard!.unlockedRows=7
        sixtyWorld.heroTown!.city.civics["housing"]=3
        sixtyWorld.heroTown!.city.civics["road"]=2
        sixtyWorld.heroTown!.city.civics["water"]=2
        sixtyWorld.heroTown!.city.attachments["kitchen"]=1
        let secondFarmIndex=sixtyWorld.heroTown!.city.plots.firstIndex{$0.id=="farm-2"}!
        sixtyWorld.heroTown!.city.plots[secondFarmIndex].level=1
        sixtyWorld.heroTown!.city.plots[secondFarmIndex].capacity=4
        sixtyWorld.heroTown!.city.plots[secondFarmIndex].service=10_000
        sixtyWorld.buildings["farm"]=2
        for index in 4..<8 {
            let id="field-\(index)"
            var field=sixtyWorld.fields["field-1"]!
            field.id=id;field.state="empty";field.due=nil;field.taskID=nil
            sixtyWorld.fields[id]=field
            var storage=sixtyWorld.storages["field-1"]!
            storage.node=id;storage.incoming=0
            sixtyWorld.storages[id]=storage
        }
        sixtyWorld.lots["fixture-sixty-grain"] = .init(id:"fixture-sixty-grain",origin:"stress-fixture",location:"warehouse",resource:.grain,amount:100_000)
        sixtyWorld.initial["grain",default:0]+=100_000
        var secondKitchen=sixtyWorld.stations["kitchen"]!
        secondKitchen.id="kitchen-2"
        sixtyWorld.stations["kitchen-2"]=secondKitchen
        for index in sixtyWorld.heroTown!.city.plots.indices where sixtyWorld.heroTown!.city.plots[index].kind=="house" {
            let number=Int(sixtyWorld.heroTown!.city.plots[index].id.dropFirst(6))!
            sixtyWorld.heroTown!.city.plots[index].developmentPermit=number<=15
            sixtyWorld.heroTown!.city.plots[index].level=3
            sixtyWorld.heroTown!.city.plots[index].capacity=8
            sixtyWorld.heroTown!.city.plots[index].service=10_000
            let plot=sixtyWorld.heroTown!.city.plots[index]
            if number>1 {
                let dining="\(plot.id).meal"
                var storage=sixtyWorld.storages[dining] ?? sixtyWorld.storages["home-meals"]!
                storage.node=plot.node;storage.capacity=max(storage.capacity,16_000_000)
                if sixtyWorld.storages[dining]==nil {storage.incoming=0}
                sixtyWorld.storages[dining]=storage
            }
        }
        sixtyWorld.heroTown!.courtyard!.units=[:]
        sixtyWorld.heroTown!.courtyard!.households=[:]
        sixtyWorld.heroTown!.courtyard!.legacyOccupiedLeases=[:]
        for plot in sixtyWorld.heroTown!.city.plots where plot.kind=="house" {
            let parcel=sixtyWorld.heroTown!.courtyard!.parcelByPlotID[plot.id]!
            for slot in 1...4 {
                let id="house:\(parcel):\(slot)"
                sixtyWorld.heroTown!.courtyard!.units[id] = .init(id:id,parcelID:parcel,plotID:plot.id,occupantHouseholdID:nil)
            }
        }
        let allIDs=roster.availableHeroes(phase:3).map(\.id).sorted()
        let unitIDs=sixtyWorld.heroTown!.courtyard!.units.keys.sorted()
        for (index,heroID) in allIDs.enumerated() {
            if sixtyWorld.agents[heroID]==nil {
                let hero=roster.hero(heroID)!
                var resident=sixtyWorld.agents["liubei"]!
                resident.id=heroID;resident.name=hero.name;resident.heroID=heroID
                resident.origin="recruited";resident.taskID=nil
                sixtyWorld.agents[heroID]=resident
                sixtyWorld.gacha!.stars[heroID]=1
                sixtyWorld.owned.append(heroID)
                sixtyWorld.heroTown!.ownedHeroes[heroID] = .init(heroID:heroID,star:1,sourceDrawID:"fixture",
                                                                    arrivalState:"resident",arrivalAt:nil,bedReservation:"tavern-1.guest")
            }
            let unitID=unitIDs[index]
            let plotID=sixtyWorld.heroTown!.courtyard!.units[unitID]!.plotID
            let plot=sixtyWorld.heroTown!.city.plot(plotID)!
            sixtyWorld.heroTown!.courtyard!.units[unitID]!.occupantHouseholdID="household:\(heroID)"
            sixtyWorld.heroTown!.courtyard!.households[heroID] = .init(id:"household:\(heroID)",
                memberPersonIDs:["hero:\(heroID)"],residencePlotID:plotID,unitID:unitID,createdAt:0)
            sixtyWorld.heroTown!.ownedHeroes[heroID]!.bedReservation=plotID
            sixtyWorld.agents[heroID]!.home=plot.node
            sixtyWorld.agents[heroID]!.dining=plotID=="house-1" ? "home-meals":"\(plotID).meal"
        }
        sixtyWorld.gacha!.houseLevels=Array(repeating:3,count:15)
        sixtyWorld.buildings["house"]=15
        var concurrent=try LifeRuntime(catalog:catalog,world:sixtyWorld)
        try concurrent.advance(to:120)
        try check(concurrent.world.projects["plot.farm-1.L2"] != nil &&
                  concurrent.world.projects["plot.farm-2.L2"] != nil &&
                  concurrent.world.tasks.values.filter{$0.kind=="build"}.count<=1,
                  "the final civic breakthrough approves two projects while preserving one builder for food recovery")
        var sixty=try LifeRuntime(catalog:catalog,world:sixtyWorld)
        try sixty.advance(to:sixty.world.time+5_760)
        try check(sixty.world.projects["plot.farm-1.L2"]?.materials == ["wood":12_000,"stone":4_000] &&
                  sixty.world.projects["plot.farm-1.L2"]?.totalWork==1_800,
                  "the first population breakthrough permits eight extra beds through two separately priced farm upgrades")
        let latestSixtyMeal=sixty.world.meals.filter(\.closed).last
        try check(sixty.world.agents.count==60 && sixty.world.housing>=60 &&
                  sixty.world.stations["kitchen-2"] != nil &&
                  (latestSixtyMeal?.served.count ?? 0)*10000/max(1,latestSixtyMeal?.expected.count ?? 0)>=9500 &&
                  sixty.world.meals.filter(\.closed).suffix(3).allSatisfy{$0.served.count==$0.expected.count},
                  "a sixty-body authority fixture with built food capacity feeds its last three meals")
        if ProcessInfo.processInfo.arguments.contains("--long") {
            try sixty.advance(to:sixty.world.time+20_160)
            let lastFour=Array(sixty.world.meals.filter(\.closed).suffix(4))
            let expected=lastFour.reduce(0){$0+$1.expected.count}
            let served=lastFour.reduce(0){$0+$1.served.count}
            let ratio=served*10_000/max(1,expected)
            print("LONG 60: coverage=\(ratio)/10000, grain=\(sixty.world.amount(.grain)), meal=\(sixty.world.amount(.meal)), happiness=\(sixty.world.happiness), harvests=\(sixty.world.counters["harvests",default:0])")
            try check(lastFour.count==4 && ratio>=9_500 && sixty.world.foodEquivalent()>=60_000,
                      "the seven-day sixty-body fixture still feeds at least 95% without inventing stock")
        }
        var newcomer:String?
        for seed:UInt64 in 1...32 {
            var candidate=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true,rngSeed:seed)
            try candidate.advance(to:300)
            let action=LifeGachaAction.draw(count:1,pool:candidate.definition!.gacha.pool_version)
            let receipt=try candidate.performGacha(.player(revision:candidate.world.sequence,action:action))
            if let drawn=receipt.draws.first,drawn.isNew {runtime=candidate;newcomer=drawn.heroID;break}
        }
        guard let newcomer else {throw LifeError.invalid("CORE LOOP FAILED: fixed seed could not draw a new body")}
        try check(runtime.world.agents[newcomer]==nil && runtime.world.gacha?.arrivals[newcomer] != nil,
                  "the draw is saved before a new body enters the map")
        try runtime.advance(to:330)
        try check(runtime.world.agents[newcomer] != nil && runtime.world.gacha?.arrivals[newcomer] == nil,
                  "one new body arrives from the gate after thirty simulation seconds")
        while runtime.world.time<10_000 && runtime.world.heroTown?.ownedHeroes[newcomer]?.firstDuty?.effectiveAt == nil {
            try runtime.advance(to:min(10_000,runtime.world.time+300))
        }
        guard let duty=runtime.world.heroTown?.ownedHeroes[newcomer]?.firstDuty else {
            throw LifeError.invalid("CORE LOOP FAILED: newcomer received no verifiable duty")
        }
        try check(duty.assignedAt>=330 && duty.arrivedAt != nil && duty.effectiveAt != nil &&
                  duty.arrivedAt!>=duty.assignedAt && duty.effectiveAt!>=duty.arrivedAt! &&
                  duty.effect?.isEmpty==false,
                  "newcomer has an ordered assigned → arrived → effective contribution trace")
        let reloaded=try LifeSaveStore.decode(LifeSaveStore.encode(runtime.world))
        try check(reloaded.heroTown?.ownedHeroes[newcomer]?.firstDuty==duty,
                  "the first contribution persists across a save/load round trip")

        var war=LifeWarState(startedUTC:0)
        var raidSchedule=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true,rngSeed:9)
        try raidSchedule.enableWar(realUTC:0)
        raidSchedule.advanceWarClock(realUTC:900)
        try check(raidSchedule.world.campaign?.raidWarning?.targetCityID=="00" &&
                  raidSchedule.world.campaign?.raidWarning?.arrivalUTC==2_700,
                  "the first border raid has a saved thirty-minute warning before its arrival")
        raidSchedule.advanceWarClock(realUTC:2_700)
        let secondRaidAt=raidSchedule.world.campaign!.nextRaidUTC
        raidSchedule.advanceWarClock(realUTC:secondRaidAt)
        try check(secondRaidAt-2_700==61_200 &&
                  raidSchedule.world.campaign!.nextRaidUTC-secondRaidAt==54_000,
                  "raid intervals vary deterministically between twelve and eighteen real hours")
        var border=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true,rngSeed:10)
        try border.enableWar(realUTC:0)
        var borderWorld=border.world
        borderWorld.campaign!.raidIndex=2
        borderWorld.campaign!.cities["01"]!.owner="player"
        borderWorld.campaign!.cities["01"]!.points=Dictionary(uniqueKeysWithValues:LifeWarContract.pointKinds.map{($0,"player")})
        borderWorld.campaign!.cities["01"]!.firstCleared.insert("outer")
        borderWorld.campaign!.firstClearReceipts.insert("01:outer")
        border=try LifeRuntime(catalog:catalog,world:borderWorld)
        border.advanceWarClock(realUTC:900)
        try check(border.world.campaign?.raidWarning?.targetCityID=="01" &&
                  border.world.campaign?.raidWarning?.counterattack==true,
                  "an adjacent external border is warned instead of teleporting every attack to the capital")
        border.advanceWarClock(realUTC:2_700)
        try check(border.world.campaign?.cities["01"]?.points["outer"]=="enemy" &&
                  border.world.campaign?.cities["01"]?.supplied==false &&
                  border.world.campaign?.firstClearReceipts.contains("01:outer")==true &&
                  border.world.campaign?.reports?.last?.kind=="raid_counterattack",
                  "the third raid can retake an outer point and sever supply without refreshing its first-clear reward")
        var permitFreight=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true,rngSeed:13)
        try permitFreight.enableWar(realUTC:0)
        var permitWorld=permitFreight.world
        permitWorld.campaign!.paused=true
        permitWorld.campaign!.cities["01"]!.owner="player"
        permitWorld.campaign!.cities["01"]!.points=Dictionary(uniqueKeysWithValues:LifeWarContract.pointKinds.map{($0,"player")})
        permitWorld.campaign!.cities["01"]!.supplied=true
        permitWorld.campaign!.unlocked.insert("stone_transport")
        permitWorld.projects["repair"]!.completed=true
        permitWorld.projects["repair"]!.phase=4
        permitWorld.projects["repair"]!.completedWork=permitWorld.projects["repair"]!.totalWork
        permitWorld.projects["repair"]!.allocatedWork=0
        permitWorld.lots["fixture-permit-wood"] = .init(id:"fixture-permit-wood",origin:"fixture",location:"warehouse",resource:.wood,amount:20_000)
        permitWorld.lots["fixture-permit-stone"] = .init(id:"fixture-permit-stone",origin:"fixture",location:"warehouse",resource:.stone,amount:10_000)
        permitWorld.initial["wood",default:0]+=20_000
        permitWorld.initial["stone",default:0]+=10_000
        permitFreight=try LifeRuntime(catalog:catalog,world:permitWorld)
        try permitFreight.advance(to:30)
        let constructionHaul=permitFreight.world.tasks.values.first{$0.subject=="war-facility:stone_transport"}
        try check(constructionHaul?.target==LifeWarContract.warehouse("01") &&
                  permitFreight.world.amount(.wood,at:LifeWarContract.warehouse("01"))==0 &&
                  permitFreight.world.campaign?.builtFacilities?.contains("stone_transport") != true,
                  "Qing Shi permit queues real wood freight instead of spending capital stock into an instant distant building")
        var severedWorld=permitFreight.world
        severedWorld.campaign!.cities["01"]!.points["outer"]="enemy"
        severedWorld.campaign!.cities["01"]!.supplied=false
        var severed=try LifeRuntime(catalog:catalog,world:severedWorld)
        try severed.advance(to:1_000)
        try check(severed.world.tasks[constructionHaul!.id]?.target=="warehouse" &&
                  severed.world.amount(.wood,at:LifeWarContract.warehouse("01"))==0,
                  "a severed route turns the same in-flight construction lot back before remote unloading")
        severed=try LifeRuntime(catalog:catalog,world:LifeSaveStore.decode(LifeSaveStore.encode(severed.world)))
        try severed.advance(to:3_000)
        try check(severed.world.tasks[constructionHaul!.id]==nil &&
                  severed.world.amount(.wood,at:LifeWarContract.warehouse("01"))==0 &&
                  severed.world.campaign?.builtFacilities?.contains("stone_transport") != true,
                  "the retreating porter and material survive reload and never credit the lost city")
        let permitReload=try LifeSaveStore.decode(LifeSaveStore.encode(permitFreight.world))
        permitFreight=try LifeRuntime(catalog:catalog,world:permitReload)
        try permitFreight.advance(to:12_000)
        try check(permitFreight.world.campaign?.builtFacilities?.contains("stone_transport")==true &&
                  permitFreight.world.amount(.wood,at:LifeWarContract.warehouse("01"))<4_000,
                  "the saved cross-city material trip unloads before local construction consumes the wood and stone")
        var shipPermitWorld=permitWorld
        shipPermitWorld.campaign!.builtFacilities=["stone_transport"]
        for cityID in ["02","05"] {
            shipPermitWorld.campaign!.cities[cityID]!.owner="player"
            shipPermitWorld.campaign!.cities[cityID]!.points=Dictionary(uniqueKeysWithValues:LifeWarContract.pointKinds.map{($0,"player")})
            shipPermitWorld.campaign!.cities[cityID]!.supplied=true
        }
        shipPermitWorld.campaign!.unlocked.insert("shipyard")
        shipPermitWorld.lots["fixture-permit-iron"] = .init(id:"fixture-permit-iron",origin:"fixture",
                                                             location:"warehouse",resource:.iron,amount:8_000)
        shipPermitWorld.lots["fixture-permit-tools"] = .init(id:"fixture-permit-tools",origin:"fixture",
                                                              location:"warehouse",resource:.tools,amount:4_000)
        shipPermitWorld.initial["iron",default:0]+=8_000
        shipPermitWorld.initial["tools",default:0]+=4_000
        var shipPermit=try LifeRuntime(catalog:catalog,world:shipPermitWorld)
        try shipPermit.advance(to:30)
        try check(shipPermit.world.tasks.values.contains{$0.subject=="war-facility:ship" && $0.target==LifeWarContract.warehouse("05")} &&
                  shipPermit.world.campaign?.shipBuilt==false,
                  "Jiang Kou shipyard permit queues conserved local construction freight before a ship exists")
        try shipPermit.advance(to:24_000)
        try check(shipPermit.world.campaign?.shipBuilt==true &&
                  shipPermit.world.amount(.wood,at:LifeWarContract.warehouse("05"))<12_000,
                  "Jiang Kou gains a real ship and water route only after all local freight and construction finish")
        var firePermitWorld=shipPermitWorld
        firePermitWorld.campaign!.shipBuilt=true
        firePermitWorld.campaign!.cities["06"]!.owner="player"
        firePermitWorld.campaign!.cities["06"]!.points=Dictionary(uniqueKeysWithValues:LifeWarContract.pointKinds.map{($0,"player")})
        firePermitWorld.campaign!.cities["06"]!.supplied=true
        firePermitWorld.campaign!.unlocked.insert("fire_doctrine")
        var firePermit=try LifeRuntime(catalog:catalog,world:firePermitWorld)
        try firePermit.advance(to:30)
        try check(firePermit.world.tasks.values.contains{$0.subject=="war-facility:fire" && $0.target==LifeWarContract.warehouse("06")} &&
                  firePermit.world.campaign?.fireDrilled==false,
                  "Yan Ling doctrine permit queues conserved local drill materials before fire is enabled")
        try firePermit.advance(to:18_000)
        try check(firePermit.world.campaign?.fireDrilled==true &&
                  firePermit.world.amount(.wood,at:LifeWarContract.warehouse("06"))<4_000,
                  "Yan Ling fire doctrine activates only after the local paid materials and timed drill finish")
        var garrison=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true,rngSeed:12)
        try garrison.enableWar(realUTC:0)
        var garrisonWorld=garrison.world
        garrisonWorld.campaign!.cities["01"]!.owner="player"
        garrisonWorld.campaign!.cities["01"]!.points=Dictionary(uniqueKeysWithValues:LifeWarContract.pointKinds.map{($0,"player")})
        garrisonWorld.campaign!.cities["01"]!.supplied=true
        for id in ["guard-a","guard-b"] {
            garrisonWorld.campaign!.squads[id] = .init(id:id,kind:"infantry",survivors:10,cityID:"00",gearOrigin:"fixture")
        }
        garrisonWorld.lots["fixture-transfer-rations"] = .init(id:"fixture-transfer-rations",origin:"fixture",location:"warehouse",resource:.rations,amount:4_000)
        garrisonWorld.initial["rations",default:0]+=4_000
        let garrisonWorkshop=garrisonWorld.heroTown!.city.plots.firstIndex{$0.id=="workshop-1"}!
        garrisonWorld.heroTown!.city.plots[garrisonWorkshop].level=1
        garrisonWorld.heroTown!.city.plots[garrisonWorkshop].capacity=1
        garrisonWorld.heroTown!.city.plots[garrisonWorkshop].service=10_000
        garrisonWorld.buildings["workshop"]=1
        garrison=try LifeRuntime(catalog:catalog,world:garrisonWorld)
        try garrison.advance(to:300)
        guard let transfer=garrison.world.campaign?.transfer else {
            throw LifeError.invalid("CORE LOOP FAILED: governor started no actual border garrison transfer")
        }
        try check(garrison.world.campaign?.squads[transfer.squadID]?.transferID==transfer.id &&
                  garrison.world.campaign?.squads[transfer.squadID]?.cityID=="00" &&
                  garrison.world.consumed["rations",default:0]>=2_000,
                  "a real ten-soldier squad and escort depart only after two physical rations are paid")
        let travellingReload=try LifeSaveStore.decode(LifeSaveStore.encode(garrison.world))
        try check(travellingReload.campaign?.transfer==transfer &&
                  travellingReload.campaign?.squads[transfer.squadID]?.transferID==transfer.id,
                  "save/reload keeps the in-flight garrison and never duplicates it at the destination")
        var boundaryWorld=travellingReload
        boundaryWorld.campaign!.paused=true
        boundaryWorld.campaign!.nextRaidUTC=200_000
        boundaryWorld.lots["fixture-transfer-boundary-rations"] = .init(id:"fixture-transfer-boundary-rations",origin:"fixture",location:"warehouse",resource:.rations,amount:5_000)
        boundaryWorld.initial["rations",default:0]+=5_000
        var boundary=try LifeRuntime(catalog:catalog,world:boundaryWorld)
        let boundaryStock=boundary.world.amount(.rations,at:"warehouse")
        boundary.advanceWarClock(realUTC:86_400)
        try check(boundaryStock-boundary.world.amount(.rations,at:"warehouse")==5_000 &&
                  boundary.world.campaign?.squads[transfer.squadID]?.survivors==10,
                  "a wall-clock day boundary does not charge the marching squad twice")
        try garrison.advance(to:transfer.dueSim)
        try check(garrison.world.campaign?.transfer==nil &&
                  garrison.world.campaign?.squads[transfer.squadID]?.cityID=="01" &&
                  garrison.world.campaign?.squads[transfer.squadID]?.transferID==nil,
                  "the border gains its garrison only after the timed march finishes")
        try check(garrison.world.campaign?.garrisonHeroByCity?["01"]==transfer.workerID &&
                  garrison.world.warAwayHeroIDs.contains(transfer.workerID) &&
                  !garrison.world.campaign!.reservedHeroIDs.contains(transfer.workerID),
                  "the real escort remains at the border instead of defending remotely from the capital")
        let stationedReload=try LifeSaveStore.decode(LifeSaveStore.encode(garrison.world))
        try check(stationedReload.campaign?.garrisonHeroByCity?["01"]==transfer.workerID &&
                  stationedReload.warAwayHeroIDs.contains(transfer.workerID),
                  "a stationed officer survives reload at exactly one border city")
        var partialWorld=stationedReload
        partialWorld.campaign!.paused=true
        partialWorld.campaign!.training=nil
        partialWorld.campaign!.mission=nil
        for squadID in partialWorld.campaign!.squads.keys {partialWorld.campaign!.squads[squadID]!.missionID=nil}
        for squadID in ["guard-c","guard-d","guard-e","guard-f"] {
            partialWorld.campaign!.squads[squadID] = .init(id:squadID,kind:"infantry",survivors:10,
                                                            cityID:"00",gearOrigin:"fixture")
        }
        var partial=try LifeRuntime(catalog:catalog,world:partialWorld)
        let soldiersBeforePartial=partial.world.campaign!.soldierCount
        try partial.advance(to:partial.world.time+30)
        guard let partialTrip=partial.world.campaign?.transfer else {
            throw LifeError.invalid("CORE LOOP FAILED: no bounded partial squad dispatched")
        }
        try check(partialTrip.officerOnly != true && partial.world.campaign?.squads[partialTrip.squadID]?.survivors==4 &&
                  partial.world.campaign?.soldierCount==soldiersBeforePartial,
                  "a frontier with ten soldiers splits only four real soldiers to fit its eight-ration store")
        try partial.advance(to:partialTrip.dueSim)
        let borderSoldiers=partial.world.campaign!.squads.values.filter{$0.cityID=="01"}.reduce(0){$0+$1.survivors}
        try check(borderSoldiers==14 && (borderSoldiers+1)/2+1<=8 &&
                  partial.world.campaign?.soldierCount==soldiersBeforePartial,
                  "partial reinforcements arrive without cloning soldiers or exceeding daily local ration capacity")
        var recallWorld=garrisonWorld
        recallWorld.campaign!.paused=true
        recallWorld.campaign!.cities["02"]!.owner="player"
        recallWorld.campaign!.cities["02"]!.points=Dictionary(uniqueKeysWithValues:LifeWarContract.pointKinds.map{($0,"player")})
        recallWorld.campaign!.cities["02"]!.supplied=true
        for index in 1...5 {
            let squadID="fixture-overstaffed-\(index)"
            recallWorld.campaign!.squads[squadID] = .init(id:squadID,kind:"infantry",survivors:10,
                                                           cityID:"02",gearOrigin:"fixture")
        }
        let frontOfficer=recallWorld.agents.keys.sorted().first{$0 != recallWorld.prefect}!
        recallWorld.campaign!.garrisonHeroByCity=["02":frontOfficer]
        recallWorld.lots["fixture-recall-rations"] = .init(id:"fixture-recall-rations",origin:"fixture",
            location:LifeWarContract.warehouse("02"),resource:.rations,amount:60_000)
        recallWorld.initial["rations",default:0]+=60_000
        var recall=try LifeRuntime(catalog:catalog,world:recallWorld)
        let beforeRecallCount=recall.world.campaign!.soldierCount
        let beforeFrontRations=recall.world.amount(.rations,at:LifeWarContract.warehouse("02"))
        try recall.advance(to:300)
        guard let recallTrip=recall.world.campaign?.transfer else {
            throw LifeError.invalid("CORE LOOP FAILED: no physical recall of an overstaffed frontier")
        }
        try check(recallTrip.sourceCityID=="02" && recallTrip.targetCityID=="00" &&
                  recall.world.campaign?.squads[recallTrip.squadID]?.survivors==10 &&
                  recall.world.campaign?.squads[recallTrip.squadID]?.cityID=="02" &&
                  recall.world.campaign?.squads[recallTrip.squadID]?.transferID==recallTrip.id &&
                  recall.world.campaign?.soldierCount==beforeRecallCount &&
                  beforeFrontRations-recall.world.amount(.rations,at:LifeWarContract.warehouse("02"))==2_000,
                  "overstaffed frontier recalls ten real soldiers only after local marching rations are paid")
        let recalledReload=try LifeSaveStore.decode(LifeSaveStore.encode(recall.world))
        try check(recalledReload.campaign?.transfer==recallTrip &&
                  recalledReload.campaign?.squads[recallTrip.squadID]?.cityID=="02",
                  "mid-route frontier recall survives save/reload without crediting the capital early")
        try recall.advance(to:recallTrip.dueSim)
        try check(recall.world.campaign?.squads[recallTrip.squadID]?.cityID=="00" &&
                  recall.world.campaign?.squads[recallTrip.squadID]?.transferID==nil &&
                  recall.world.campaign?.soldierCount==beforeRecallCount,
                  "recalled frontier soldiers become available only after their timed return")
        var replacementWorld=stationedReload
        replacementWorld.campaign!.paused=true
        replacementWorld.campaign!.training=nil
        replacementWorld.campaign!.mission=nil
        for squadID in replacementWorld.campaign!.squads.keys {replacementWorld.campaign!.squads[squadID]!.missionID=nil}
        replacementWorld.campaign!.garrisonHeroByCity?["01"]=nil
        replacementWorld.campaign!.returningGarrisonHeroes=[transfer.workerID:replacementWorld.time+1_200]
        replacementWorld.campaign!.reservedHeroIDs.removeAll{$0==transfer.workerID}
        replacementWorld.lots["fixture-replacement-rations"] = .init(id:"fixture-replacement-rations",origin:"fixture",
            location:LifeWarContract.warehouse("01"),resource:.rations,amount:6_000)
        replacementWorld.initial["rations",default:0]+=6_000
        var replacement=try LifeRuntime(catalog:catalog,world:replacementWorld)
        let beforeReplacementRations=replacement.world.amount(.rations,at:"warehouse")
        try replacement.advance(to:replacement.world.time+30)
        guard let officerTrip=replacement.world.campaign?.transfer else {
            throw LifeError.invalid("CORE LOOP FAILED: no replacement officer dispatched to existing frontier squad")
        }
        try check(officerTrip.officerOnly==true && officerTrip.squadID.isEmpty &&
                  replacement.world.campaign?.squads[transfer.squadID]?.cityID=="01" &&
                  beforeReplacementRations-replacement.world.amount(.rations,at:"warehouse")==2_000,
                  "an already manned border gets a ration-paid replacement officer without a phantom squad")
        let officerTripReload=try LifeSaveStore.decode(LifeSaveStore.encode(replacement.world))
        try check(officerTripReload.campaign?.transfer?.officerOnly==true &&
                  officerTripReload.warAwayHeroIDs.contains(officerTrip.workerID),
                  "officer-only travel survives reload while the hero stays away from capital duty")
        try replacement.advance(to:officerTrip.dueSim)
        try check(replacement.world.campaign?.garrisonHeroByCity?["01"]==officerTrip.workerID &&
                  replacement.world.campaign?.squads[transfer.squadID]?.cityID=="01",
                  "replacement defense begins only after the real officer reaches the border")
        var mixedCargoWorld=garrisonWorld
        mixedCargoWorld.campaign!.paused=true
        mixedCargoWorld.campaign!.squads["guard-a"]!.cityID="01"
        mixedCargoWorld.campaign!.unlocked.insert("stone_transport")
        mixedCargoWorld.lots["fixture-mixed-front-rations"] = .init(id:"fixture-mixed-front-rations",origin:"fixture",
            location:LifeWarContract.warehouse("01"),resource:.rations,amount:8_000)
        mixedCargoWorld.lots["fixture-mixed-home-rations"] = .init(id:"fixture-mixed-home-rations",origin:"fixture",
            location:"warehouse",resource:.rations,amount:20_000)
        mixedCargoWorld.initial["rations",default:0]+=28_000
        var mixedCargo=try LifeRuntime(catalog:catalog,world:mixedCargoWorld)
        try mixedCargo.advance(to:300)
        let frontWarehouse=LifeWarContract.warehouse("01")
        try check(mixedCargo.world.tasks.values.contains{$0.kind=="haul" && $0.target==frontWarehouse &&
                  $0.subject.hasPrefix("war-facility:") && $0.resource != .rations},
                  "a genuine construction-material shipment can reserve volume in the frontier warehouse")
        var dryFront=mixedCargo.world
        dryFront.lots["fixture-mixed-front-rations"]=nil
        dryFront.consumed["rations",default:0]+=8_000
        try dryFront.validate()
        try check(dryFront.storages[frontWarehouse]!.incoming>0 &&
                  dryFront.inFlight(.rations,to:frontWarehouse)==0 &&
                  dryFront.inFlight(.wood,to:frontWarehouse)+dryFront.inFlight(.stone,to:frontWarehouse)>0 &&
                  8_000-dryFront.amount(.rations,at:frontWarehouse)-dryFront.inFlight(.rations,to:frontWarehouse)==8_000,
                  "wood or stone in transit cannot masquerade as incoming frontier rations")
        var upkeepWorld=garrison.world
        upkeepWorld.campaign!.paused=true
        upkeepWorld.campaign!.nextRaidUTC=200_000
        upkeepWorld.lots["fixture-local-rations"] = .init(id:"fixture-local-rations",origin:"fixture",location:LifeWarContract.warehouse("01"),resource:.rations,amount:6_000)
        upkeepWorld.lots["fixture-home-rations"] = .init(id:"fixture-home-rations",origin:"fixture",location:"warehouse",resource:.rations,amount:10_000)
        upkeepWorld.initial["rations",default:0]+=16_000
        var upkeep=try LifeRuntime(catalog:catalog,world:upkeepWorld)
        let beforeLocal=upkeep.world.amount(.rations,at:LifeWarContract.warehouse("01"))
        let beforeHome=upkeep.world.amount(.rations,at:"warehouse")
        upkeep.advanceWarClock(realUTC:86_400)
        try check(beforeLocal-upkeep.world.amount(.rations,at:LifeWarContract.warehouse("01"))==6_000 &&
                  beforeHome-upkeep.world.amount(.rations,at:"warehouse")==5_000 &&
                  upkeep.world.campaign?.squads[transfer.squadID]?.survivors==10 &&
                  upkeep.world.campaign?.garrisonHeroByCity?["01"]==transfer.workerID,
                  "capital soldiers consume five rations, border soldiers five and the real officer one")
        var cutWorld=upkeep.world
        cutWorld.campaign!.cities["01"]!.points["outer"]="enemy"
        var cutGarrison=try LifeRuntime(catalog:catalog,world:cutWorld)
        cutGarrison.advanceWarClock(realUTC:86_401)
        let officerDue=cutGarrison.world.campaign?.returningGarrisonHeroes?[transfer.workerID]
        try check(cutGarrison.world.campaign?.garrisonHeroByCity?["01"]==nil &&
                  officerDue != nil && cutGarrison.world.warAwayHeroIDs.contains(transfer.workerID),
                  "a severed border starts a timed officer withdrawal without teleporting home")
        try cutGarrison.advance(to:officerDue!)
        try check(!cutGarrison.world.warAwayHeroIDs.contains(transfer.workerID) &&
                  cutGarrison.world.agents[transfer.workerID]?.node=="gate",
                  "the evacuated officer returns to the capital only after travel completes")
        var sickWorld=upkeep.world
        sickWorld.heroTown!.health!.conditions[transfer.workerID] = .overwork(
            heroID:transfer.workerID,time:sickWorld.time,cycle:sickWorld.cycle,duty:1_800,rest:0)
        var sickGarrison=try LifeRuntime(catalog:catalog,world:sickWorld)
        sickGarrison.advanceWarClock(realUTC:86_401)
        try check(sickGarrison.world.campaign?.garrisonHeroByCity?["01"]==nil &&
                  sickGarrison.world.campaign?.returningGarrisonHeroes?[transfer.workerID] != nil &&
                  sickGarrison.world.warAwayHeroIDs.contains(transfer.workerID),
                  "an ill border officer withdraws for treatment without teleporting to capital duty")
        var damaged=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true,rngSeed:11)
        try damaged.enableWar(realUTC:0)
        var damageWorld=damaged.world
        damageWorld.projects["repair"]!.completed=true
        damageWorld.projects["repair"]!.phase=4
        damageWorld.projects["repair"]!.completedWork=damageWorld.projects["repair"]!.totalWork
        damageWorld.projects["repair"]!.allocatedWork=0
        let workshopIndex=damageWorld.heroTown!.city.plots.firstIndex{$0.id=="workshop-1"}!
        damageWorld.heroTown!.city.plots[workshopIndex].level=1
        damageWorld.heroTown!.city.plots[workshopIndex].capacity=1
        damageWorld.heroTown!.city.plots[workshopIndex].service=10_000
        damageWorld.buildings["workshop"]=1
        damaged=try LifeRuntime(catalog:catalog,world:damageWorld)
        damaged.advanceWarClock(realUTC:2_700)
        try check(damaged.world.heroTown?.city.plot("workshop-1")?.service==0,
                  "a lost capital raid disables one nonessential production building")
        try damaged.advance(to:30)
        try check(damaged.world.projects["raid-repair.1.workshop-1"]?.materials == ["wood":3_000,"stone":1_500,"tools":250] &&
                  damaged.world.projects["raid-repair.1.workshop-1"]?.totalWork==600,
                  "the governor quotes an actual one-quarter material and labor repair")
        try damaged.advance(to:5_000)
        try check(damaged.world.projects["raid-repair.1.workshop-1"]?.completed==true &&
                  damaged.world.heroTown?.city.plot("workshop-1")?.service==10_000,
                  "the damaged workshop returns only after its four real repair stages finish")
        var city=war.cities["01"]!
        city.owner="player";city.supplied=true
        war.cities["01"]=city
        try check(LifeWarContract.lootBatchLimit(resource:.stone,city:city,war:war)==4_000,
                  "capturing Qing Shi does not grant a free transport upgrade")
        war.builtFacilities=["stone_transport"]
        try check(LifeWarContract.lootBatchLimit(resource:.stone,city:city,war:war)==6_000 &&
                  LifeWarContract.lootBatchLimit(resource:.wood,city:city,war:war)==4_000,
                  "the built facility upgrades only Qing Shi stone loads")
        city.owner="enemy"
        war.cities["01"]=city
        try check(LifeWarContract.lootBatchLimit(resource:.stone,city:city,war:war)==4_000,
                  "losing the production city suspends its local facility effect")

        for id in ["02","07","09","10"] {
            war.cities[id]!.owner="player"
            war.cities[id]!.supplied=true
        }
        war.builtFacilities=(war.builtFacilities ?? []).union(["frontier_granary","river_supply","long_range_scouting","frontier_transfer"])
        try check(LifeWarContract.frontRationCapacity("02",in:war)==32_000 &&
                  LifeWarContract.frontRationCapacity("01",in:war)==8_000,
                  "the built Feng Gu granary alone raises its finite automatic ration target")
        try check(LifeWarContract.lootBatchLimit(resource:.rations,city:war.cities["07"]!,war:war)==8_000 &&
                  LifeWarContract.scoutingSeconds(in:war)==300 &&
                  LifeWarContract.transportSeconds(from:"10",edges:2,resource:.rations,in:war)==960,
                  "river logistics, scouting, and transfer bonuses require built and supplied facilities")
        war.cities["09"]!.supplied=false
        try check(LifeWarContract.scoutingSeconds(in:war)==600,
                  "a severed city suspends its scouting facility without deleting the permit")

        var transferFreight=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true,rngSeed:4)
        try transferFreight.enableWar(realUTC:0)
        var transferFreightWorld=transferFreight.world
        transferFreightWorld.campaign!.paused=true
        for cityID in ["01","03","08","10"] {
            transferFreightWorld.campaign!.cities[cityID]!.owner="player"
            transferFreightWorld.campaign!.cities[cityID]!.points=Dictionary(uniqueKeysWithValues:LifeWarContract.pointKinds.map{($0,"player")})
            transferFreightWorld.campaign!.cities[cityID]!.supplied=true
        }
        transferFreightWorld.campaign!.unlocked.insert("frontier_transfer")
        transferFreightWorld.campaign!.builtFacilities=["frontier_transfer"]
        transferFreightWorld.campaign!.squads["east-guard"] = .init(id:"east-guard",kind:"infantry",survivors:10,cityID:"10",gearOrigin:"fixture")
        transferFreightWorld.lots["fixture-east-rations"] = .init(id:"fixture-east-rations",origin:"fixture",location:"warehouse",resource:.rations,amount:20_000)
        transferFreightWorld.initial["rations",default:0]+=20_000
        transferFreight=try LifeRuntime(catalog:catalog,world:transferFreightWorld)
        try transferFreight.advance(to:1_000)
        let eastHaul=transferFreight.world.tasks.values.first{$0.kind=="haul" && $0.target==LifeWarContract.warehouse("10")}
        try check(eastHaul?.steps.first(where:{$0.kind=="carry"})?.seconds==1_920 &&
                  transferFreight.world.amount(.rations,at:LifeWarContract.warehouse("10"))==0,
                  "the built East Capital depot shortens an actual four-edge ration delivery")
        let eastReload=try LifeSaveStore.decode(LifeSaveStore.encode(transferFreight.world))
        transferFreight=try LifeRuntime(catalog:catalog,world:eastReload)
        try transferFreight.advance(to:3_300)
        try check(transferFreight.world.amount(.rations,at:LifeWarContract.warehouse("10"))>=4_000,
                  "the multi-day courier survives reload and unloads real rations before the garrison can use them")

        var freight=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true,rngSeed:3)
        try freight.enableWar(realUTC:0)
        var freightWorld=freight.world
        freightWorld.campaign!.paused=true
        freightWorld.campaign!.cities["02"]!.owner="player"
        freightWorld.campaign!.cities["02"]!.points=Dictionary(uniqueKeysWithValues:LifeWarContract.pointKinds.map{($0,"player")})
        freightWorld.campaign!.cities["02"]!.supplied=true
        freightWorld.campaign!.unlocked.insert("frontier_granary")
        freightWorld.campaign!.builtFacilities=["frontier_granary"]
        freightWorld.lots["fixture-front-rations"] = .init(id:"fixture-front-rations",origin:"fixture",location:"warehouse",resource:.rations,amount:20_000)
        freightWorld.initial["rations",default:0]+=20_000
        freight=try LifeRuntime(catalog:catalog,world:freightWorld)
        try freight.advance(to:4_000)
        try check(freight.world.amount(.rations,at:LifeWarContract.warehouse("02"))>0 &&
                  freight.world.initial["rations",default:0]+freight.world.produced["rations",default:0]-freight.world.consumed["rations",default:0]==freight.world.amount(.rations),
                  "a real porter delivers conserved rations to the built frontier granary")

        var mine=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true,rngSeed:5)
        try mine.enableWar(realUTC:0)
        var mineWorld=mine.world
        for id in ["01","03"] {
            mineWorld.campaign!.cities[id]!.owner="player"
            mineWorld.campaign!.cities[id]!.points=Dictionary(uniqueKeysWithValues:LifeWarContract.pointKinds.map{($0,"player")})
            mineWorld.campaign!.cities[id]!.supplied=true
        }
        mineWorld.campaign!.paused=true
        mineWorld.campaign!.unlocked.insert("rare_ore_mine")
        mineWorld.buildings["workshop"]=1
        mineWorld.lots["fixture-mine-rations"] = .init(id:"fixture-mine-rations",origin:"fixture",location:"warehouse",resource:.rations,amount:4_000)
        mineWorld.initial["rations",default:0]+=4_000
        mine=try LifeRuntime(catalog:catalog,world:mineWorld)
        try mine.advance(to:4_000)
        try check(mine.world.produced["rare_ore",default:0]>=1_000 &&
                  mine.world.consumed["rations",default:0]>=1_000 &&
                  mine.world.amount(.rare_ore,at:"warehouse")==0 &&
                  mine.world.campaign?.mission==nil,
                  "paused offensives still allow ration-paid regional mining without starting a new attack")

        var iron=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true,rngSeed:4)
        try iron.enableWar(realUTC:0)
        var ironWorld=iron.world
        for id in ["01","03","08"] {
            ironWorld.campaign!.cities[id]!.owner="player"
            ironWorld.campaign!.cities[id]!.points=Dictionary(uniqueKeysWithValues:LifeWarContract.pointKinds.map{($0,"player")})
            ironWorld.campaign!.cities[id]!.supplied=true
        }
        ironWorld.campaign!.paused=true
        ironWorld.campaign!.unlocked.formUnion(["rare_ore_mine","refined_iron_forge"])
        ironWorld.campaign!.builtFacilities=["refined_iron_forge"]
        ironWorld.campaign!.siegeEquipment=true
        ironWorld.buildings["workshop"]=1
        ironWorld.lots["fixture-rare-ore"] = .init(id:"fixture-rare-ore",origin:"fixture",location:"warehouse",resource:.rare_ore,amount:2_000)
        ironWorld.initial["rare_ore",default:0]+=2_000
        iron=try LifeRuntime(catalog:catalog,world:ironWorld)
        try iron.advance(to:2_400)
        try check(iron.world.produced["refined_iron",default:0]>=1_000 &&
                  iron.world.consumed["rare_ore",default:0]>=2_000 &&
                  iron.world.consumed["wood",default:0]>=1_000,
                  "the Red Town forge consumes transported ore and wood before producing conserved refined iron")
        try iron.advance(to:3_600)
        try check(iron.world.campaign?.refinedSiegeEquipment==true &&
                  iron.world.consumed["refined_iron",default:0]>=1_000,
                  "the advanced siege upgrade needs a built forge and consumes real refined iron")

        var reporting=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true,rngSeed:6)
        try reporting.enableWar(realUTC:0)
        reporting.advanceWarClock(realUTC:2_700)
        let raidReports=reporting.world.campaign?.reports ?? []
        try check(raidReports.count==1 && raidReports[0].id=="raid:1" &&
                  raidReports[0].attack>raidReports[0].defense &&
                  LifeSaveStore.decode(LifeSaveStore.encode(reporting.world)).campaign?.reports==raidReports,
                  "the raid formula, real losses and report survive a save/load round trip")
        reporting.advanceWarClock(realUTC:2_700)
        try check(reporting.world.campaign?.reports?.count==1,
                  "the same accepted wall-clock input cannot duplicate a raid report")

        var auditWorld=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true,rngSeed:2).world
        var disconnected=LifeWarState(startedUTC:0)
        disconnected.paused=true
        for id in disconnected.cities.keys where id != "00" && id != "10" {
            disconnected.cities[id]!.owner="player"
            disconnected.cities[id]!.points=Dictionary(uniqueKeysWithValues:LifeWarContract.pointKinds.map{($0,"player")})
        }
        auditWorld.campaign=disconnected
        var audit=try LifeRuntime(catalog:catalog,world:auditWorld)
        audit.advanceWarClock(realUTC:0)
        try check(audit.world.campaign?.cities["07"]?.supplied==false && audit.world.campaign?.won==false,
                  "an occupied river city without a held land route or built ship is not supplied or a victory")
        auditWorld=audit.world
        auditWorld.campaign!.cities["10"]!.owner="player"
        auditWorld.campaign!.cities["10"]!.points=Dictionary(uniqueKeysWithValues:LifeWarContract.pointKinds.map{($0,"player")})
        auditWorld.campaign!.cities["01"]!.points["supply"]="enemy"
        audit=try LifeRuntime(catalog:catalog,world:auditWorld)
        audit.advanceWarClock(realUTC:0)
        try check(audit.world.campaign?.capturedEnemyCities==11 && audit.world.campaign?.won==false,
                  "eleven held city cores are not victory while even one inner border point is contested")
        auditWorld=audit.world
        auditWorld.campaign!.cities["01"]!.points["supply"]="player"
        audit=try LifeRuntime(catalog:catalog,world:auditWorld)
        audit.advanceWarClock(realUTC:0)
        try check(audit.world.campaign?.won==true && audit.world.campaign?.cities.values.allSatisfy(\.supplied)==true &&
                  audit.world.campaign?.waitReason.contains("天下统一")==true,
                  "unification is recorded only after all eleven cities have a held supply route")
        try check(try LifeSaveStore.decode(LifeSaveStore.encode(audit.world)).campaign?.won==true,
                  "the supply-audited victory survives a save/load round trip")
        print("Core loop: \(passed)/\(passed) checks passed.")
    }
}
