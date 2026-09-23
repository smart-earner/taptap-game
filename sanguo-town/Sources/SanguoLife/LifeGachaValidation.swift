import Foundation
extension LifeWorld {
    func validateGacha() throws {
        func check(_ ok:Bool,_ message:String) throws {if !ok {throw LifeError.invalid(message)}}
        guard let g=gacha else{throw LifeError.invalid("缺少抽卡存档")}
        let ids:Set<String>=["xunyu","zhaoyun","lusu","liang","guanyu","zhangfei","caocao","liubei","sunquan","simayi","guojia","jiaxu","pangtong","xunyou","chenqun","manchong","zhangzhao","huangyueying","zhouyu","luxun","lumeng","zhangliao","xuhuang","xiahoudun","xuchu","machao","huangzhong","weiyan","ganning","lvbu"]
        let unlockedV12=Set(try LifeV12Roster.load().heroes.filter{$0.phase<=(g.rosterPhase ?? 0)}.map(\.id))
        let allowed=isFormalHeroTown ? ids.union(unlockedV12):ids
        try check((0...3).contains(g.rosterPhase ?? 0) && Set(g.stars.keys).isSubset(of:allowed) &&
                  (5...g.rosterTarget).contains(g.stars.count) && g.stars.values.allSatisfy{(1...5).contains($0)},"武将星级或身份无效")
        try check(Set(owned)==Set(g.stars.keys) && Set(agents.keys).union(g.arrivals.keys)==Set(g.stars.keys) && Set(agents.keys).isDisjoint(with:Set(g.arrivals.keys)),"本体与到达权益重复/缺失")
        try check(agents.values.allSatisfy{$0.id==$0.heroID},"抽卡版不允许普通居民")
        try check(g.arrivals.allSatisfy{heroID,due in
            due>time || (isFormalHeroTown && heroTown?.ownedHeroes[heroID]?.arrivalState=="waiting_residency")
        },"抵达或候任时间无效")
        try check((0...19).contains(g.pity) && g.drawCount>=0 && g.drawCount<=1_000_000_000_000,"保底数据无效")
        try check([treasury,g.minted,g.spent,g.souls,g.soulsMade,g.soulsSpent].allSatisfy{(0...1_000_000_000_000).contains($0)},"钱包越界")
        try check(treasury==200+g.minted-g.spent && g.souls==g.soulsMade-g.soulsSpent,"钱包账本不守恒")
        let totalIngots=consumed["gold_ingot",default:0]/1000
        try check(consumed["gold_ingot",default:0]%1000==0,"金币没有完整金锭来源")
        if let rebalance=g.goldRebalance {
            try check(isFormalHeroTown && rebalance.historicalIngots>=0 && rebalance.historicalIngots<=totalIngots &&
                      rebalance.historicalCoins==rebalance.historicalIngots*10 &&
                      (10...1000).contains(rebalance.coinsPerNewIngot) &&
                      g.minted==rebalance.historicalCoins+(totalIngots-rebalance.historicalIngots)*rebalance.coinsPerNewIngot,
                      "新旧金币账本不守恒")
        } else {try check(g.minted==totalIngots*10,"旧版金币账本不守恒")}
        try check(reservedCash==0 && projects.values.allSatisfy{$0.cash==0},"城务不得扣招募金币")
        let segments=g.receiptSegments ?? []
        try check(g.cards.count<=50000 && g.receipts.count<=10000 && segments.count<=100 && segments.allSatisfy{$0.count<=10000},"卡片/回执安全容量已满")
        let allReceiptIDs=Array(g.receipts.keys)+segments.flatMap{$0.keys}
        try check(Set(allReceiptIDs).count==allReceiptIDs.count,"命令幂等索引出现重复")
        for (id,c) in g.cards {try check(c.id==id && g.stars[c.heroID] != nil && c.count>0 && c.count<=1_000_000_000,"卡片来源/数量无效")}
        let maximumHouses=heroTown?.courtyard == nil ? 4:15
        try check((1...maximumHouses).contains(g.houseLevels.count) && g.houseLevels.allSatisfy{(1...3).contains($0)},"住宅级别无效")
        try check(agents.values.filter{$0.home=="home"}.count<=housing && agents.values.filter{$0.home=="tavern"}.count<=30,"床位超额")
        if isFormalHeroTown {
            try check(agents.values.allSatisfy{$0.origin=="founding" || $0.origin=="recruited"},"正式v0.9居民必须具有真实来源")
            let formalReceipts=Array(g.receipts.values)+segments.flatMap{$0.values}
            try check(formalReceipts.allSatisfy{$0.request.principal=="player" && $0.request.payloadHash==LifeGachaRequest.hash($0.request.action)},"正式v0.9命令回执缺少玩家权限或载荷哈希")
        }
    }
}
