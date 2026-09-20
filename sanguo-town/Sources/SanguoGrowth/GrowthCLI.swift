import Foundation
import SanguoCore
import SanguoPresentation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

@main
struct GrowthCLI {
    static func seed(_ policy:Policy,legion:Int,town:Bool = false) throws -> WorldState {
        var w=GrowthRuntime.newGame(wallUTC:0)
        try GameEngine.apply(.init(id:"governance",expectedRevision:w.revision,action:town ? .realm(.adopt(policy:policy,investment:.balanced)) : .acceptDevelopment(policy:policy,investment:.balanced)),to:&w)
        if legion>0 { try GameEngine.apply(.init(id:"army",expectedRevision:w.revision,action:.authorizeLegion(cityID:"plain",capacity:legion,budget:Int64(legion)*12)),to:&w) }
        return w
    }
    static func advance(_ world:inout WorldState,days:Int,cadence:Int) throws {
        let end=Int64(days)*86_400
        while world.lastWallUTC<end {
            try GameEngine.advance(to:min(end,world.lastWallUTC+Int64(cadence)*86_400),world:&world)
        }
    }
    static func main() {
        do { try run() }
        catch { FileHandle.standardError.write(Data("Growth CLI failed: \(error)\n".utf8));exit(1) }
    }
    static func run() throws {
        var policy=Policy.balanced,days=30,cadence=3,legion=0,path="dist/growth-preview",matrix=false,town=false
        var args=Array(CommandLine.arguments.dropFirst())
        while !args.isEmpty {
            let flag=args.removeFirst()
            if flag=="--town" { town=true;continue }
            if flag=="--matrix" { matrix=true;continue }
            if flag=="--help" {
                print("SanguoGrowth [--policy supply|trade|industry|military|balanced] [--days 1...90] [--cadence 1...30] [--legion 0|30|60|90] [--output DIR] [--matrix] [--town]")
                return
            }
            guard !args.isEmpty else { throw GameError.invalid("缺少\(flag)参数") }
            let value=args.removeFirst()
            switch flag {
            case "--policy": guard let p=Policy(rawValue:value) else { throw GameError.invalid("policy") };policy=p
            case "--days": guard let d=Int(value),(1...90).contains(d) else { throw GameError.invalid("days") };days=d
            case "--cadence": guard let c=Int(value),(1...30).contains(c) else { throw GameError.invalid("cadence") };cadence=c
            case "--legion": guard let n=Int(value),[0,30,60,90].contains(n) else { throw GameError.invalid("legion") };legion=n
            case "--output": path=value
            default:throw GameError.invalid("未知参数：\(flag)")
            }
        }
        let out=URL(fileURLWithPath:path,isDirectory:true)
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        if matrix { try runMatrix(out,town:town);return }
        var w=try seed(policy,legion:legion,town:town)
        var snapshots:[(String,CityAppearanceSnapshot)]=[("刚刚定策",w.appearance(cityID:"plain")!)]
        try GameEngine.advance(to:300,world:&w)
        snapshots.append(("五分钟：第一处修缮",w.appearance(cityID:"plain")!))
        for d in [1,7,30,60,90] where d<=days {
            try advance(&w,days:d,cadence:cadence)
            snapshots.append(("第\(d)成长日",w.appearance(cityID:"plain")!))
        }
        if w.lastWallUTC<Int64(days)*86_400 { try advance(&w,days:days,cadence:cadence) }
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
        try encoder.encode(w).write(to:out.appendingPathComponent("simulated-world.json"))
        var sections=""
        for (index,entry) in snapshots.enumerated() {
            let svg=GrowthTownArt.svg(entry.1)
            try svg.write(to:out.appendingPathComponent("city-\(index).svg"),atomically:true,encoding:.utf8)
            sections += "<section><h2>\(SVG.escape(entry.0))</h2><p>实际人口 \(entry.1.population) / 住房 \(entry.1.housing)　已建建筑 \(entry.1.buildings.filter(\.isOperating).count)　军团现役 \(entry.1.legionActive)/\(entry.1.legionCapacity)　街区改善 \(entry.1.civic?.levelTotal ?? 0)</p>\(svg)</section>"
        }
        let html="""
        <!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>小城志 · 真实模拟的城池成长</title>
        <style>body{background:#edf0e4;color:#263c36;margin:0;font:16px system-ui,sans-serif}main{max-width:1180px;padding:32px;margin:auto}h1{font-size:32px}p{line-height:1.8}section{margin:28px 0;background:#f8f7ee;padding:18px;border-radius:12px}svg{width:100%;height:auto;display:block}h2{font-size:20px}</style>
        <main><h1>\(policy.title)：城池一点点长出来</h1><p>\(town ? "town-0.4" : "growth-0.3") 开发切片。以下是同一存档按真实Swift规则加速运行的状态，不是概念图、不是M4录像，也不证明90天内容已平衡。只在开局定策\(legion>0 ? "并批准军团上限" : "")，之后没有逐项点击建设；按\(cadence)天一看推进。普通工程、入住与整军已接入；启用town模式后增加八类街区分阶段改善。此预览不宣称完整战斗、全量物流或90天可玩性已经验收。</p>
        \(sections)
        <p>固定同一视角；房屋、施工阶段、库存档位与营地来自各时点状态。矢量美术仍是可替换的开发素材。</p></main></html>
        """
        try html.write(to:out.appendingPathComponent("city-growth.html"),atomically:true,encoding:.utf8)
        print("\(policy.rawValue) \(days)d: \(w.growth!.cities["plain"]!.completedCount) construction completions, population \(w.cities["plain"]!.population), army \(w.growth!.legion?.active ?? 0), civic \(w.realm?.civicCount ?? 0), treasury \(w.treasury). Real state snapshots exported; not a native GUI recording.")
    }
    struct MatrixRow:Codable {
        let policy:String,days:Int,cadenceDays:Int
        let seconds:Double,population:Int,projects:Int,buildings:Int,army:Int,treasury:Int64,proposals:Int
        let equalToDaily:Bool
        let civic:Int
    }
    static func runMatrix(_ out:URL,town:Bool) throws {
        var rows:[MatrixRow]=[]
        let started=Date()
        for policy in Policy.allCases {
            var references:[Int:WorldState]=[:]
            for cadence in [1,3,7] {
                var w=try seed(policy,legion:60,town:town)
                for day in [30,60,90] {
                    let begin=Date()
                    try advance(&w,days:day,cadence:cadence)
                    if cadence==1 { references[day]=w }
                    let equal=references[day]==w
                    guard equal else { throw GameError.invalid("\(policy.rawValue) \(day)日 查看频率改变状态") }
                    try w.validate()
                    rows.append(.init(policy:policy.rawValue,days:day,cadenceDays:cadence,seconds:Date().timeIntervalSince(begin),
                        population:w.cities["plain"]!.population,projects:w.growth!.cities["plain"]!.completedCount,
                        buildings:w.growth!.cities["plain"]!.buildings.filter(\.isOperating).count,army:w.growth!.legion?.active ?? 0,
                        treasury:w.treasury,proposals:w.growth!.proposals.count,equalToDaily:equal,civic:w.realm?.civicCount ?? 0))
                }
            }
        }
        struct Report:Codable { let version:String;let scope:String;let rowCount:Int;let elapsedSeconds:Double;let rows:[MatrixRow] }
        let report=Report(version:town ? RealmRules.version : GrowthRules.version,scope:"runtime simulation of the finite single-city slice; not playtesting or full PRD acceptance",rowCount:rows.count,elapsedSeconds:Date().timeIntervalSince(started),rows:rows)
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(report).write(to:out.appendingPathComponent("growth-matrix.json"))
        print("PASS \(rows.count) checkpoints: 5 policies × 3 viewing cadences × 30/60/90 days. \(String(format:"%.3f",report.elapsedSeconds))s. States match exactly; this is not proof of long-term fun/balance.")
    }
}
