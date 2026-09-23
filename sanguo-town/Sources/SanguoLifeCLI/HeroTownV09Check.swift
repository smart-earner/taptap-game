import Foundation
import SanguoLife

enum HeroTownV09Check {
    static func run() async throws {
        var passed=0
        func check(_ condition:Bool,_ id:String,_ message:String)throws {
            guard condition else{throw LifeError.invalid("\(id) FAILED: \(message)")}
            passed+=1;print("PASS \(id) \(message)")
        }
        func make(_ seed:UInt64=42)throws->LifeRuntime {
            try .init(catalog:.bundled(),wallUTC:0,formalHeroTown:true,rngSeed:seed)
        }
        func command(_ engine:inout LifeRuntime,_ action:LifeGachaAction,_ id:String=UUID().uuidString)throws->LifeGachaReceipt {
            try engine.performGacha(.player(id:id,revision:engine.world.sequence,action:action))
        }
        func fund(_ engine:inout LifeRuntime,_ coins:Int64) throws {
            let rate=engine.world.gacha!.goldRebalance?.coinsPerNewIngot ?? 10
            let ingots=coins/rate*1000
            var world=engine.world
            world.initial["gold_ingot",default:0]+=ingots
            world.consumed["gold_ingot",default:0]+=ingots
            world.gacha!.minted+=coins
            world.treasury+=coins
            engine=try LifeRuntime(catalog:.bundled(),world:world)
        }

        var base=try make()
        let stocks:[LifeResource:Int64]=[.grain:24000,.meat:0,.meal:10000,.rations:0,.wood:20000,.stone:8000,.iron:4000,.tools:2000,.gold_ore:0,.gold_ingot:0]
        try check(base.world.rules==LifeHeroTownContract.rules && base.world.format==4 && base.world.agents.count==5 && base.world.treasury==200,"GC01","formal rules, five founders and one-time 200 coins")
        try check(stocks.allSatisfy{base.world.amount($0.key)==$0.value} &&
                  base.world.amount(.rare_ore)==0 && base.world.amount(.refined_iron)==0 &&
                  LifeResource.allCases.count==12,"GC02","original bootstrap stock stays exact; two v0.12 resources start empty")
        try check(base.world.heroTown?.city.plots.count==18 && LifeMap.places.keys.filter{$0.hasPrefix("field-")}.count==24,"GC03","layout6 has 18 plots and 24 planned field beds")
        try check(base.world.agents.values.allSatisfy{$0.heroID==$0.id && $0.origin=="founding"},"GC04","no anonymous or hidden residents")

        let denied=base.world
        do {_ = try base.performGacha(.init(action:.draw(count:1,pool:base.definition!.gacha.pool_version)));throw LifeError.invalid("unscoped command accepted")}
        catch {try check(base.world==denied,"GC05","formal player envelope and revision are mandatory")}

        let pool=base.definition!.gacha.pool_version
        let first=try command(&base,.draw(count:1,pool:pool),"draw-once"),after=base.world
        let retry=try base.performGacha(first.request)
        try check(first==retry && base.world==after && base.world.treasury==100,"GC06","paid draw is atomic and idempotent")
        do {_ = try command(&base,.draw(count:10,pool:pool));throw LifeError.invalid("insufficient ten-draw accepted")}
        catch {try check(base.world==after,"GC07","insufficient gold changes neither wallet nor RNG")}

        var pity=try make(7);var pityWorld=pity.world;pityWorld.gacha!.pity=19;pity=try LifeRuntime(catalog:.bundled(),world:pityWorld)
        let forced=try command(&pity,.draw(count:1,pool:pool))
        try check(forced.draws.first?.rarity=="legend" && pity.world.gacha!.pity==0,"GC08","twentieth pull forces a legend and resets pity")

        var batch=try make(11);try fund(&batch,2000)
        let ten=try command(&batch,.draw(count:10,pool:pool),"ten")
        let uniqueBodies=Set(batch.world.agents.keys).union(batch.world.gacha!.arrivals.keys)
        try check(ten.draws.count==10 && uniqueBodies.count==batch.world.gacha!.stars.count && batch.world.gacha!.cards.values.reduce(0,{$0+$1.count})==Int64(ten.draws.filter{!$0.isNew}.count),"GC09","ten-pull resolves new ownership before later duplicates")
        let newIDs=ten.draws.filter(\.isNew).map(\.heroID)
        try batch.advance(to:batch.world.time+30)
        try check(newIDs.allSatisfy{batch.world.agents[$0] != nil} && batch.world.gacha!.arrivals.isEmpty,"GC10","new heroes arrive once after 30 seconds as real residents")

        var cards=try make();var cardWorld=cards.world;cardWorld.gacha!.cards["fixture"] = .init(id:"fixture",heroID:"xunyu",origin:"fixture",count:14,originDrawIDs:["fixture"]);cards=try LifeRuntime(catalog:.bundled(),world:cardWorld)
        _=try command(&cards,.lock(card:"fixture",locked:true))
        let locked=cards.world
        do {_=try command(&cards,.starUp(hero:"xunyu",target:2));throw LifeError.invalid("locked card consumed")}
        catch {try check(cards.world==locked,"GC11","locked cards cannot be spent")}
        _=try command(&cards,.lock(card:"fixture",locked:false))
        _=try command(&cards,.starUpSelected(hero:"xunyu",target:2,cards:[.init(lotID:"fixture",quantity:1)]))
        _=try command(&cards,.starUp(hero:"xunyu",target:3))
        try check(cards.world.gacha!.stars["xunyu"]==3 && cards.world.gacha!.cardCount("xunyu")==11 && cards.world.treasury==200,"GC12","manual star-up consumes 1 then 2 same-name cards, never coins or body")

        let selection=[LifeCardSelection(lotID:"fixture",quantity:5)]
        let preview=cards.world.gacha!.cultivationPreviewHash(selection)
        let beforeSouls=cards.world.gacha!.souls
        _=try command(&cards,.disassembleMany(cards:selection,confirmed:true,previewHash:preview))
        try check(cards.world.gacha!.souls-beforeSouls==500,"GC13","confirmed batch decomposition uses rarity yield and preview hash")
        _=try command(&cards,.exchange(hero:"xunyu",quantity:1))
        try check(cards.world.gacha!.souls==100 && cards.world.gacha!.stars["xunyu"]==3,"GC14","soul exchange creates a card without automatic star-up")

        let cultivation=(cards.world.gacha!.stars,cards.world.gacha!.cards,cards.world.gacha!.souls)
        try cards.advance(to:cards.world.time+86400)
        try check(cards.world.gacha!.stars==cultivation.0 && cards.world.gacha!.cards==cultivation.1 && cards.world.gacha!.souls==cultivation.2,"GC15","governor and offline simulation cannot consume cultivation assets")

        var economy=try make(123);try economy.advance(to:7200)
        try check(economy.world.produced["gold_ore",default:0]>0 && economy.world.produced["gold_ingot",default:0]>0,"GC16","gold is mined, hauled and smelted by real tasks")
        let mintedRate=economy.world.gacha!.goldRebalance?.coinsPerNewIngot ?? 10
        try check(economy.world.gacha!.minted==economy.world.consumed["gold_ingot",default:0]/1000*mintedRate && economy.world.treasury==200+economy.world.gacha!.minted,"GC17","every minted coin has consumed-ingot provenance")
        try check(economy.world.foodCoverage>=9500 && economy.world.amount(.wood)>=0,"GC18","gold production preserves food and cannot overdraw protected fuel")

        let activeSnapshot=economy.world.tasks.values.compactMap(\.skillSnapshot).first
        if let hero=activeSnapshot?.heroID {
            var changed=economy.world;changed.gacha!.stars[hero]=min(5,(changed.gacha!.stars[hero] ?? 1)+1);changed.heroTown!.ownedHeroes[hero]!.star=changed.gacha!.stars[hero]!
            economy=try LifeRuntime(catalog:.bundled(),world:changed)
        }
        try check(activeSnapshot==economy.world.tasks.values.first(where:{$0.skillSnapshot?.id==activeSnapshot?.id})?.skillSnapshot,"GC19","star changes do not rewrite an active stage snapshot")
        try check(economy.definition!.heroes.allSatisfy{$0.skills.count==3 && $0.skills.map(\.unlock_star)==[1,3,5]},"GC20","all 30 heroes have authoritative 1/3/5-star skills")

        let saved=try LifeSaveStore.decode(LifeSaveStore.encode(economy.world))
        try check(saved==economy.world && saved.heroTown?.contentHash==LifeHeroTownContract.contentHash,"GC21","format4 save round-trips with content hash")
        var cadenceA=try make(9),cadenceB=cadenceA
        try cadenceA.advance(to:14400)
        for t in stride(from:Int64(17),to:14400,by:17){try cadenceB.advance(to:t)}
        try cadenceB.advance(to:14400)
        try check(cadenceA.world==cadenceB.world,"GC22","simulation is invariant to advance cadence")

        var complete=try make();var completeWorld=complete.world
        for hero in complete.definition!.heroes.prefix(completeWorld.gacha!.rosterTarget) {
            completeWorld.gacha!.stars[hero.id]=5
            completeWorld.heroTown!.ownedHeroes[hero.id] = LifeOwnedHero(heroID:hero.id,star:5,sourceDrawID:"fixture",arrivalState:"resident",arrivalAt:nil,bedReservation:"tavern-1.guest")
            if completeWorld.agents[hero.id]==nil {
                var resident=completeWorld.agents["liubei"]!;resident.id=hero.id;resident.name=hero.name;resident.heroID=hero.id;resident.origin="recruited";resident.node="tavern";resident.home="tavern";resident.dining="guest-meals";resident.taskID=nil
                completeWorld.agents[hero.id]=resident;completeWorld.owned.append(hero.id)
            }
        }
        completeWorld.owned=Array(Set(completeWorld.owned)).sorted();complete=try LifeRuntime(catalog:.bundled(),world:completeWorld)
        let completeBefore=complete.world
        do {_=try command(&complete,.draw(count:1,pool:pool));throw LifeError.invalid("complete pool charged")}
        catch {try check(complete.world==completeBefore && complete.world.gacha!.isComplete,"GC23","all-30 five-star collection stops paid draws and new gold demand")}

        var random=LifeGachaState(rng:0x123456789abcdef),counts=[0,0,0]
        for _ in 0..<1_000_000 {
            let roll=random.uniform(10000);let rarity=base.definition!.rarity(for:roll)
            counts[rarity=="talent" ? 0:(rarity=="renowned" ? 1:2)]+=1
        }
        try check(abs(counts[0]-700000)<5000 && abs(counts[1]-250000)<5000 && abs(counts[2]-50000)<2500,"GC24","one-million SplitMix64 samples match 70/25/5 boundaries")

        var crowd=try make(55);var crowdWorld=crowd.world
        for hero in crowd.definition!.heroes.prefix(crowdWorld.gacha!.rosterTarget) where crowd.world.gacha!.stars[hero.id]==nil {
            var resident=crowdWorld.agents["liubei"]!;resident.id=hero.id;resident.name=hero.name;resident.heroID=hero.id;resident.origin="recruited";resident.node="tavern";resident.home="tavern";resident.dining="guest-meals";resident.taskID=nil
            crowdWorld.agents[hero.id]=resident;crowdWorld.gacha!.stars[hero.id]=1;crowdWorld.owned.append(hero.id)
            crowdWorld.heroTown!.ownedHeroes[hero.id] = LifeOwnedHero(heroID:hero.id,star:1,sourceDrawID:"fixture",arrivalState:"resident",arrivalAt:nil,bedReservation:"tavern-1.guest")
        }
        crowd=try LifeRuntime(catalog:.bundled(),world:crowdWorld);try crowd.advance(to:86400)
        let remainingGuests=crowd.world.agents.values.filter{$0.home=="tavern"}.count
        if crowd.world.foodCoverage<9500 {try crowd.advance(to:crowd.world.time+8640)}
        let recentMeals=Array(crowd.world.meals.filter(\.closed).suffix(4))
        let recentExpected=recentMeals.reduce(0){$0+$1.expected.count}
        let recentServed=recentMeals.reduce(0){$0+$1.served.count}
        let recentCoverage=recentExpected==0 ? 10000:recentServed*10000/recentExpected
        try check(crowd.world.agents.count==30 && remainingGuests==0 && recentCoverage>=9500 && crowd.world.foodCoverage>=9500 && crowd.world.housing>=30,"GC25","30 real heroes receive housing and recent-four-meal coverage reaches 95%, without hidden labour")

        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("hero-town-check-\(UUID().uuidString)")
        defer{try? FileManager.default.removeItem(at:directory)}
        let store=LifeSaveStore(url:directory.appendingPathComponent("world.json"));try store.save(crowd.world);try store.save(crowd.world)
        let good=try Data(contentsOf:store.url);try Data("broken".utf8).write(to:store.url)
        do {_=try store.load();throw LifeError.invalid("corrupt save accepted")}
        catch {try check(try Data(contentsOf:store.url)==Data("broken".utf8) && !store.availableBackups().isEmpty,"GC26","corrupt save is rejected without overwrite and rolling backup remains")}
        try good.write(to:store.url,options:.atomic)
        let wallets=(crowd.world.gacha!.stars,crowd.world.gacha!.cards,crowd.world.gacha!.souls)
        try crowd.advance(to:crowd.world.time+86400)
        try check(crowd.world.gacha!.stars==wallets.0 && crowd.world.gacha!.cards==wallets.1 && crowd.world.gacha!.souls==wallets.2,"GC27","one offline day changes no player cultivation wallet")
        try check(LifeHeroTownContract.layout==6 && crowd.world.agents.values.allSatisfy{$0.heroID != nil},"GC28","formal presentation data exposes layout6 and only real named identities")
        print("HeroTown v0.9 formal runtime: \(passed)/28 grouped checks passed. UI/energy/manual-experience checks run separately.")
    }
}
