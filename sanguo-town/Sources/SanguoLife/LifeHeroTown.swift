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

public struct LifeOwnedHero: Codable, Equatable, Sendable {
    public var heroID: String
    public var star: Int
    public var sourceDrawID: String
    public var arrivalState: String
    public var arrivalAt: Int64?
    public var bedReservation: String
    public init(heroID:String,star:Int,sourceDrawID:String,arrivalState:String,arrivalAt:Int64?,bedReservation:String) {
        self.heroID=heroID;self.star=star;self.sourceDrawID=sourceDrawID;self.arrivalState=arrivalState;self.arrivalAt=arrivalAt;self.bedReservation=bedReservation
    }
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

    public static func initial(wallUTC:Int64) -> Self {
        let starters = ["xunyu","liubei","zhangfei","zhaoyun","huangyueying"]
        let owned = Dictionary(uniqueKeysWithValues: starters.map { id in
            (id, LifeOwnedHero(heroID:id,star:1,sourceDrawID:"founding",arrivalState:"resident",arrivalAt:nil,bedReservation:"house-1"))
        })
        return .init(saveID:UUID().uuidString,contentHash:LifeHeroTownContract.contentHash,
                     authority:LifeHeroTownContract.authority,createdAtUTC:wallUTC,
                     ownedHeroes:owned,adminLease:nil,skillSnapshots:[],city:.initial())
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
