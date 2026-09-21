import Foundation

public struct LifePoint: Codable, Equatable, Sendable { public var x: Double, y: Double; public init(_ x:Double,_ y:Double){self.x=x;self.y=y} }
public struct LifeLot: Codable, Equatable, Identifiable, Sendable {
    public var id: String, origin: String, location: String
    public var resource: LifeResource
    public var amount: Int64, reserved: Int64 = 0
    public var quality: String = "basic"
}
public struct LifeStorage: Codable, Equatable, Sendable {
    public var node: String
    public var capacity: Int64 // millionths of one visible volume unit
    public var incoming: Int64 = 0
}
public struct LifeAgent: Codable, Equatable, Identifiable, Sendable {
    public var id: String, name: String, job: String, node: String, home: String, dining: String
    public var heroID: String? = nil
    public var taskID: String? = nil
    public var busyCycle: Int64 = 0, serviceSeconds: Int64 = 0
    public var restStart: Int64? = nil
    public var restedCycle: Int64 = -1
    public var workSeconds: [String:Int64] = [:]
}
public struct LifeStep: Codable, Equatable, Sendable {
    public var kind: String
    public var seconds: Int64
    public var route: [LifePoint] = []
    public var destination: String = ""
}
public struct LifeReservation: Codable, Equatable, Sendable {
    public var lotID: String
    public var amount: Int64
}
public struct LifeTask: Codable, Equatable, Identifiable, Sendable {
    public var id: String, worker: String, kind: String, job: String, subject: String
    public var steps: [LifeStep]
    public var step: Int = 0
    public var started: Int64, due: Int64
    public var rate: Int
    public var reservations: [LifeReservation] = []
    public var target: String = ""
    public var resource: LifeResource? = nil
    public var quantity: Int64 = 0
    public var space: Int64 = 0
    public var contribution: Int64 = 0
    public var current: LifeStep { steps[step] }
}
public struct LifeField: Codable, Equatable, Identifiable, Sendable {
    public var id: String, crop: String = "millet", state: String = "empty"
    public var due: Int64? = nil
    public var taskID: String? = nil
    public var cycle: Int = 0
}
public struct LifeStation: Codable, Equatable, Identifiable, Sendable {
    public var id: String, node: String, input: String, output: String, kind: String
    public var recipe: String? = nil
    public var phase: String = "idle"
    public var due: Int64? = nil
    public var taskID: String? = nil
    public var outputSpace: Int64 = 0
    public var foodInProcess: Int64 = 0
}
public struct LifeProject: Codable, Equatable, Identifiable, Sendable {
    public var id: String, kind: String, node: String
    public var materials: [String:Int64]
    public var cash: Int64, totalWork: Int64, completedWork: Int64 = 0
    public var phase: Int = 0
    public var stageStarted = false
    public var completed = false
    public var allocatedWork: Int64 = 0
}
public struct LifeMeal: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var at: Int64, deadline: Int64
    public var expected: [String]
    public var served: [String:Int] = [:]
    public var closed = false
    public var recoveryExtra: Int = 0
}
public struct LifeRecruit: Codable, Equatable, Sendable {
    public var stage = 0
    public var state = "waiting"
    public var due: Int64? = nil
    public var spent: Int64 = 0
}
public struct LifeRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String, kind: String, text: String
    public var time: Int64
}
public struct LifeWorld: Codable, Equatable, Sendable {
    public var format = 1
    public var rules = "life-0.7.2-v1"
    public var time: Int64 = 0
    public var sequence: Int64 = 1
    public var nextPlan: Int64 = 0
    public var wallUTC: Int64
    public var policy = "supply"
    public var treasury: Int64 = 600
    public var reservedCash: Int64 = 0
    public var agents: [String:LifeAgent] = [:]
    public var lots: [String:LifeLot] = [:]
    public var storages: [String:LifeStorage] = [:]
    public var tasks: [String:LifeTask] = [:]
    public var fields: [String:LifeField] = [:]
    public var stations: [String:LifeStation] = [:]
    public var projects: [String:LifeProject] = [:]
    public var buildings: [String:Int] = ["hall":1,"house":1,"farm":1,"granary":1]
    public var meals: [LifeMeal] = []
    public var records: [LifeRecord] = []
    public var produced: [String:Int64] = [:], consumed: [String:Int64] = [:], initial: [String:Int64] = [:]
    public var counters: [String:Int] = [:]
    public var discovered: [String] = ["xunyu"]
    public var recruits: [String:LifeRecruit] = [:]
    public var wish: String? = nil
    public var owned: [String] = ["xunyu"]
    public var husbandry: LifeHusbandry? = nil // Absent in v1; explicit opt-in upgrades the isolated save.
    public var prefect = "xunyu"
    public var happiness = 70
    public var foodCoverage = 10000
    public var growthEnabled = true
    public var rationTarget: Int64 = 0
    public var treeReady: [Int64] = Array(repeating:0,count:24)
    public var cleanedSites: [String] = []
    public var tradePeriod: Int64 = 0, tradedAmount: Int64 = 0
    public var housing: Int { buildings["house",default:1] * 16 }
    public var phase: Int64 { time % 2880 }
    public var cycle: Int64 { time / 2880 }
    public var isNight: Bool { phase >= 2160 }
    public init(wallUTC:Int64) { self.wallUTC=wallUTC }
    mutating func next(_ prefix:String) -> String { defer{sequence+=1};return "\(prefix)-\(sequence)" }
    mutating func record(_ kind:String,_ text:String) { let id=next("event");records.append(.init(id:id,kind:kind,text:text,time:time)); if records.count>200{records.removeFirst(records.count-200)} }
    public func amount(_ r:LifeResource,at location:String? = nil,free:Bool = false) -> Int64 {
        lots.values.filter{ $0.resource == r && (location == nil || $0.location == location) }.reduce(0){$0+$1.amount-(free ? $1.reserved : 0)}
    }
    public func volume(at location:String) -> Int64 { lots.values.filter{$0.location == location}.reduce(0){$0+$1.amount*$1.resource.volume} }
    public func foodEquivalent() -> Int64 { amount(.grain)*4 + amount(.meal) + stations.values.reduce(0){$0+$1.foodInProcess} } // military rations are deliberately excluded
    public func coverageText() -> String { foodCoverage>=9500 ? "饭食稳定" : "正在恢复饭食供应" }
}
/// Economic paths use immutable map units. Desktop size and retina scale never enter this graph.
public enum LifeMap {
    public static let places: [String:LifePoint] = [
        "hall":.init(1080,750),"home":.init(920,900),"warehouse":.init(570,610),
        "kitchen":.init(1040,570),"market":.init(860,420),"workshop":.init(1340,540),
        "tavern":.init(1050,410),"stable":.init(1550,430),"station":.init(1430,280),
        "barracks":.init(1600,700),"farm":.init(360,720),"well":.init(740,610),
        "trees":.init(200,900),"quarry":.init(390,160),"mine":.init(180,160),"gate":.init(1570,210),
        "field-0":.init(250,380),"field-1":.init(420,380),"field-2":.init(250,510),"field-3":.init(420,510),
        "seal":.init(1190,745),"ration":.init(1500,610),
        "pasture":.init(500,810),"butcher":.init(650,500)]
    public static func point(_ id:String) -> LifePoint { places[id] ?? places["hall"]! }
    public static func path(_ from:String,_ to:String) -> [LifePoint] {
        let a=point(from),b=point(to)
        if from == to {return [a]}
        let ys=[220.0,660.0,1010.0]
        let ay=ys.min{abs($0-a.y)<abs($1-a.y)}!,by=ys.min{abs($0-b.y)<abs($1-b.y)}!
        var p=[a,LifePoint(a.x,ay)]
        if ay != by {p += [.init(700,ay),.init(700,by)]}
        p += [.init(b.x,by),b]
        return p.reduce(into:[]){result,v in if result.last != v{result.append(v)}}
    }
    public static func length(_ p:[LifePoint]) -> Double { zip(p,p.dropFirst()).reduce(0){$0+hypot($1.0.x-$1.1.x,$1.0.y-$1.1.y)} }
    public static func position(_ task:LifeTask,at time:Double) -> LifePoint? {
        let step=task.current;guard !step.route.isEmpty else{return nil}
        let t=max(0,min(1,(time-Double(task.started))/Double(max(1,step.seconds))))
        var d=length(step.route)*t
        for (a,b) in zip(step.route,step.route.dropFirst()) {
            let n=hypot(b.x-a.x,b.y-a.y)
            if d<=n {let f=n>0 ? d/n:1;return .init(a.x+(b.x-a.x)*f,a.y+(b.y-a.y)*f)};d-=n
        }
        return step.route.last
    }
}
