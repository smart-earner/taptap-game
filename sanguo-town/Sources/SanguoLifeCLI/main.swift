import Foundation
import SanguoLifeCore

@main
struct LifeCLI {
    static func main() throws {
        let args=Array(CommandLine.arguments.dropFirst())
        func value(_ key:String,_ fallback:String)->String { guard let i=args.firstIndex(of:key),i+1<args.count else{return fallback};return args[i+1] }
        let hours=Double(value("--hours","6")) ?? -1
        guard hours>=0,hours<=2160 else {throw LifeError.invalid("--hours范围0...2160")}
        let step=Int64(value("--step","3600")) ?? 0
        guard step>0 else {throw LifeError.invalid("--step必须大于0")}
        let rules=try LifeRules.load();var state=try LifeEngine.newGame(wallUTC:0,rules:rules)
        let end=Int64(hours*3600)
        while state.time<end {try LifeEngine.advance(&state,to:min(end,state.time+step),rules:rules)}
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        if args.contains("--state") {print(String(decoding:try encoder.encode(state),as:UTF8.self))}
        else {print(String(decoding:try encoder.encode(Summary(state)),as:UTF8.self))}
    }
    struct Summary:Encodable {
        let time:Int64;let population,satisfaction,housing,treasury,served,completedTasks:Int
        let stocks,produced,consumed:[String:Int];let achievements:[String]
        init(_ s:LifeState) {time=s.time;population=s.population;satisfaction=s.satisfaction;housing=s.housing;treasury=s.treasury;served=s.totalServed;completedTasks=s.completedTasks;achievements=s.achievements;produced=s.ledger.produced;consumed=s.ledger.consumed;stocks=Dictionary(uniqueKeysWithValues:s.ledger.initial.keys.union(s.ledger.produced.keys).map{($0,s.total($0))})}
    }
}

extension Dictionary.Keys where Key==String,Value==Int {func union(_ other:Self)->Set<String> {Set(self).union(other)}}
