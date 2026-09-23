import Foundation

/// Persisted identity for the formal v0.9 ruleset.  Preview saves intentionally do not
/// receive this object, which keeps the two save families isolated.
public enum LifeHeroTownContract {
    public static let rules = "hero-town-0.9.0"
    public static let format = 4
    public static let layout = 6
    public static let contentHash = "94340e629722bb9cbb6a755e4e27b98bf0049289b0a389f18b07881fb522023c"
    public static let authority = "createCity.auto_manage_v09"
}

/// Published identity for the complete v0.12 city and campaign rules. The
/// content hash covers the bundled v0.9 base data, v0.10 growth and v0.11 war
/// contracts, plus the v0.12 economy and roster data, in that order. Format 7
/// deliberately skips unshipped format 5/6 plans: existing format-4 saves
/// upgrade directly and keep their original file as a rolling backup.
public enum LifeV12Contract {
    public static let rules = "hero-town-0.12.0"
    public static let format = 7
    public static let layout = 7
    public static let contentHash = "df40845afb91ba200fa7a9746837e27ced982f79182a398b5db022ef8d5791bc"
    public static let authority = "createCity.auto_manage_v12"
}

/// Small pacing adjustments that make the desktop town readable without changing
/// its resource ledger or granting materials outside the normal production chains.
public enum LifeTownPacingContract {
    public static let defaultPresentationSpeed = 2
    public static let formalResourceWorkRateBonusBP = 1500
    public static let resourceJobs: Set<String> = ["farmer", "logger", "miner"]
    public static let protectedBuilderFoodCoverageBP = 9500
}

public struct LifeOwnedHero: Codable, Equatable, Sendable {
    public var heroID: String
    public var star: Int
    public var sourceDrawID: String
    public var arrivalState: String
    public var arrivalAt: Int64?
    public var bedReservation: String
    /// Optional for old saves. A newly drawn body has one verifiable path from
    /// arrival to its first completed city or campaign contribution.
    public var firstDuty: LifeHeroFirstDuty? = nil
    public init(heroID:String,star:Int,sourceDrawID:String,arrivalState:String,arrivalAt:Int64?,bedReservation:String) {
        self.heroID=heroID;self.star=star;self.sourceDrawID=sourceDrawID;self.arrivalState=arrivalState;self.arrivalAt=arrivalAt;self.bedReservation=bedReservation
    }
}

public struct LifeHeroFirstDuty: Codable, Equatable, Sendable {
    public var taskID: String
    public var job: String
    public var destination: String
    public var assignedAt: Int64
    public var arrivedAt: Int64?
    public var effectiveAt: Int64?
    public var effect: String?
}

public struct LifeAdminLease: Codable, Equatable, Sendable {
    public var sourceHeroID: String
    public var taskID: String
    public var completedAt: Int64
    public var expiresAt: Int64
}

public struct LifeSkillSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var contentHash: String
    public var heroID: String
    public var star: Int
    public var skillIDs: [String]
    public var metric: String
    public var value: Int
    public var retainedValue: Int
    public var eventID: String
}

public struct LifePlotState: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var index: Int
    public var kind: String
    public var node: String
    public var point: LifePoint
    public var level: Int
    public var capacity: Int
    public var occupancy: Int
    public var service: Int
    public var developmentPermit: Bool
    public var identity: String
    public var built: Bool { level > 0 }

    public init(id: String,index: Int,kind: String,node: String,point: LifePoint,level: Int,capacity: Int,
                occupancy: Int,service: Int,developmentPermit: Bool,identity: String) {
        self.id=id;self.index=index;self.kind=kind;self.node=node;self.point=point;self.level=level
        self.capacity=capacity;self.occupancy=occupancy;self.service=service
        self.developmentPermit=developmentPermit;self.identity=identity
    }
}

public struct LifeMemory: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var eventID: String
    public var time: Int64
    public var kind: String
    public var heroIDs: [String]
    public var pinned: Bool
    public var rules: String
    public var layoutVersion: Int
}

public enum LifeHealthContract {
    public static let clinicPoint = LifePoint(1370,930)
    public static let clinicWork: Int64 = 2400
    public static let clinicMaterials: [String:Int64] = ["wood":12000,"stone":6000,"tools":1000]
    public static let clinicBeds = [2,4,6]
    public static let hazardousJobs: Set<String> = ["logger","miner","smith","builder"]
    public static let physicianWeights = ["strategy":6000,"administration":4000]
}

public struct LifeHealthCondition: Codable, Equatable, Sendable, Identifiable {
    public var id: String { heroID }
    public var heroID: String
    public var kind: String
    public var startedAt: Int64
    public var triggerCycle: Int64
    public var evidence: String
    public var workModifierBP: Int
    public var blockedJobs: [String]
    public var homeRecoverySeconds: Int64

    public static func overwork(heroID:String,time:Int64,cycle:Int64,duty:Int64,rest:Int64)->Self {
        .init(heroID:heroID,kind:"overwork_strain",startedAt:time,triggerCycle:cycle,
              evidence:"duty=\(duty),rest=\(rest),streak=2",workModifierBP:-1000,
              blockedJobs:["logger","miner","smith","builder"],homeRecoverySeconds:1800)
    }
    public static func injury(heroID:String,time:Int64,cycle:Int64,duty:Int64,happiness:Int,job:String)->Self {
        .init(heroID:heroID,kind:"minor_work_injury",startedAt:time,triggerCycle:cycle,
              evidence:"job=\(job),duty=\(duty),happiness=\(happiness)",workModifierBP:-2000,
              blockedJobs:["logger","miner","smith","builder","porter"],homeRecoverySeconds:2880)
    }
}

public struct LifeClinicTreatment: Codable, Equatable, Sendable, Identifiable {
    public var id: String { patientHeroID }
    public var patientHeroID: String
    public var doctorHeroID: String?
    public var phase: String
    public var doctorTaskID: String?
    public var patientTaskID: String?
    public var doctorDone: Bool = false
    public var patientDone: Bool = false
    public init(patientHeroID:String,phase:String,doctorHeroID:String?=nil,
                doctorTaskID:String?=nil,patientTaskID:String?=nil) {
        self.patientHeroID=patientHeroID;self.phase=phase;self.doctorHeroID=doctorHeroID
        self.doctorTaskID=doctorTaskID;self.patientTaskID=patientTaskID
    }
}

public struct LifeHealthState: Codable, Equatable, Sendable {
    public var clinicLevel: Int = 0
    /// Sticky demand signal: a recovered first patient must still justify the first clinic.
    public var firstIncidentSeen: Bool = false
    public var conditions: [String:LifeHealthCondition] = [:]
    public var treatments: [String:LifeClinicTreatment] = [:]
    public var overworkStreak: [String:Int] = [:]
    public var homeRecoveryProgress: [String:Int64] = [:]
    public var homeRecoveryLastAt: [String:Int64] = [:]
    public var lastEvaluatedCycle: Int64 = -1
    public var lastConditionCycle: Int64 = -1
    public var clinicDemandWindows: Int = 0
    public static func initial()->Self {.init()}
}

public struct LifeCityState: Codable, Equatable, Sendable {
    public var layoutVersion: Int
    public var plots: [LifePlotState]
    public var civics: [String:Int]
    public var landmarks: [String:Int]
    public var attachments: [String:Int]
    public var qualifiedWindows: [String:Int]
    public var economyWindows: Int
    public var nextEconomyWindow: Int64
    public var supplyRecovery: Bool
    public var lowMealStreak: Int
    public var goodMealStreak: Int
    public var memories: [LifeMemory]

    public static func initial() -> Self {
        let built: Set<Int> = [0, 1, 4, 5, 8, 16, 17]
        let definitions: [(String,String,LifePoint)] = [
            ("hall-1","hall",.init(1060,760)), ("house-1","home",.init(910,760)),
            ("house-2","home-2",.init(770,750)), ("house-3","home-3",.init(920,930)),
            ("farm-1","farm",.init(570,730)), ("granary-1","warehouse",.init(560,550)),
            ("market-1","market",.init(910,550)), ("workshop-1","workshop",.init(1370,540)),
            ("tavern-1","tavern",.init(1060,550)), ("stable-1","stable",.init(1540,470)),
            ("station-1","station",.init(1460,290)), ("barracks-1","barracks",.init(1610,740)),
            ("house-4","home-4",.init(1080,930)), ("granary-2","warehouse-2",.init(580,930)),
            ("farm-2","farm-2",.init(570,470)), ("workshop-2","workshop-2",.init(1370,790)),
            ("goldmine-1","goldmine",.init(120,290)), ("smelter-1","smelter",.init(1370,400))
        ]
        let disabled: Set<String> = ["market-1", "stable-1"]
        let plots = definitions.enumerated().map { index, item in
            let kind = item.0.split(separator: "-").dropLast().joined(separator: "-")
            let initialCapacity:[String:Int] = ["hall-1":1,"house-1":5,"farm-1":4,"granary-1":256,"tavern-1":1,"goldmine-1":1,"smelter-1":1]
            return LifePlotState(id:item.0,index:index,kind:kind,node:item.1,point:item.2,
                                 level:built.contains(index) ? 1:0,capacity:initialCapacity[item.0,default:0],occupancy:0,
                                 service:built.contains(index) ? 10000:0,
                                 developmentPermit:!disabled.contains(item.0),identity:item.0)
        }
        return .init(layoutVersion:LifeHeroTownContract.layout,plots:plots,
                     civics:Dictionary(uniqueKeysWithValues:["road","water","housing","trade","industry","academy","garden","defense"].map{($0,0)}),
                     landmarks:["welfare":0,"industry":0,"military":0],attachments:["ration":0,"delivery":1,"cart":0],
                     qualifiedWindows:[:],economyWindows:0,nextEconomyWindow:21600,
                     supplyRecovery:false,lowMealStreak:0,goodMealStreak:0,memories:[])
    }

    public func plot(_ id:String) -> LifePlotState? { plots.first{$0.id == id} }
}

public struct LifeHeroTownState: Codable, Equatable, Sendable {
    public var saveID: String
    public var contentHash: String
    public var authority: String
    public var createdAtUTC: Int64
    public var ownedHeroes: [String:LifeOwnedHero]
    public var adminLease: LifeAdminLease?
    public var skillSnapshots: [LifeSkillSnapshot]
    public var city: LifeCityState
    /// Optional so existing format-4 saves decode without destructive migration.
    public var health: LifeHealthState? = nil
    /// Optional layout-7 housing slice; absent in untouched format-4 saves.
    public var courtyard: LifeCourtyardState? = nil

    public static func initial(wallUTC:Int64) -> Self {
        let starters = ["xunyu","liubei","zhangfei","zhaoyun","huangyueying"]
        let owned = Dictionary(uniqueKeysWithValues: starters.map { id in
            (id, LifeOwnedHero(heroID:id,star:1,sourceDrawID:"founding",arrivalState:"resident",arrivalAt:nil,bedReservation:"house-1"))
        })
        return .init(saveID:UUID().uuidString,contentHash:LifeHeroTownContract.contentHash,
                     authority:LifeHeroTownContract.authority,createdAtUTC:wallUTC,
                     ownedHeroes:owned,adminLease:nil,skillSnapshots:[],city:.initial(),health:.initial(),courtyard:nil)
    }
}

public enum LifeLayout6 {
    public static let roadX: [Double] = [140,680,1200,1780]
    public static let roadY: [Double] = [200,380,640,840,1000]
    public static let fieldPoints: [LifePoint] = (0..<24).map { index in
        let column = index % 4, row = index / 4
        return .init(400 + Double(column) * 105, 405 + Double(row) * 52)
    }
}
