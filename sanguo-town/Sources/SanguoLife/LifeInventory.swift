import Foundation

extension LifeWorld {
    func freeSpace(_ location:String) -> Int64 {
        guard let s=storages[location] else {return 0}
        return max(0,s.capacity-s.incoming-volume(at:location))
    }
    mutating func add(_ resource:LifeResource,quantity:Int64,at location:String,quality:String="basic",origin:String,production:Bool=false) {
        guard quantity>0 else{return}
        // Merge only identical provenance, quality and location; reservation remains part of stock.
        if let id=lots.keys.sorted().first(where:{lots[$0]!.resource==resource && lots[$0]!.location==location && lots[$0]!.origin==origin && lots[$0]!.quality==quality}) {
            lots[id]!.amount+=quantity
        } else { let id=next("lot");lots[id] = .init(id:id,origin:origin,location:location,resource:resource,amount:quantity,quality:quality) }
        if production {produced[resource.rawValue,default:0]+=quantity}
    }
    func selection(_ resource:LifeResource,quantity:Int64,at location:String,quality:String?=nil) -> [LifeReservation]? {
        var left=quantity;var chosen:[LifeReservation]=[]
        for lot in lots.values.sorted(by:{$0.id<$1.id}) where lot.location==location && lot.resource==resource && (quality == nil || lot.quality==quality) {
            let q=min(left,lot.amount-lot.reserved)
            if q>0 {chosen.append(.init(lotID:lot.id,amount:q));left-=q}
            if left==0 {break}
        }
        return left==0 ? chosen:nil
    }
    mutating func consume(_ resource:LifeResource,quantity:Int64,at location:String) -> Bool {
        guard let parts=selection(resource,quantity:quantity,at:location) else{return false}
        for part in parts {lots[part.lotID]!.amount-=part.amount}
        consumed[resource.rawValue,default:0]+=quantity; pruneLots(); return true
    }
    func has(_ inputs:[String:Int64],at location:String) -> Bool { inputs.allSatisfy{ key,qty in amount(LifeResource(rawValue:key)!,at:location,free:true)>=qty} }
    mutating func use(_ inputs:[String:Int64],at location:String) {
        precondition(has(inputs,at:location))
        for key in inputs.keys.sorted() {precondition(consume(LifeResource(rawValue:key)!,quantity:inputs[key]!,at:location))}
    }
    mutating func pruneLots() {for id in Array(lots.keys) where lots[id]!.amount==0 {lots[id]=nil}}
    public func validate() throws {
        func check(_ b:Bool,_ text:String) throws {if !b{throw LifeError.invalid(text)}}
        try check(format==1 && rules=="life-0.7.2-v1","存档版本不受支持，未重建存档")
        try check(time>=0 && time<=315_360_000 && sequence>0 && sequence<Int64.max/2,"时间或序列越界")
        try check(agents.count<=256 && tasks.count<=2048 && lots.count<=50000,"实体数量超过安全上限")
        try check(treasury>=0 && reservedCash>=0 && reservedCash<=treasury,"国库预留不合法")
        for (id,lot) in lots {
            try check(lot.id==id && lot.amount>0 && lot.amount<=1_000_000_000 && lot.reserved>=0 && lot.reserved<=lot.amount,"批次数量不合法")
            try check(storages[lot.location] != nil || tasks[lot.location] != nil,"批次失去仓库或承运者")
            try check(lot.quality=="basic" || lot.quality=="hearty","餐食品质不合法")
        }
        for (id,s) in storages {try check(s.capacity>=0 && s.capacity<=1_000_000_000_000 && s.incoming>=0 && volume(at:id)+s.incoming<=s.capacity,"\(id)仓储超额")}
        for r in LifeResource.allCases {try check(initial[r.rawValue,default:0]+produced[r.rawValue,default:0]-consumed[r.rawValue,default:0]==amount(r),"\(r.title)来源/消费不守恒")}
        var workers=Set<String>();var reserved:[String:Int64]=[:]
        for (id,t) in tasks {
            try check(t.id==id && t.step>=0 && t.step<t.steps.count && t.due>=time && t.started<=time,"任务时点错误")
            try check(agents[t.worker]?.taskID==id && workers.insert(t.worker).inserted,"工人重复占用或失联")
            try check(t.steps.allSatisfy{$0.seconds>0 && $0.seconds<31_536_000},"无效阶段时长")
            for p in t.reservations {reserved[p.lotID,default:0]+=p.amount}
        }
        for a in agents.values {if let id=a.taskID {try check(tasks[id]?.worker==a.id,"人物关联错误")};try check(LifeMap.places[a.node] != nil,"人物位置无效")}
        for lot in lots.values {try check(lot.reserved==reserved[lot.id,default:0],"资源预留不是唯一任务占用")}
        for meal in meals {try check(Set(meal.expected).count==meal.expected.count && Set(meal.served.keys).isSubset(of:Set(meal.expected)),"餐次消费者错误")}
        try check(Set(owned).count==owned.count && Set(discovered).count==discovered.count,"收藏身份重复")
    }
}
