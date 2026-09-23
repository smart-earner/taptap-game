import Foundation

public struct LifeGachaDefinition: Decodable, Sendable {
    public struct Hero: Decodable, Sendable, Identifiable {
        public var id:String, name:String, rarity:String, star_profile:String
        public var skills:[Skill]
    }
    public struct Skill:Decodable,Sendable {
        public var id:String,unlock_star:Int,kind:String
        public var jobs:[String]?
        public var values_by_star:[Int]?
    }
    public struct Gacha:Decodable,Sendable {
        public var pool_version:String,rarity_bp:[String:Int],cost:[String:Int64],pity_threshold:Int,arrival_s:Int64
    }
    public struct Cultivation:Decodable,Sendable {
        public var duplicate_cost_by_next_star:[String:Int64],disassemble_yield:[String:Int64],exchange_cost:[String:Int64]
    }
    public var spec_version:String,heroes:[Hero],recipes:[LifeRecipe],buildings:[LifeBuildingQuote],gacha:Gacha,cultivation:Cultivation
    public static func bundled() throws -> Self {
        let url=Bundle.main.url(forResource:"hero-town-v0.9",withExtension:"json",subdirectory:"HeroTown09")
            ?? Bundle.module.url(forResource:"hero-town-v0.9",withExtension:"json")
        guard let url else {throw LifeError.invalid("缺少v0.9参数包")}
        let d=try JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
        guard d.spec_version=="0.9.0",d.heroes.count==30,Set(d.heroes.map(\.id)).count==30,
              d.gacha.cost==["single":100,"ten":1000],d.gacha.rarity_bp==["talent":7000,"renowned":2500,"legend":500] else {throw LifeError.invalid("v0.9参数包不合法")}
        guard d.gacha.pity_threshold==20,d.gacha.arrival_s==30,
              d.cultivation.duplicate_cost_by_next_star==["2":1,"3":2,"4":3,"5":4],
              d.cultivation.disassemble_yield==["talent":10,"renowned":30,"legend":100],
              d.cultivation.exchange_cost==["talent":40,"renowned":120,"legend":400],
              d.heroes.filter({$0.rarity=="talent"}).count==10,d.heroes.filter({$0.rarity=="renowned"}).count==12,d.heroes.filter({$0.rarity=="legend"}).count==8,
              d.heroes.allSatisfy({h in ["food","supply","craft","logistics","trade","guard"].contains(h.star_profile) && h.skills.count==3 && h.skills.map(\.unlock_star)==[1,3,5] && h.skills.prefix(2).allSatisfy{$0.values_by_star?.count==5}}),
              Set(d.recipes.map(\.id))==Set(["cook_basic","cook_meat","ration_plain","forge","smelt_gold","cook_feast"])
        else {throw LifeError.invalid("卡池、保底或星技参数不合法")}
        return d
    }
    public func hero(_ id:String)->Hero? {heroes.first{$0.id==id}}
    public func availableHeroes(phase:Int)->[Hero] {Array(heroes.prefix(min(heroes.count,30+10*max(0,min(3,phase)))))}
    public func rarity(for roll:UInt64)->String {roll<7000 ? "talent":(roll<9500 ? "renowned":"legend")}
}
public struct LifeDuplicateCard:Codable,Equatable,Sendable,Identifiable {
    public var id:String,heroID:String,origin:String
    public var count:Int64
    public var locked=false
    public var originDrawIDs:[String]? = nil
    public var exchangeReceipt:String? = nil
    public init(id:String,heroID:String,origin:String,count:Int64,locked:Bool=false,originDrawIDs:[String]?=nil,exchangeReceipt:String?=nil) {
        self.id=id;self.heroID=heroID;self.origin=origin;self.count=count;self.locked=locked;self.originDrawIDs=originDrawIDs;self.exchangeReceipt=exchangeReceipt
    }
}
public struct LifeDrawResult:Codable,Equatable,Sendable,Identifiable {
    public var id:String,heroID:String,rarity:String
    public var isNew:Bool
}
public enum LifeGachaAction:Codable,Equatable,Sendable {
    case draw(count:Int,pool:String)
    case starUp(hero:String,target:Int)
    case starUpSelected(hero:String,target:Int,cards:[LifeCardSelection])
    case disassemble(card:String,quantity:Int64)
    case disassembleMany(cards:[LifeCardSelection],confirmed:Bool,previewHash:String)
    case exchange(hero:String,quantity:Int64)
    case lock(card:String,locked:Bool)
}
public struct LifeCardSelection:Codable,Equatable,Sendable,Hashable {
    public var lotID:String,quantity:Int64
    public init(lotID:String,quantity:Int64){self.lotID=lotID;self.quantity=quantity}
}
public struct LifeGachaRequest:Codable,Equatable,Sendable {
    public var id:String,action:LifeGachaAction
    public var expectedRevision:Int64? = nil
    public var payloadHash:String? = nil
    public var principal:String? = nil
    public init(id:String=UUID().uuidString,action:LifeGachaAction,expectedRevision:Int64?=nil,payloadHash:String?=nil,principal:String?=nil){
        self.id=id;self.action=action;self.expectedRevision=expectedRevision;self.payloadHash=payloadHash;self.principal=principal
    }
    public static func hash(_ action:LifeGachaAction)->String {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let data=(try? encoder.encode(action)) ?? Data()
        let value=data.reduce(UInt64(14695981039346656037)){($0 ^ UInt64($1)) &* 1099511628211}
        return String(value,radix:16)
    }
    public static func player(id:String=UUID().uuidString,revision:Int64,action:LifeGachaAction)->Self {
        .init(id:id,action:action,expectedRevision:revision,payloadHash:hash(action),principal:"player")
    }
}
public struct LifeGachaReceipt:Codable,Equatable,Sendable {
    public var request:LifeGachaRequest,draws:[LifeDrawResult],message:String
    public var revisionBefore:Int64? = nil,revisionAfter:Int64? = nil
    public var rngBefore:UInt64? = nil,rngAfter:UInt64? = nil
    public var pityBefore:Int? = nil,pityAfter:Int? = nil
    public var price:Int64? = nil,poolVersion:String? = nil
    public var selectedLots:[LifeCardSelection]? = nil
    public var starBefore:Int? = nil,starAfter:Int? = nil
    public var soulsDelta:Int64? = nil
}
public struct LifeGachaState:Codable,Equatable,Sendable {
    public var rng:UInt64
    public var pity=0
    public var minted:Int64=0,spent:Int64=0,souls:Int64=0,soulsMade:Int64=0,soulsSpent:Int64=0
    /// Nil means the original ten-coins-per-ingot ledger. Existing saves are
    /// anchored at their historical totals before the faster formal economy.
    public var goldRebalance:LifeGoldRebalance? = nil
    public var stars:[String:Int]=[:]
    public var arrivals:[String:Int64]=[:]
    public var cards:[String:LifeDuplicateCard]=[:]
    public var receipts:[String:LifeGachaReceipt]=[:]
    public var receiptSegments:[[String:LifeGachaReceipt]]? = nil
    public var drawCount:Int64=0
    /// Nil is a pre-v0.12 save and means the original thirty-hero pool.
    public var rosterPhase:Int? = nil
    public var lastDraws:[LifeDrawResult]=[]
    public var houseLevels:[Int]=[1]
    public var surveyedProjects:Set<String>=[]
    public init(rng:UInt64){self.rng=rng}
    public var rosterTarget:Int {30+10*(rosterPhase ?? 0)}
    public var isComplete:Bool {stars.count==rosterTarget && stars.values.allSatisfy{$0==5}}
    public func poolVersion(formal:Bool)->String {
        formal ? "tavern-standard-v12-p\(rosterPhase ?? 0)":"tavern-standard-1"
    }
    public func cardCount(_ hero:String,unlockedOnly:Bool=false)->Int64 {
        cards.values.filter{$0.heroID==hero && (!unlockedOnly || !$0.locked)}.reduce(0){$0+$1.count}
    }
    public func receipt(_ id:String)->LifeGachaReceipt? {
        if let value=receipts[id] {return value}
        return receiptSegments?.lazy.compactMap{$0[id]}.first
    }
    public func cultivationPreviewHash(_ selections:[LifeCardSelection])->String {
        let canonical=selections.sorted{$0.lotID==$1.lotID ? $0.quantity<$1.quantity:$0.lotID<$1.lotID}.map { selection in
            let card=cards[selection.lotID]
            return "\(selection.lotID):\(selection.quantity):\(card?.heroID ?? "missing"):\(card?.count ?? -1):\(card?.locked == true ? 1:0)"
        }.joined(separator:"|")
        let value=canonical.utf8.reduce(UInt64(14695981039346656037)){($0 ^ UInt64($1)) &* 1099511628211}
        return String(value,radix:16)
    }
    public mutating func uniform(_ n:UInt64)->UInt64 {
        let threshold=(0 &- n)%n
        while true {
            rng &+= 0x9E3779B97F4A7C15
            var z=rng;z=(z ^ (z>>30)) &* 0xBF58476D1CE4E5B9;z=(z ^ (z>>27)) &* 0x94D049BB133111EB;z ^= z>>31
            if z>=threshold {return z%n}
        }
    }
}

public struct LifeGoldRebalance:Codable,Equatable,Sendable {
    public var historicalIngots:Int64
    public var historicalCoins:Int64
    public var coinsPerNewIngot:Int64
    public init(historicalIngots:Int64,historicalCoins:Int64,coinsPerNewIngot:Int64) {
        self.historicalIngots=historicalIngots
        self.historicalCoins=historicalCoins
        self.coinsPerNewIngot=coinsPerNewIngot
    }
}

extension LifeRuntime {
    public mutating func performGacha(_ request:LifeGachaRequest) throws -> LifeGachaReceipt {
        guard world.isGacha,let definition else {throw LifeError.invalid("此存档未开放酒馆抽卡")}
        if let receipt=world.gacha?.receipt(request.id) {
            guard receipt.request==request else {throw LifeError.invalid("命令ID已被其他操作占用")}
            return receipt
        }
        guard !request.id.isEmpty,request.id.count<=128 else {throw LifeError.invalid("命令ID无效")}
        if world.isFormalHeroTown {
            guard request.principal=="player" else{throw LifeError.invalid("DENIED_SCOPE：只有玩家可执行招募与培养")}
            guard request.expectedRevision==world.sequence else{throw LifeError.invalid("STALE：世界版本已变化，请刷新后重试")}
            guard request.payloadHash==LifeGachaRequest.hash(request.action) else{throw LifeError.invalid("DENIED_SCOPE：命令载荷校验失败")}
        }
        var draft=self
        let receipt=try draft.applyGacha(request,definition:definition)
        try draft.world.validate()
        self=draft
        return receipt
    }
    private mutating func applyGacha(_ request:LifeGachaRequest,definition d:LifeGachaDefinition) throws -> LifeGachaReceipt {
        var g=world.gacha!
        if g.receipts.count>=10000 {
            var segments=g.receiptSegments ?? []
            guard segments.count<100 else {throw LifeError.invalid("OVERFLOW：幂等回执索引超过安全上限；未扣费")}
            segments.append(g.receipts);g.receiptSegments=segments;g.receipts=[:]
        }
        var draws:[LifeDrawResult]=[]
        var message=""
        let revisionBefore=world.sequence,rngBefore=g.rng,pityBefore=g.pity
        var price:Int64=0,selectedLots:[LifeCardSelection]?=nil,starBefore:Int?=nil,starAfter:Int?=nil,soulsDelta:Int64=0
        switch request.action {
        case .draw(let count,let pool):
            guard [1,10].contains(count),pool==g.poolVersion(formal:world.isFormalHeroTown),!g.isComplete else {throw LifeError.invalid("抽数/卡池不合法或本阶段全员已满星")}
            let cost=Int64(count)*d.gacha.cost["single"]!;price=cost
            guard world.treasury>=cost else {throw LifeError.invalid("金币不足，还差\(cost-world.treasury)")}
            world.treasury-=cost;g.spent+=cost
            for _ in 0..<count {
                let rarity:String
                if g.pity==d.gacha.pity_threshold-1 {rarity="legend"}
                else {rarity=d.rarity(for:g.uniform(10000))}
                let pool=d.availableHeroes(phase:world.isFormalHeroTown ? (g.rosterPhase ?? 0):0).filter{$0.rarity==rarity}.sorted{$0.id<$1.id}
                let hero=pool[Int(g.uniform(UInt64(pool.count)))]
                let isNew=g.stars[hero.id]==nil
                let result=LifeDrawResult(id:world.next("draw"),heroID:hero.id,rarity:rarity,isNew:isNew)
                if isNew {
                    g.stars[hero.id]=1;g.arrivals[hero.id]=world.time+d.gacha.arrival_s
                    world.owned.append(hero.id)
                } else {
                    let id=world.next("card");g.cards[id] = .init(id:id,heroID:hero.id,origin:result.id,count:1,originDrawIDs:[result.id])
                }
                g.pity=rarity=="legend" ? 0:g.pity+1;g.drawCount+=1;draws.append(result)
            }
            g.lastDraws=draws
            message="招募\(count)次：新武将\(draws.filter(\.isNew).count)位，重复卡\(draws.filter{!$0.isNew}.count)张；扣除\(cost)金币。"
        case .starUp(let hero,let target):
            guard let star=g.stars[hero],star<5,target==star+1,let cost=d.cultivation.duplicate_cost_by_next_star[String(target)] else {throw LifeError.invalid("只能为已拥有武将升一星，最高5星")}
            guard g.cardCount(hero,unlockedOnly:true)>=cost else {throw LifeError.invalid("未锁定的同名卡不足，需要\(cost)张")}
            var remaining=cost
            var used:[LifeCardSelection]=[]
            for id in g.cards.keys.sorted() where g.cards[id]!.heroID==hero && !g.cards[id]!.locked && remaining>0 {
                let q=min(remaining,g.cards[id]!.count);used.append(.init(lotID:id,quantity:q));g.cards[id]!.count-=q;remaining-=q
                if g.cards[id]!.count==0 {g.cards[id]=nil}
            }
            starBefore=star;starAfter=target;selectedLots=used
            g.stars[hero]=target;message="\(d.hero(hero)!.name)升至\(target)星；新技能效果从下一工序生效。"
        case .starUpSelected(let hero,let target,let cards):
            guard let star=g.stars[hero],star<5,target==star+1,let cost=d.cultivation.duplicate_cost_by_next_star[String(target)] else {throw LifeError.invalid("MAX_STAR：只能为已拥有武将升一星，最高5星")}
            guard !cards.isEmpty,Set(cards.map(\.lotID)).count==cards.count,cards.reduce(Int64(0),{$0+$1.quantity})==cost else{throw LifeError.invalid("INSUFFICIENT_CARDS：选卡数量必须恰好等于升星需求")}
            for item in cards {
                guard item.quantity>0,let card=g.cards[item.lotID],card.heroID==hero,card.count>=item.quantity else{throw LifeError.invalid("INVALID_CARD：升星只能选择足额同名重复卡")}
                guard !card.locked else{throw LifeError.invalid("CARD_LOCKED：所选重复卡已锁定")}
            }
            for item in cards {g.cards[item.lotID]!.count-=item.quantity;if g.cards[item.lotID]!.count==0{g.cards[item.lotID]=nil}}
            starBefore=star;starAfter=target;selectedLots=cards
            g.stars[hero]=target;message="\(d.hero(hero)!.name)升至\(target)星；所选卡片已原子消费。"
        case .disassemble(let id,let quantity):
            guard var card=g.cards[id],quantity>0,quantity<=card.count,!card.locked,let hero=d.hero(card.heroID) else {throw LifeError.invalid("只能分解未锁定的重复卡；数量无效或卡已锁定")}
            let gain=quantity*d.cultivation.disassemble_yield[hero.rarity]!
            guard gain<=1_000_000_000_000-g.souls else {throw LifeError.invalid("将魂余额超过安全上限")}
            card.count-=quantity;g.cards[id]=card.count==0 ? nil:card
            selectedLots=[.init(lotID:id,quantity:quantity)];soulsDelta=gain
            g.souls+=gain;g.soulsMade+=gain;message="已分解\(hero.name)重复卡\(quantity)张，获得\(gain)通用将魂。"
        case .disassembleMany(let cards,let confirmed,let previewHash):
            guard confirmed,!cards.isEmpty,cards.count<=100,Set(cards.map(\.lotID)).count==cards.count else{throw LifeError.invalid("INVALID_CARD：批量分解必须明确确认，且每个批次只能选择一次")}
            guard previewHash==g.cultivationPreviewHash(cards) else{throw LifeError.invalid("STALE：卡片状态已变化，请重新确认")}
            var gain:Int64=0
            for item in cards {
                guard item.quantity>0,let card=g.cards[item.lotID],item.quantity<=card.count,let hero=d.hero(card.heroID) else{throw LifeError.invalid("INVALID_CARD：重复卡或数量无效")}
                guard !card.locked else{throw LifeError.invalid("CARD_LOCKED：所选重复卡已锁定")}
                let (part,overflow)=item.quantity.multipliedReportingOverflow(by:d.cultivation.disassemble_yield[hero.rarity]!)
                guard !overflow,gain<=1_000_000_000_000-part else{throw LifeError.invalid("OVERFLOW：将魂余额超过安全上限")}
                gain+=part
            }
            for item in cards {g.cards[item.lotID]!.count-=item.quantity;if g.cards[item.lotID]!.count==0{g.cards[item.lotID]=nil}}
            guard g.souls<=1_000_000_000_000-gain else{throw LifeError.invalid("OVERFLOW：将魂余额超过安全上限")}
            selectedLots=cards;soulsDelta=gain;g.souls+=gain;g.soulsMade+=gain
            message="已分解\(cards.reduce(Int64(0)){$0+$1.quantity})张重复卡，获得\(gain)通用将魂。"
        case .exchange(let id,let quantity):
            guard let star=g.stars[id],star<5,let hero=d.hero(id),(1...10).contains(quantity) else {throw LifeError.invalid("只能兑换已拥有且未满星的人物，数量1—10")}
            let needed=((star+1)...5).reduce(Int64(0)){$0+d.cultivation.duplicate_cost_by_next_star[String($1)]!}-g.cardCount(id)
            guard quantity<=needed else {throw LifeError.invalid("兑换量超过到5星的剩余同名卡缺口")}
            let cost=quantity*d.cultivation.exchange_cost[hero.rarity]!
            guard g.souls>=cost else {throw LifeError.invalid("通用将魂不足，需要\(cost)")}
            g.souls-=cost;g.soulsSpent+=cost
            let cardID=world.next("card");g.cards[cardID] = .init(id:cardID,heroID:id,origin:request.id,count:quantity,exchangeReceipt:request.id)
            soulsDelta = -cost
            message="已兑换\(hero.name)同名卡\(quantity)张；未自动升星。"
        case .lock(let id,let locked):
            guard g.cards[id] != nil else {throw LifeError.invalid("重复卡不存在")}
            g.cards[id]!.locked=locked;message=locked ? "重复卡已锁定，不会用于升星或分解。":"重复卡已解锁。"
        }
        world.gacha=g;world.record("gacha",message)
        if world.isFormalHeroTown {syncFormalOwnedHeroes()}
        var receipt=LifeGachaReceipt(request:request,draws:draws,message:message)
        receipt.revisionBefore=revisionBefore;receipt.revisionAfter=world.sequence
        receipt.rngBefore=rngBefore;receipt.rngAfter=g.rng;receipt.pityBefore=pityBefore;receipt.pityAfter=g.pity
        receipt.price=price;receipt.poolVersion=g.poolVersion(formal:world.isFormalHeroTown);receipt.selectedLots=selectedLots
        receipt.starBefore=starBefore;receipt.starAfter=starAfter;receipt.soulsDelta=soulsDelta
        world.gacha!.receipts[request.id]=receipt
        return receipt
    }

    mutating func syncFormalOwnedHeroes() {
        guard world.isFormalHeroTown,var formal=world.heroTown,let g=world.gacha else{return}
        for (id,star) in g.stars {
            if var owned=formal.ownedHeroes[id] {
                owned.star=star
                if let due=g.arrivals[id] {
                    owned.arrivalState=due<=world.time && world.agents[id]==nil ? "waiting_residency":"arriving"
                    owned.arrivalAt=due
                }
                else {owned.arrivalState="resident";owned.arrivalAt=nil}
                formal.ownedHeroes[id]=owned
            } else {
                var reservation="tavern-1.guest"
                if formal.courtyard == nil,let index=formal.city.plots.indices.filter({formal.city.plots[$0].kind=="house" && formal.city.plots[$0].level>0 && formal.city.plots[$0].occupancy<formal.city.plots[$0].capacity}).sorted(by:{formal.city.plots[$0].id<formal.city.plots[$1].id}).first {
                    formal.city.plots[index].occupancy+=1;reservation=formal.city.plots[index].id
                }
                let due=g.arrivals[id]
                formal.ownedHeroes[id] = .init(heroID:id,star:star,sourceDrawID:g.lastDraws.last(where:{$0.heroID==id && $0.isNew})?.id ?? "recruited",
                                                arrivalState:due == nil ? "resident":(due.map{$0<=world.time} == true ? "waiting_residency":"arriving"),
                                                arrivalAt:due,bedReservation:reservation)
            }
        }
        world.heroTown=formal
    }
}
