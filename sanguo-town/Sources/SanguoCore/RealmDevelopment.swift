import Foundation

/// Opt-in expansion of the existing growth save. Every asset still belongs to WorldState.
public enum RealmRules {
    public static let version = "town-0.4"
    public static let day: Int64 = 86_400
}
public enum CivicTrack: String, Codable, CaseIterable, Sendable {
    case streets, water, homes, commerce, industry, academy, gardens, ramparts
    public var title: String {
        switch self {
        case .streets: "街巷铺设"; case .water: "渠井水利"; case .homes: "里坊安居"
        case .commerce: "商街仓埠"; case .industry: "工造院区"; case .academy: "书院藏阁"
        case .gardens: "园林游憩"; case .ramparts: "城门守备"
        }
    }
    public var detail: String {
        switch self {
        case .streets: "石路、街灯与路亭；每级缩短本城出发运输工时5%"
        case .water: "沟渠、水井与水车；每级提升农桑产速3%"
        case .homes: "院墙、坊门与生活设施；每级增加4个真实住房容量"
        case .commerce: "铺面、货栈与商埠；每级提高本地酒类需求，不凭空发钱"
        case .industry: "工棚、堆场与吊架；每级提升器材加工3%"
        case .academy: "书舍、藏阁与讲学亭；每级提高自动研习效率"
        case .gardens: "植树、庭园与池景；供给充足时改善居民入住速度"
        case .ramparts: "门楼、箭楼与城墙整修；改善授权军务准备，不自动宣战"
        }
    }
    public static func order(for policy: Policy) -> [Self] {
        switch policy {
        case .trade: [.commerce,.streets,.water,.homes,.academy,.gardens,.industry,.ramparts]
        case .industry: [.industry,.water,.streets,.homes,.academy,.commerce,.ramparts,.gardens]
        case .military: [.ramparts,.industry,.water,.streets,.homes,.academy,.commerce,.gardens]
        case .supply: [.water,.homes,.gardens,.streets,.academy,.commerce,.industry,.ramparts]
        case .balanced: [.streets,.water,.homes,.commerce,.industry,.academy,.gardens,.ramparts]
        }
    }
}
public struct CivicProject: Codable, Equatable, Sendable {
    public var track: CivicTrack
    public var level: Int
    public var startedAt: Int64
    public var work: Int64 = 0
    public var requiredWork: Int64
    public var workers: Int = 0
    public var cash: Int64
    public var spent: Int64 = 0
    public var materials: [String:Int64]
    public var used: [String:Int64] = [:]
    public var paused: Bool = false
    public var progress: Double { Double(work) / Double(requiredWork) }
}
public struct CivicCity: Codable, Equatable, Sendable {
    public var levels: [String:Int] = [:]
    public var project: CivicProject?
    public var completedAt: [String:Int64] = [:]
    public var levelTotal: Int { levels.values.reduce(0,+) }
    public var workers: Int { project?.workers ?? 0 }
    public func level(_ track: CivicTrack) -> Int { levels[track.rawValue, default:0] }
}
public enum CollectibleKind: String, Codable, Sendable { case person, weapon, mount }
public struct CollectionStage: Sendable {
    public let title: String
    public let seconds: Int64
    public let cash: Int64
    public let materials: [String:Int64]
}
public struct CollectibleDefinition: Sendable {
    public let id: String, name: String
    public let kind: CollectibleKind
    public let building: BuildingKind
    public let stages: [CollectionStage]
    public var totalCash: Int64 { stages.reduce(0) { $0+$1.cash } }
    public var totalHours: Int64 { stages.reduce(0) { $0+$1.seconds } / 3600 }
    public var totalMaterials: [String:Int64] {
        var result:[String:Int64]=[:]
        for stage in stages { for (key,value) in stage.materials { result[key,default:0]+=value } }
        return result
    }
}
public enum CollectionCatalog {
    static func s(_ name:String,_ hours:Int64,_ cash:Int64,_ materials:[String:Int64]=[:]) -> CollectionStage {
        .init(title:name,seconds:hours*3600,cash:cash,materials:materials.mapValues{$0*1000})
    }
    public static let all: [CollectibleDefinition] = [
        .init(id:"zhaoyun",name:"赵云",kind:.person,building:.hall,stages:[s("接待过路游士",4,30),s("协助乡里护送",12,80,["grain":20]),s("邀其留城",4,50)]),
        .init(id:"lusu",name:"鲁肃",kind:.person,building:.market,stages:[s("结识行商",6,50),s("合办本地互市",24,120,["wine":4]),s("商议长居",6,80)]),
        .init(id:"liang",name:"诸葛亮",kind:.person,building:.workshop,stages:[s("探访工匠",12,80),s("共议器材改良",36,180,["tools":4]),s("邀请入城",12,100)]),
        .init(id:"guanyu",name:"关羽",kind:.person,building:.station,stages:[s("驿站听闻",8,50),s("同行商路",24,150,["grain":30]),s("相约定居",8,80)]),
        .init(id:"zhangfei",name:"张飞",kind:.person,building:.tavern,stages:[s("酒肆相识",6,40,["wine":4]),s("筹办乡宴",18,100,["wine":8]),s("邀其相助",6,60)]),
        .init(id:"xunyu",name:"荀彧",kind:.person,building:.hall,stages:[s("修书求贤",8,80),s("共议安民方略",30,160,["grain":30]),s("礼聘入城",8,80)]),
        .init(id:"silver-spear",name:"银纹长枪",kind:.weapon,building:.workshop,stages:[s("寻访旧枪",4,40,["wood":4]),s("打磨修复",24,100,["iron":10])]),
        .init(id:"dragon-spear",name:"龙胆亮银枪",kind:.weapon,building:.workshop,stages:[s("访旧藏家",12,100),s("换得残件",12,180,["tools":3]),s("修复银枪",48,220,["iron":25])]),
        .init(id:"crescent-blade",name:"青龙偃月刀",kind:.weapon,building:.workshop,stages:[s("工匠介绍",8,100),s("寻得刀身",24,180,["tools":4]),s("合刃淬火",48,240,["iron":30])]),
        .init(id:"serpent-spear",name:"丈八蛇矛",kind:.weapon,building:.workshop,stages:[s("辨认旧件",12,100),s("整修矛杆",24,150,["wood":20]),s("重铸矛锋",48,240,["iron":25])]),
        .init(id:"qinggang",name:"青釭剑",kind:.weapon,building:.workshop,stages:[s("旧物寄售",12,130),s("鉴别剑身",24,180),s("修复剑刃",48,260,["iron":25,"tools":4])]),
        .init(id:"seven-star",name:"七星宝刀",kind:.weapon,building:.workshop,stages:[s("走访藏家",18,120),s("合对铭记",24,200),s("修整宝刀",48,260,["iron":20,"tools":5])]),
        .init(id:"yellow-horse",name:"黄骠马",kind:.mount,building:.stable,stages:[s("接待马商",6,50),s("熟悉与驯养",24,120,["grain":40])]),
        .init(id:"red-hare",name:"赤兔",kind:.mount,building:.stable,stages:[s("取得牧场消息",18,100),s("寻访与接回",36,240,["grain":40]),s("稳妥驯养",60,300,["grain":80,"tools":3])]),
        .init(id:"dilu",name:"的卢",kind:.mount,building:.stable,stages:[s("山路寻马",18,100),s("建立信任",36,180,["grain":40]),s("安置驯养",48,250,["grain":80])]),
        .init(id:"jueying",name:"绝影",kind:.mount,building:.stable,stages:[s("远客带来消息",18,100),s("寻访良马",36,200,["grain":40]),s("培养骑乘",60,280,["grain":80,"tools":3])])
    ]
    public static func item(_ id:String) -> CollectibleDefinition? { all.first{$0.id==id} }
    public static func attributes(_ id:String) -> Attributes {
        switch id {
        case "xunyu": .init(command:55,valor:35,strategy:88,administration:94,charisma:85)
        case "liang": .init(command:85,valor:35,strategy:96,administration:92,charisma:84)
        case "lusu": .init(command:70,valor:40,strategy:84,administration:86,charisma:94)
        case "zhaoyun": .init(command:92,valor:94,strategy:74,administration:62,charisma:82)
        case "guanyu": .init(command:90,valor:96,strategy:72,administration:60,charisma:80)
        case "zhangfei": .init(command:88,valor:97,strategy:55,administration:42,charisma:60)
        default: .init()
        }
    }
}
public struct CollectionProgress: Codable, Equatable, Sendable {
    public var stage = 0
    public var dueAt: Int64?
    public var cityID: String
    public var spent: Int64 = 0
    public var completedAt: Int64?
    public var history: [String] = []
    public var inherited: Bool? = nil
}
public struct CargoTrip: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var source: String
    public var destination: String
    public var resource: Resource
    public var quantity: Int64
    public var arriveAt: Int64
    public var returnAt: Int64
    public var delivered = false
    public var externalReceipt: Int64? = nil
}
public struct PersonJourney: Codable, Equatable, Sendable {
    public var personID: String
    public var destination: String
    public var arriveAt: Int64
}
public enum RegionalGoal: String, Codable, CaseIterable, Sendable {
    case riverTrade, mountainTrade, securePass, settleStone, settleRiver
    public var title: String {
        switch self {
        case .riverTrade: "交涉渡口互市"; case .mountainTrade: "建立山地合作"
        case .securePass: "军团护送开路"; case .settleStone: "合作建设白石"; case .settleRiver: "合建南渡商埠"
        }
    }
    public var cash: Int64 { switch self { case .riverTrade:800;case .mountainTrade:600;case .securePass:400;case .settleStone:3000;case .settleRiver:4000 } }
    public var hours: Int64 { switch self { case .riverTrade:36;case .mountainTrade:30;case .securePass:12;case .settleStone:72;case .settleRiver:96 } }
    public var materials: [String:Int64] {
        switch self {
        case .riverTrade: ["wine":20_000,"grain":20_000]
        case .mountainTrade: ["tools":10_000,"grain":20_000]
        case .securePass: ["grain":60_000,"tools":4_000]
        case .settleStone,.settleRiver: ["grain":250_000,"wood":150_000,"iron":50_000,"tools":10_000]
        }
    }
}
public struct RegionalOperation: Codable, Equatable, Sendable {
    public var goal: RegionalGoal
    public var source: String
    public var dueAt: Int64
    public var strength: Int
    public var training: Int
    public var fortificationLevel: Int = 0
}
public struct RealmDevelopment: Codable, Equatable, Sendable {
    public var version = 1
    public var civic: [String:CivicCity] = [:]
    public var collectionGoal: String?
    public var collections: [String:CollectionProgress] = [:]
    public var equipment: [String:String] = [:] // collectibleID -> personID, never duplicate instances
    public var trips: [CargoTrip] = []
    public var journeys: [PersonJourney] = []
    public var operation: RegionalOperation?
    public var completedGoals: [String] = []
    public var operationAttempts: [String:Int] = [:]
    public var lastFailedStrength = 0
    public var wounded = 0
    public var nextRecovery: Int64
    public var nextStudy: Int64
    public var nextTrade: Int64
    public var routeIncome: Int64 = 0
    public var civicCashSpent: Int64 = 0
    public var regionalCashSpent: Int64 = 0
    /// Nil keeps legacy town-0.4 planning and appearance unchanged until consent.
    public var identity: CityIdentityState? = nil
    public var reservationCash: Int64 { civic.values.compactMap(\.project).reduce(0){$0+$1.cash-$1.spent} }
    public var civicCount: Int { civic.values.reduce(0){$0+$1.levelTotal} }
}
public enum RealmAction: Codable, Equatable, Sendable {
    case adoptIdentity(policy:Policy,investment:InvestmentStyle)
    case adopt(policy:Policy,investment:InvestmentStyle)
    case collection(String?)
    case equip(item:String,person:String?)
    case regional(RegionalGoal)
    case movePerson(person:String,destination:String)
    case pauseCivic(city:String,paused:Bool)
    case removeMemory(String)
}
