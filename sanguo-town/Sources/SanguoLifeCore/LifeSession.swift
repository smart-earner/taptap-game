import Foundation

public protocol LifePersistence: Sendable { func save(_ state:LifeState) throws }
public struct LifeSaveStore: LifePersistence, Sendable {
    public let url:URL
    public init(url:URL) {self.url=url}
    public func load(rules:LifeRules) throws -> LifeState? {
        guard FileManager.default.fileExists(atPath:url.path) else { return nil }
        let state=try JSONDecoder().decode(LifeState.self,from:Data(contentsOf:url));try state.validate(rules);return state
    }
    public func save(_ state:LifeState) throws {
        let fm=FileManager.default
        try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let data=try encoder.encode(state)
        if fm.fileExists(atPath:url.path) {
            for index in stride(from:3,through:2,by:-1) {
                let previous=URL(fileURLWithPath:url.path+".bak\(index-1)"),next=URL(fileURLWithPath:url.path+".bak\(index)")
                if fm.fileExists(atPath:previous.path) {try Data(contentsOf:previous).write(to:next,options:.atomic)}
            }
            try Data(contentsOf:url).write(to:URL(fileURLWithPath:url.path+".bak1"),options:.atomic)
        }
        try data.write(to:url,options:.atomic)
    }
}
public actor LifeSession {
    private var state:LifeState
    private let rules:LifeRules
    private let persistence:any LifePersistence
    public init(state:LifeState,rules:LifeRules,persistence:any LifePersistence) throws {
        try state.validate(rules);self.state=state;self.rules=rules;self.persistence=persistence
    }
    public func snapshot()->LifeState {state}
    public func save() throws {try persistence.save(state)}
    public func advance(to wall:Int64) throws {
        guard wall>state.lastWallUTC else {return}
        var candidate=state;try LifeEngine.advanceWall(&candidate,to:wall,rules:rules)
        try persistence.save(candidate);state=candidate
    }
    public func chooseCrop(site:String,crop:String) throws {
        var candidate=state;try LifeEngine.changeCrop(&candidate,site:site,crop:crop,rules:rules)
        try candidate.validate(rules);try persistence.save(candidate);state=candidate
    }
}

/// Read-only, directly interpolated from an authoritative task; no looping commuter animation.
public enum LifeProjection {
    public static func position(_ agent:LifeAgent,state:LifeState,rules:LifeRules,at time:Double?=nil)->LifePoint {
        guard let task=state.tasks.first(where:{$0.id==agent.task}),["approach","loaded"].contains(task.phase) else {return rules.point(agent.site)}
        let target=task.kind=="haul" && task.phase=="approach" ? task.source:task.destination
        let path=rules.path(task.phaseFrom,target), lengths=zip(path,path.dropFirst()).map{$0.distance($1)}
        let fraction=max(0,min(1,((time ?? Double(state.time))-Double(task.began))/Double(max(1,task.due-task.began))))
        var remaining=lengths.reduce(0,+)*fraction
        for i in lengths.indices {
            if remaining<=lengths[i] { let f=lengths[i]>0 ? remaining/lengths[i]:0;return .init(x:path[i].x+(path[i+1].x-path[i].x)*f,y:path[i].y+(path[i+1].y-path[i].y)*f) }
            remaining-=lengths[i]
        }
        return path.last ?? rules.point(agent.site)
    }
    public static func light(at time:Int64,rules r:LifeRules)->Double {
        let phase=Double(time%r.clock.cycle)
        if phase<Double(r.clock.dawnEnd) {return 0.55+0.45*phase/Double(r.clock.dawnEnd)}
        if phase<Double(r.clock.dayEnd) {return 1}
        if phase<Double(r.clock.duskEnd) {return 1-0.65*(phase-Double(r.clock.dayEnd))/Double(r.clock.duskEnd-r.clock.dayEnd)}
        return 0.35
    }
    public static func title(_ agent:LifeAgent,state:LifeState,rules r:LifeRules)->String {
        guard let t=state.tasks.first(where:{$0.id==agent.task}) else {return agent.activity}
        let noun=r.resources.first{$0.id==t.key}?.name ?? r.recipe(t.key)?.name ?? t.key
        if t.kind=="haul" {return t.cargo>0 ? "搬\(t.cargo)份\(noun)":"去取\(noun)"}
        if t.kind=="recipe" && t.phase=="work" {return r.recipe(t.key)?.name ?? t.key}
        return LifeEngine.activity(t)
    }
}

/// Pure effect functions are testable in L1. Recruitment and actually applying these to the
/// existing game's officers remain L3; possession is never inferred from the catalogue.
public enum LifeHeroEffects {
    public static func baseWork(_ seconds:Int64,attribute:Int,level:Int=1)->Int64 {
        let speed=min(14000,8000+40*max(0,min(100,attribute))+50*max(0,min(9,level-1)))
        return max((seconds*70+99)/100,(seconds*10000+Int64(speed)-1)/Int64(speed))
    }
    public static func value(hero:String,effect:String,base:Int,owned:Bool,onDuty:Bool)->Int {
        guard owned,onDuty else {return base}
        switch (hero,effect) {
        case ("xunyu","satisfactionFall"):return min(base,4)
        case ("liang","craftWork"):return (base*88+99)/100
        case ("lusu","importGoods"):return (base*92+99)/100
        case ("zhaoyun","escortTravel"),("guanyu","trainingWork"):return (base*90+99)/100
        case ("zhaoyun","wounded"):return (base*80+99)/100
        case ("zhangfei","militaryCarry"):return base+2
        default:return base
        }
    }
}
