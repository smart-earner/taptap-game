import Foundation
extension LifeRuntime {
    mutating func planTrade() {
        guard world.buildings["market",default:0]>0,!world.tasks.values.contains(where:{$0.kind=="export"}),world.foodCoverage>=9500 else{return}
        let period=world.time/21600
        if world.tradePeriod != period {world.tradePeriod=period;world.tradedAmount=0}
        guard world.tradedAmount<24000 else{return}
        for (r,keep,price) in [(LifeResource.tools,Int64(3000),Int64(6)),(.iron,4000,4),(.stone,10000,2)] {
            let free=world.amount(r,at:"warehouse",free:true)-keep
            let q=min(4000,24000-world.tradedAmount,free,4_000_000/r.volume)/1000*1000
            guard q>0,let parts=world.selection(r,quantity:q,at:"warehouse") else{continue}
            var tail=[LifeStep(kind:"load",seconds:10)]
            if let m=move("warehouse","gate",loaded:true){tail.append(m)}
            tail += [.init(kind:"external_sale",seconds:150),.init(kind:"return",seconds:150,destination:"gate")]
            guard let task=assign(kind:"export",job:"merchant",subject:"market",at:"warehouse",work:0,tail:tail) else{continue}
            for p in parts{world.lots[p.lotID]!.reserved+=p.amount}
            world.tasks[task]!.reservations=parts;world.tasks[task]!.quantity=q;world.tasks[task]!.resource=r;world.tasks[task]!.contribution=q/1000*price
            world.tradedAmount+=q
            break
        }
    }
}
