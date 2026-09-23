import Foundation

extension LifeRuntime {
    func healthCondition(_ heroID:String) -> LifeHealthCondition? {
        world.heroTown?.health?.conditions[heroID]
    }

    func healthWorkModifier(_ heroID:String) -> Int {
        healthCondition(heroID)?.workModifierBP ?? 0
    }

    func healthAllows(heroID:String,job:String) -> Bool {
        guard let condition=healthCondition(heroID) else{return true}
        return !condition.blockedJobs.contains(job)
    }

    func physicianWorkRate(_ agent:LifeAgent) -> Int {
        guard let hero=catalog.hero(agent.id) else{return 10000}
        let ability=LifeHealthContract.physicianWeights.reduce(0){$0+hero.attributes[$1.key,default:50]*$1.value}/10000
        let personal=min(1000,max(0,ability-50)*20)
        let xp=agent.workSeconds["physician",default:0]/300
        let levelBonus=[60,180,360,600].filter{xp>=Int64($0)}.count*100
        return min(14000,max(8000,10000+personal+levelBonus))
    }

    mutating func evaluateHealthCycle() {
        guard world.isFormalHeroTown,var formal=world.heroTown else{return}
        var health=formal.health ?? .initial()
        guard health.lastEvaluatedCycle<world.cycle else{return}
        let previous=world.cycle-1
        health.lastEvaluatedCycle=world.cycle
        guard previous>=0 else{formal.health=health;world.heroTown=formal;return}
        for heroID in world.agents.keys.sorted() {
            guard let agent=world.agents[heroID],health.conditions[heroID]==nil else{continue}
            let duty=agent.busyCycle==previous ? agent.serviceSeconds:0
            let rest:Int64
            if let start=agent.restStart {rest=min(2880,max(0,world.time-start))}
            else {rest=agent.restedCycle>=previous ? 600:0}
            let strained=duty>=1800 && rest<360
            health.overworkStreak[heroID]=strained ? health.overworkStreak[heroID,default:0]+1:0
            if health.overworkStreak[heroID,default:0]>=2,health.lastConditionCycle != world.cycle {
                health.conditions[heroID] = .overwork(heroID:heroID,time:world.time,cycle:world.cycle,duty:duty,rest:rest)
                health.firstIncidentSeen=true
                health.homeRecoveryProgress[heroID]=0;health.homeRecoveryLastAt[heroID]=world.time
                health.lastConditionCycle=world.cycle
                health.overworkStreak[heroID]=0
                world.record("health","\(agent.name)连续劳作且休息不足，出现过劳劳损，太守已安排休养。")
            }
        }
        formal.health=health;world.heroTown=formal
    }

    mutating func maybeTriggerHealthCondition(after task:LifeTask) {
        guard world.isFormalHeroTown,LifeHealthContract.hazardousJobs.contains(task.job),
              var formal=world.heroTown,var health=formal.health,
              health.conditions[task.worker]==nil,health.lastConditionCycle != world.cycle,
              let agent=world.agents[task.worker],agent.busyCycle==world.cycle,
              agent.serviceSeconds>=1800,world.happiness<50 else{return}
        health.conditions[task.worker] = .injury(heroID:task.worker,time:world.time,cycle:world.cycle,duty:agent.serviceSeconds,happiness:world.happiness,job:task.job)
        health.firstIncidentSeen=true
        health.homeRecoveryProgress[task.worker]=0;health.homeRecoveryLastAt[task.worker]=world.time
        health.lastConditionCycle=world.cycle
        formal.health=health;world.heroTown=formal
        world.record("health","\(agent.name)在劳累状态下完成高负荷工作，出现轻微工伤，暂停危险岗位。")
    }

    mutating func recoverHealthAtHome() {
        guard world.isFormalHeroTown,var formal=world.heroTown,var health=formal.health else{return}
        var recovered:[String]=[]
        for heroID in health.conditions.keys.sorted() where health.treatments[heroID]==nil {
            guard let condition=health.conditions[heroID],let agent=world.agents[heroID] else{continue}
            let previous=health.homeRecoveryLastAt[heroID] ?? condition.startedAt
            let elapsed=max(0,world.time-previous)
            let task=agent.taskID.flatMap{world.tasks[$0]}
            let restingAtHome=agent.node==agent.home && (task==nil || ["eat","home","meal_trip"].contains(task!.kind))
            if restingAtHome {health.homeRecoveryProgress[heroID,default:0]+=elapsed}
            else {health.homeRecoveryProgress[heroID]=0}
            health.homeRecoveryLastAt[heroID]=world.time
            if health.homeRecoveryProgress[heroID,default:0]>=condition.homeRecoverySeconds {recovered.append(heroID)}
        }
        for heroID in recovered {
            health.conditions[heroID]=nil;health.overworkStreak[heroID]=0
            health.homeRecoveryProgress[heroID]=nil;health.homeRecoveryLastAt[heroID]=nil
            world.record("health","\(world.agents[heroID]?.name ?? heroID)在家充分休养，身体已经恢复。")
        }
        formal.health=health;world.heroTown=formal
    }

    mutating func planHealth() {
        guard world.isFormalHeroTown,var formal=world.heroTown,var health=formal.health else{return}
        recoverHealthAtHome()
        formal=world.heroTown!;health=formal.health!
        guard health.clinicLevel>0 else{return}

        // Reserve only real clinic beds. A patient is not sent away from home until
        // another healthy, currently available resident can actually diagnose them.
        let beds=LifeHealthContract.clinicBeds[health.clinicLevel-1]
        var admissionSlots=max(0,world.agents.values.filter{$0.taskID==nil && health.conditions[$0.id]==nil && $0.job != "prefect"}.count-2)
        let queue=health.conditions.values.sorted { a,b in
            let pa=a.kind=="minor_work_injury" ? 0:1,pb=b.kind=="minor_work_injury" ? 0:1
            if pa != pb {return pa<pb}
            return a.startedAt==b.startedAt ? a.heroID<b.heroID:a.startedAt<b.startedAt
        }.map(\.heroID)
        for heroID in queue where health.treatments[heroID]==nil && health.treatments.count<beds && admissionSlots>0 {
            guard let patient=world.agents[heroID],patient.taskID==nil else{continue}
            let doctors=Set(world.agents.values.filter{$0.id != heroID && $0.taskID==nil && health.conditions[$0.id]==nil && $0.job != "prefect"}.map(\.id))
            guard !doctors.isEmpty else{continue}
            if patient.node=="clinic" {
                health.treatments[heroID] = .init(patientHeroID:heroID,phase:"waiting_doctor")
                admissionSlots-=1
            } else if let task=assign(kind:"clinic_arrive",job:"patient",subject:heroID,at:"clinic",work:0,tail:[.init(kind:"arrive",seconds:1)],only:heroID) {
                health.treatments[heroID] = .init(patientHeroID:heroID,phase:"arriving",patientTaskID:task)
                admissionSlots-=1
            }
        }
        formal.health=health;world.heroTown=formal

        for heroID in (world.heroTown?.health?.treatments.keys.sorted() ?? []) {startTreatmentPhase(heroID)}
    }

    private mutating func createPatientTask(_ heroID:String,kind:String,seconds:Int64)->String? {
        guard seconds>0,var agent=world.agents[heroID],agent.taskID==nil else{return nil}
        let id=world.next("task")
        world.tasks[id] = .init(id:id,worker:heroID,kind:kind,job:"patient",subject:heroID,
                                steps:[.init(kind:"rest",seconds:seconds)],started:world.time,due:world.time+seconds,rate:10000)
        agent.taskID=id;agent.restStart=world.time;world.agents[heroID]=agent
        return id
    }

    private mutating func startTreatmentPhase(_ heroID:String) {
        guard var formal=world.heroTown,var health=formal.health,var treatment=health.treatments[heroID],
              let condition=health.conditions[heroID] else{return}
        if treatment.phase=="arriving" {return}
        if treatment.phase=="waiting_doctor" {
            let doctors=world.agents.values.filter{$0.id != heroID && $0.taskID==nil && health.conditions[$0.id]==nil && $0.job != "prefect"}
                .sorted{a,b in let ra=physicianWorkRate(a),rb=physicianWorkRate(b);return ra==rb ? a.id<b.id:ra>rb}
            guard doctors.count>2,let doctor=doctors.first else{return}
            let eligible:Set<String>=[doctor.id]
            let work:Int64=condition.kind=="minor_work_injury" ? 180:120
            let taskKind=condition.kind=="minor_work_injury" ? "clinic_prepare":"clinic_consult"
            guard world.agents[heroID]?.taskID==nil,
                  let doctorTask=assign(kind:taskKind,job:"physician",subject:heroID,at:"clinic",work:work,eligible:eligible),
                  let doctorID=world.tasks[doctorTask]?.worker else{return}
            let duration=world.tasks[doctorTask]!.steps.reduce(Int64(0)){$0+$1.seconds}
            let patientSeconds=condition.kind=="minor_work_injury" ? duration:600
            guard let patientTask=createPatientTask(heroID,kind:condition.kind=="minor_work_injury" ? "clinic_patient_wait":"clinic_rest",seconds:patientSeconds) else{return}
            treatment.doctorHeroID=doctorID;treatment.doctorTaskID=doctorTask;treatment.patientTaskID=patientTask
            treatment.phase=condition.kind=="minor_work_injury" ? "preparing":"treating"
            treatment.doctorDone=false;treatment.patientDone=false
            health.treatments[heroID]=treatment;formal.health=health;world.heroTown=formal
            return
        }
        if treatment.phase=="rest_ready",world.agents[heroID]?.taskID==nil {
            guard let patientTask=createPatientTask(heroID,kind:"clinic_rest",seconds:900) else{return}
            treatment.patientTaskID=patientTask;treatment.patientDone=false;treatment.phase="resting"
            health.treatments[heroID]=treatment;formal.health=health;world.heroTown=formal
            return
        }
        if treatment.phase=="finish_ready",world.agents[heroID]?.taskID==nil {
            let doctors=world.agents.values.filter{$0.id != heroID && $0.taskID==nil && health.conditions[$0.id]==nil && $0.job != "prefect"}
                .sorted{a,b in let ra=physicianWorkRate(a),rb=physicianWorkRate(b);return ra==rb ? a.id<b.id:ra>rb}
            guard doctors.count>2,let doctor=doctors.first else{return}
            let eligible:Set<String>=[doctor.id]
            guard let doctorTask=assign(kind:"clinic_finish",job:"physician",subject:heroID,at:"clinic",work:60,eligible:eligible),
                  let doctorID=world.tasks[doctorTask]?.worker else{return}
            let duration=world.tasks[doctorTask]!.steps.reduce(Int64(0)){$0+$1.seconds}
            guard let patientTask=createPatientTask(heroID,kind:"clinic_patient_wait",seconds:duration) else{return}
            treatment.doctorHeroID=doctorID;treatment.doctorTaskID=doctorTask;treatment.patientTaskID=patientTask
            treatment.doctorDone=false;treatment.patientDone=false;treatment.phase="finishing"
            health.treatments[heroID]=treatment;formal.health=health;world.heroTown=formal
        }
    }

    mutating func finishHealthTask(_ task:LifeTask) {
        guard var formal=world.heroTown,var health=formal.health else{return}
        let heroID=task.subject
        guard var treatment=health.treatments[heroID] else{return}
        if task.kind=="clinic_arrive" {
            treatment.patientTaskID=nil;treatment.phase="waiting_doctor"
        } else if ["clinic_consult","clinic_prepare","clinic_finish"].contains(task.kind) {
            treatment.doctorTaskID=nil;treatment.doctorDone=true
        } else if ["clinic_rest","clinic_patient_wait"].contains(task.kind) {
            treatment.patientTaskID=nil;treatment.patientDone=true
        }

        var completed=false
        switch treatment.phase {
        case "preparing" where treatment.doctorDone && treatment.patientDone:
            treatment.phase="rest_ready";treatment.doctorDone=false;treatment.patientDone=false
        case "treating" where treatment.doctorDone && treatment.patientDone:completed=true
        case "resting" where treatment.patientDone:
            treatment.phase="finish_ready";treatment.patientDone=false
        case "finishing" where treatment.doctorDone && treatment.patientDone:completed=true
        default:break
        }
        if completed {
            health.conditions[heroID]=nil;health.treatments[heroID]=nil;health.overworkStreak[heroID]=0
            health.homeRecoveryProgress[heroID]=nil;health.homeRecoveryLastAt[heroID]=nil
            world.record("health","\(world.agents[heroID]?.name ?? heroID)完成医舍治疗，已经恢复正常城务。")
        } else {health.treatments[heroID]=treatment}
        formal.health=health;world.heroTown=formal
    }

    @discardableResult mutating func planClinicConstruction() -> Bool {
        guard world.isFormalHeroTown,var formal=world.heroTown,var health=formal.health,
              !world.projects.values.contains(where:{!$0.completed}) else{return false}
        let level=health.clinicLevel
        let stable=formal.city.qualifiedWindows["clinic.stable",default:0]>=2
        let firstNeeded = health.firstIncidentSeen || !health.conditions.isEmpty
        var target:Int?
        if level==0,firstNeeded || (world.agents.count>=20 && stable) {target=1}
        else if level>0,level<3,health.clinicDemandWindows>=2 {target=level+1}
        guard let target else{return false}
        let multiplier:Int64=[1,2,4][target-1]
        startProject(id:"clinic.L\(target)",kind:"clinic",node:"clinic",cash:0,
                     work:LifeHealthContract.clinicWork*multiplier,
                     materials:LifeHealthContract.clinicMaterials.mapValues{$0*multiplier},
                     targetLevel:target,beneficiaryDemandID:firstNeeded ? "health.condition":"health.population.\(world.agents.count)")
        formal=world.heroTown!;health=formal.health ?? health;formal.health=health;world.heroTown=formal
        return true
    }
}
