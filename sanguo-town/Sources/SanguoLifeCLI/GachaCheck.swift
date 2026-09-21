import Foundation
import SanguoLife

enum GachaCheck {
    struct FailingStore:LifePersistence {func save(_ world:LifeWorld)throws{throw LifeError.invalid("injected disk failure")}}
    static func run() async throws {
        var checks=0
        func check(_ ok:Bool,_ message:String)throws{guard ok else{throw LifeError.invalid("CHECK FAILED: \(message)")};checks+=1;print("PASS \(message)")}
        func make(_ seed:UInt64=42)throws->LifeRuntime {try .init(catalog:.bundled(),wallUTC:0,gachaMode:true,rngSeed:seed)}
        var e=try make();let pool=e.definition!.gacha.pool_version
        try check(e.world.treasury==200 && e.world.gacha!.stars.count==5,"new independent save: five heroes, 200 coins")
        let request=LifeGachaRequest(id:"draw-1",action:.draw(count:1,pool:pool))
        let first=try e.performGacha(request),after=e.world
        let repeated=try e.performGacha(request)
        try check(first==repeated && e.world==after,"draw retry returns same result, no extra payment")
        do {_=try e.performGacha(.init(id:"draw-1",action:.draw(count:10,pool:pool)));throw LifeError.invalid("wrongly accepted changed payload")}catch{try check(e.world==after,"same id / changed payload rejected atomically")}
        do {_=try e.performGacha(.init(action:.draw(count:10,pool:pool)));throw LifeError.invalid("wrongly accepted expensive draw")}catch{try check(e.world==after,"insufficient money leaves RNG and wallet intact")}
        var restored=try LifeRuntime(catalog:.bundled(),world:LifeSaveStore.decode(LifeSaveStore.encode(e.world)))
        try e.advance(to:7200)
        for t in stride(from:Int64(17),to:7200,by:17){try restored.advance(to:t)}
        try restored.advance(to:7200)
        try check(e.world==restored.world,"save/restore and different frame cadence match")
        try check(e.world.gacha!.minted>0 && e.world.produced["gold_ore",default:0]>0 && e.world.produced["gold_ingot",default:0]>0,"real mining, smelting, hauling, minting")
        try check(e.world.gacha!.minted==e.world.consumed["gold_ingot",default:0]/1000*10,"every coin has consumed ingot provenance")
        try check(e.world.foodCoverage==10000,"food coverage preserved during gold production")
        try e.advance(to:86400)
        print("DAY coins=\(e.world.treasury) minted=\(e.world.gacha!.minted) meals=\(e.world.foodCoverage)")
        try check(e.world.treasury>=1000,"automatic economy earns a ten-draw without gifted money")
        let ten=try e.performGacha(.init(id:"ten",action:.draw(count:10,pool:pool)))
        try check(ten.draws.count==10 && e.world.gacha!.drawCount==11,"ten draw pays once and yields ten outcomes")
        try e.advance(to:e.world.time+30)
        try check(e.world.agents.count==e.world.gacha!.stars.count && e.world.gacha!.arrivals.isEmpty,"new heroes arrive once; duplicate cards are not people")
        // Explicit deterministic fixtures exercise manual card boundaries, never grant user save assets.
        var fixture=e.world
        guard let cardID=fixture.gacha!.cards.keys.sorted().first else{throw LifeError.invalid("test seed produced no duplicate")}
        let hero=fixture.gacha!.cards[cardID]!.heroID
        fixture.gacha!.cards[cardID]!.count=10
        var f=try LifeRuntime(catalog:.bundled(),world:fixture)
        _=try f.performGacha(.init(action:.lock(card:cardID,locked:true)))
        let locked=f.world
        do{_=try f.performGacha(.init(action:.disassemble(card:cardID,quantity:1)));throw LifeError.invalid("accepted locked card")}catch{try check(f.world==locked,"locked duplicate cannot be decomposed")}
        _=try f.performGacha(.init(action:.lock(card:cardID,locked:false)))
        let money=f.world.treasury
        for target in 2...5 {_=try f.performGacha(.init(action:.starUp(hero:hero,target:target)))}
        try check(f.world.gacha!.stars[hero]==5 && f.world.treasury==money,"manual 1/2/3/4 card upgrades, no coin fee")
        let full=f.world
        do{_=try f.performGacha(.init(action:.starUp(hero:hero,target:6)));throw LifeError.invalid("accepted sixth star")}catch{try check(f.world==full,"sixth star rejected without consumption")}
        var manual=try LifeRuntime(catalog:.bundled(),world:fixture)
        _=try manual.performGacha(.init(action:.disassemble(card:cardID,quantity:4)))
        let beforeStar=manual.world.gacha!.stars[hero]
        _=try manual.performGacha(.init(action:.exchange(hero:hero,quantity:1)))
        try check(manual.world.gacha!.souls==0 && manual.world.gacha!.stars[hero]==beforeStar,"manual 4:1 decomposition/exchange does not auto-upgrade")
        let souls=manual.world.gacha!.souls,cards=manual.world.gacha!.cards,stars=manual.world.gacha!.stars
        try manual.advance(to:manual.world.time+7200)
        try check(manual.world.gacha!.souls==souls && manual.world.gacha!.cards==cards && manual.world.gacha!.stars==stars,"offline city never consumes cultivation assets")
        var pityFixture=try make().world;pityFixture.gacha!.pity=19
        var pity=try LifeRuntime(catalog:.bundled(),world:pityFixture)
        let guaranteed=try pity.performGacha(.init(action:.draw(count:1,pool:pool)))
        try check(guaranteed.draws[0].rarity=="legend" && pity.world.gacha!.pity==0,"twentieth pull forces legend and resets pity")
        let base=try make(),session=LifeSession(engine:base,store:FailingStore())
        do{try await session.send(.gacha(request));throw LifeError.invalid("save should fail")}catch{}
        let snapshot=await session.snapshot()
        try check(snapshot==base.world,"disk failure rolls back draw, RNG, money, and ownership")
        var crowd=try make().world
        let template=crowd.agents["liubei"]!
        for h in e.definition!.heroes where crowd.agents[h.id]==nil {
            var resident=template;resident.id=h.id;resident.heroID=h.id;resident.name=h.name
            resident.taskID=nil;resident.node="gate";resident.home="tavern";resident.dining="guest-meals";resident.job="flex"
            crowd.agents[h.id]=resident;crowd.gacha!.stars[h.id]=1;crowd.owned.append(h.id)
        }
        var stress=try LifeRuntime(catalog:.bundled(),world:crowd)
        try stress.advance(to:86400)
        let guests=stress.world.agents.values.filter{$0.home=="tavern"}.count
        print("CROWD coverage=\(stress.world.foodCoverage) grain=\(stress.world.amount(.grain)) meal=\(stress.world.amount(.meal)) wood=\(stress.world.amount(.wood)) beds=\(stress.world.housing) guests=\(guests)")
        print(stress.world.records.suffix(10).map(\.text).joined(separator:"\n"))
        try check(stress.world.agents.count==30 && stress.world.foodCoverage>=9500,"30 real residents including guests: one-day food recovery")
        try check(stress.world.housing>=30 && stress.world.agents.values.allSatisfy{$0.home=="home"},"prefect builds and upgrades homes and physically relocates guests")
        let baseStars=stress.world.gacha!.stars
        try check(baseStars.values.allSatisfy{$0==1},"crowded automatic management does not upgrade heroes")
        var fullPool=stress.world
        for id in fullPool.gacha!.stars.keys {fullPool.gacha!.stars[id]=5}
        var complete=try LifeRuntime(catalog:.bundled(),world:fullPool)
        var rejected=false
        do{_=try complete.performGacha(.init(action:.draw(count:1,pool:pool)))}catch{rejected=true}
        try check(rejected && complete.world==fullPool,"complete five-star collection stops spending")
        try complete.advance(to:complete.world.time+7200)
        try check(complete.world.foodCoverage>=9500,"high-star signature skills preserve actual city economy")
        print("Gacha integration: \(checks) checks passed. Not full GC01—GC28 acceptance.")
    }
}
