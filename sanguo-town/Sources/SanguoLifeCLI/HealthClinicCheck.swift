import Foundation
import SanguoLife

enum HealthClinicCheck {
    static func run() throws {
        var passed=0
        func check(_ condition:Bool,_ id:String,_ message:String)throws {
            guard condition else{throw LifeError.invalid("\(id) FAILED: \(message)")}
            passed+=1;print("PASS \(id) \(message)")
        }
        func make(_ seed:UInt64=81)throws->LifeRuntime {
            try .init(catalog:.bundled(),wallUTC:0,formalHeroTown:true,rngSeed:seed)
        }
        func finishRepair(_ source:LifeRuntime)throws->LifeRuntime {
            var world=source.world
            guard var repair=world.projects["repair"] else{throw LifeError.invalid("repair fixture missing")}
            repair.completedWork=repair.totalWork;repair.allocatedWork=0;repair.phase=4;repair.stageStarted=false;repair.completed=true
            world.projects[repair.id]=repair
            world.tasks=[:]
            for id in world.agents.keys {world.agents[id]!.taskID=nil}
            for id in world.lots.keys {world.lots[id]!.reserved=0}
            for id in world.storages.keys {world.storages[id]!.incoming=0}
            for id in world.fields.keys where ["sowing","watering1","watering2","harvesting"].contains(world.fields[id]!.state) {
                world.fields[id]!.state="empty";world.fields[id]!.taskID=nil;world.fields[id]!.due=nil
            }
            for id in world.stations.keys where world.stations[id]!.taskID != nil {
                world.stations[id]!.taskID=nil;world.stations[id]!.phase="idle";world.stations[id]!.recipe=nil
                world.stations[id]!.due=nil;world.stations[id]!.outputSpace=0;world.stations[id]!.foodInProcess=0
            }
            return try .init(catalog:.bundled(),world:world)
        }
        func patientFixture(_ kind:String)throws->LifeRuntime {
            var runtime=try finishRepair(make())
            var world=runtime.world
            world.heroTown!.health!.clinicLevel=1
            world.heroTown!.health!.firstIncidentSeen=true
            world.buildings["clinic"]=1
            let patient="zhangfei"
            world.heroTown!.health!.conditions[patient] = kind=="minor_work_injury"
                ? .injury(heroID:patient,time:world.time,cycle:world.cycle,duty:1800,happiness:40,job:"logger")
                : .overwork(heroID:patient,time:world.time,cycle:world.cycle,duty:1800,rest:120)
            runtime=try .init(catalog:.bundled(),world:world)
            return runtime
        }

        try check(LifeHealthContract.clinicBeds == [2,4,6],"HC01","clinic levels expose exactly 2/4/6 treatment beds")
        try check(LifeHealthContract.physicianWeights["strategy"]==6000 && LifeHealthContract.physicianWeights["administration"]==4000,
                  "HC02","physician efficiency is strategy 60% plus administration 40%")

        var construction=try finishRepair(make(82));var buildWorld=construction.world
        buildWorld.heroTown!.health!.firstIncidentSeen=true
        construction=try .init(catalog:.bundled(),world:buildWorld)
        try construction.advance(to:30)
        let clinicProject=construction.world.projects.values.first{$0.kind=="clinic" && !$0.completed}
        try check(clinicProject?.targetLevel==1 && clinicProject?.totalWork==LifeHealthContract.clinicWork && clinicProject?.materials==LifeHealthContract.clinicMaterials,
                  "HC03","first clinical incident creates the exact automatic clinic project")
        try check(clinicProject?.beneficiaryDemandID=="health.condition","HC04","clinic construction keeps an auditable demand reason")

        var population=try finishRepair(make(85));var populationWorld=population.world
        for hero in population.catalog.heroes where populationWorld.agents.count<20 && populationWorld.agents[hero.id]==nil {
            var resident=populationWorld.agents["liubei"]!
            resident.id=hero.id;resident.name=hero.name;resident.heroID=hero.id;resident.origin="recruited"
            resident.job="flex";resident.node="tavern";resident.home="tavern";resident.dining="guest-meals";resident.taskID=nil
            populationWorld.agents[hero.id]=resident;populationWorld.gacha!.stars[hero.id]=1;populationWorld.owned.append(hero.id)
            populationWorld.heroTown!.ownedHeroes[hero.id] = .init(heroID:hero.id,star:1,sourceDrawID:"fixture",arrivalState:"resident",arrivalAt:nil,bedReservation:"tavern-1.guest")
        }
        populationWorld.owned=Array(Set(populationWorld.owned)).sorted()
        populationWorld.heroTown!.city.qualifiedWindows["clinic.stable"]=2
        population=try .init(catalog:.bundled(),world:populationWorld);try population.advance(to:30)
        try check(population.world.projects.values.contains{$0.kind=="clinic" && $0.targetLevel==1 && $0.beneficiaryDemandID=="health.population.20"},
                  "HC11","twenty residents plus two stable windows also authorizes the first clinic")

        var upgrade=try finishRepair(make(86));var upgradeWorld=upgrade.world
        upgradeWorld.heroTown!.health!.clinicLevel=1;upgradeWorld.heroTown!.health!.clinicDemandWindows=2;upgradeWorld.buildings["clinic"]=1
        upgrade=try .init(catalog:.bundled(),world:upgradeWorld);try upgrade.advance(to:30)
        let levelTwo=upgrade.world.projects.values.first{$0.kind=="clinic" && $0.targetLevel==2}
        try check(levelTwo?.totalWork==LifeHealthContract.clinicWork*2 && levelTwo?.materials==LifeHealthContract.clinicMaterials.mapValues{$0*2},
                  "HC12","sustained bed demand creates a level-two project at the exact multiplier")

        var strain=try patientFixture("overwork_strain")
        var physicianTask:LifeTask?
        for target in stride(from:Int64(30),through:900,by:30) {
            try strain.advance(to:target)
            if let task=strain.world.tasks.values.first(where:{$0.job=="physician"}) {physicianTask=task;break}
        }
        let treatment=strain.world.heroTown!.health!.treatments["zhangfei"]
        try check(treatment?.doctorHeroID != nil && physicianTask?.subject=="zhangfei" && (8000...14000).contains(physicianTask?.rate ?? 0),
                  "HC05","a healthy real hero travels to the clinic and performs physician work")
        try check(strain.world.agents["zhangfei"]?.node=="clinic" && treatment != nil,"HC06","the patient physically arrives and occupies one clinic bed")
        try strain.advance(to:1800)
        try check(strain.world.heroTown!.health!.conditions["zhangfei"]==nil && strain.world.heroTown!.health!.treatments["zhangfei"]==nil,
                  "HC07","overwork treatment clears condition and bed atomically")

        var injury=try patientFixture("minor_work_injury")
        try injury.advance(to:2400)
        try check(injury.world.heroTown!.health!.conditions["zhangfei"]==nil && injury.world.records.contains(where:{$0.kind=="health" && $0.text.contains("完成医舍治疗")}),
                  "HC08","minor injury completes prepare, rest and follow-up treatment phases")

        var waitingWorld=try patientFixture("overwork_strain").world
        waitingWorld.agents["zhangfei"]!.node="clinic"
        waitingWorld.heroTown!.health!.treatments["zhangfei"] = .init(patientHeroID:"zhangfei",phase:"waiting_doctor")
        for heroID in waitingWorld.agents.keys.sorted() where heroID != "zhangfei" && heroID != waitingWorld.prefect {
            var unavailable=LifeHealthCondition.overwork(heroID:heroID,time:0,cycle:0,duty:1_800,rest:0)
            unavailable.homeRecoverySeconds=10_000
            waitingWorld.heroTown!.health!.conditions[heroID]=unavailable
        }
        var waiting=try LifeRuntime(catalog:.bundled(),world:waitingWorld)
        try waiting.advance(to:600)
        try check(waiting.world.heroTown!.health!.treatments["zhangfei"]?.phase=="waiting_doctor" &&
                  waiting.world.agents["zhangfei"]?.node=="clinic" &&
                  waiting.world.agents["zhangfei"]?.taskID==nil,
                  "HC13","a patient awaiting a healthy doctor keeps the clinic bed across the morning meal window")

        var oldPantry=waitingWorld
        oldPantry.storages["clinic-meals"]=nil
        var bedside=try LifeRuntime(catalog:.bundled(),world:oldPantry)
        try check(bedside.world.storages["clinic-meals"]?.capacity==12_000_000 &&
                  bedside.world.amount(.meal,at:"clinic-meals")==0,
                  "HC14","an older save gains an empty physical clinic meal pantry without minting food")
        var mealWorld=bedside.world
        guard let source=mealWorld.lots.values.first(where:{$0.location=="home-meals" && $0.resource == .meal && $0.amount >= 1_000}) else {
            throw LifeError.invalid("clinic meal fixture lacks founding food")
        }
        mealWorld.lots[source.id]!.amount-=1_000
        mealWorld.lots["clinic-delivery-fixture"] = .init(id:"clinic-delivery-fixture",origin:source.origin,
            location:"clinic-meals",resource:.meal,amount:1_000,quality:source.quality)
        bedside=try LifeRuntime(catalog:.bundled(),world:mealWorld)
        try bedside.advance(to:600)
        try check(bedside.world.meals.contains(where:{$0.at==600 && $0.served["zhangfei"] != nil}) &&
                  (bedside.world.lots["clinic-delivery-fixture"]?.amount ?? 0)==0 &&
                  bedside.world.agents["zhangfei"]?.node=="clinic",
                  "HC15","an admitted patient consumes the delivered clinic meal without leaving the bed")

        var home=try finishRepair(make(83));var homeWorld=home.world
        homeWorld.heroTown!.health!.firstIncidentSeen=true
        homeWorld.heroTown!.health!.conditions["zhangfei"] = .overwork(heroID:"zhangfei",time:0,cycle:0,duty:1800,rest:120)
        homeWorld.agents["zhangfei"]!.node=homeWorld.agents["zhangfei"]!.home
        homeWorld.agents["zhangfei"]!.restStart=0
        homeWorld.nextPlan=1800
        home=try .init(catalog:.bundled(),world:homeWorld)
        try home.advance(to:1800)
        try check(home.world.heroTown!.health!.conditions["zhangfei"]==nil,"HC09","without clinic or physician, continuous home rest is a non-blocking fallback")

        var legacy=try make(84).world;legacy.heroTown!.health=nil
        let migrated=try LifeRuntime(catalog:.bundled(),world:LifeSaveStore.decode(LifeSaveStore.encode(legacy)))
        try check(migrated.world.heroTown?.health != nil,"HC10","existing format-4 saves receive a non-destructive health-state migration")
        try migrated.world.validate()
        print("Health clinic runtime: \(passed)/15 checks passed.")
    }
}
