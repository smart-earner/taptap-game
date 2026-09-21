import Foundation
import SanguoLife
@main struct LifeCLI {
    static func main() throws {
        let args=Array(CommandLine.arguments.dropFirst())
        func value(_ name:String)->String? {guard let i=args.firstIndex(of:name),i+1<args.count else{return nil};return args[i+1]}
        let seconds=Int64(value("--seconds") ?? "7200") ?? 7200
        let cadence=Int64(value("--cadence") ?? "30") ?? 30
        guard seconds>=0,seconds<=2_592_000,cadence>0 else{throw LifeError.invalid("--seconds必须0..2592000，--cadence必须正数")}
        let c=try LifeCatalog.bundled();var engine=try LifeRuntime(catalog:c,wallUTC:0)
        if args.contains("--seal"){try engine.requestSeal()}
        var samples:[LifeWorld]=[engine.world]
        while engine.world.time<seconds {
            let target=min(seconds,engine.world.time+cadence);try engine.advance(to:target)
            if args.contains("--trace") {samples.append(engine.world)}
        }
        let w=engine.world
        print("规则\(w.rules)，模拟\(seconds)秒，人口\(w.agents.count)，满意\(w.happiness)，供餐\(w.foodCoverage)/10000")
        print("真实收割\(w.counters["harvests",default:0])次，搬运\(w.counters["deliveries",default:0])次，已消费\(w.counters["resident_meals_consumed",default:0])餐；发现\(w.discovered.count)/30将；拥有\(w.owned)")
        for r in LifeResource.allCases {print("\(r.title)：\(w.amount(r))mU；生产\(w.produced[r.rawValue,default:0])，消费\(w.consumed[r.rawValue,default:0])")}
        print("项目：\(w.projects.values.sorted{$0.id<$1.id}.map{"\($0.id) \($0.completedWork)/\($0.totalWork)"})")
        print(w.records.suffix(10).map{"\($0.time): \($0.text)"}.joined(separator:"\n"))
        if let out=value("--output") {
            let dir=URL(fileURLWithPath:out,isDirectory:true);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            try encoder.encode(w).write(to:dir.appendingPathComponent("world.json"),options:.atomic)
            if args.contains("--trace"){try encoder.encode(samples).write(to:dir.appendingPathComponent("trace.json"),options:.atomic)}
        }
    }
}
