import Foundation
import SanguoLife
import SanguoLifeVisual

@main struct LifeCLI {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        func value(_ name: String) -> String? {
            guard let i = args.firstIndex(of:name), i+1 < args.count else { return nil }
            return args[i+1]
        }
        guard let seconds = Int64(value("--seconds") ?? "7200"),
              let cadence = Int64(value("--cadence") ?? "30"),
              seconds >= 0, seconds <= 2_592_000, cadence > 0 else {
            throw LifeError.invalid("--seconds必须0..2592000，--cadence必须正数")
        }
        let catalog = try LifeCatalog.bundled()
        var engine = try LifeRuntime(catalog:catalog,wallUTC:0)
        let policy = value("--policy") ?? "supply"
        try engine.setPolicy(policy)
        let herd = Int(value("--herd") ?? "2")
        let budget = Int64(value("--purchase-limit") ?? "40")
        if args.contains("--husbandry") {
            guard let herd, let budget else { throw LifeError.invalid("养殖参数必须为整数") }
            try engine.authorizeHusbandry(herdTarget:herd,purchaseLimit:budget)
        } else if value("--herd") != nil || value("--purchase-limit") != nil {
            throw LifeError.invalid("养殖参数需要显式传入--husbandry")
        }
        if args.contains("--seal") { try engine.requestSeal() }
        var samples: [LifeWorld] = [engine.world]
        while engine.world.time < seconds {
            try engine.advance(to:min(seconds,engine.world.time+cadence))
            if args.contains("--trace") { samples.append(engine.world) }
        }
        let w = engine.world, food = LifeFoodStatus(world:w)
        print("规则\(w.rules)，模拟\(seconds)秒，人口\(w.agents.count)，满意\(w.happiness)，供餐\(w.foodCoverage)/10000")
        print("真实收割\(w.counters["harvests",default:0])次，搬运\(w.counters["deliveries",default:0])次，已消费\(food.mealsConsumed)餐；发现\(w.discovered.count)/30将；拥有\(w.owned)")
        if w.husbandry != nil {
            print("养殖：在途\(food.pigsInTransit)，城门待接\(food.pigsAtGate)，城内\(food.pigsInCity)，已出栏\(food.pigsProcessed)；实际肉食用餐\(food.heartyMealsConsumed)/\(food.mealsConsumed)；本期采购\(food.purchaseSpent)/\(food.purchaseLimit)铜")
            print(food.reason)
        }
        for r in LifeResource.allCases { print("\(r.title)：\(w.amount(r))mU；生产\(w.produced[r.rawValue,default:0])，消费\(w.consumed[r.rawValue,default:0])") }
        print("国库\(w.treasury)；预留\(w.reservedCash)；建筑\(w.buildings)")
        print(w.records.suffix(10).map { "\($0.time): \($0.text)" }.joined(separator:"\n"))
        if let out = value("--output") {
            let dir = URL(fileURLWithPath:out,isDirectory:true)
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(w).write(to:dir.appendingPathComponent("world.json"),options:.atomic)
            try encoder.encode(food).write(to:dir.appendingPathComponent("food-status.json"),options:.atomic)
            if args.contains("--trace") { try encoder.encode(samples).write(to:dir.appendingPathComponent("trace.json"),options:.atomic) }
            if args.contains("--preview") {
                try LifePreview.export(catalog:catalog,to:dir,husbandry:args.contains("--husbandry"),policy:policy,herd:herd ?? 2,budget:budget ?? 40)
            }
        }
    }
}
