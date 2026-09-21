import Foundation
import SanguoLife
import SanguoLifeVisual
@main struct LifeCLI {
    static func main() throws {
        let args=Array(CommandLine.arguments.dropFirst())
        func value(_ name:String)->String? {guard let i=args.firstIndex(of:name),i+1<args.count else{return nil};return args[i+1]}
        let seconds=Int64(value("--seconds") ?? "7200") ?? 7200
        let cadence=Int64(value("--cadence") ?? "30") ?? 30
        guard seconds>=0,seconds<=2_592_000,cadence>0 else{throw LifeError.invalid("--seconds必须0..2592000，--cadence必须正数")}
        let c=try LifeCatalog.bundled();var engine=try LifeRuntime(catalog:c,wallUTC:0)
        if args.contains("--husbandry"){try engine.setHusbandry(enabled:true)}
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
        if let h=w.husbandry {print("养殖：购入\(h.purchasedTotal)，出栏\(h.processedTotal)，现存\(h.pigs.count)，肉食饭消费\(w.counters["hearty_meals_consumed",default:0])；\(h.status)")}
        print("项目：\(w.projects.values.sorted{$0.id<$1.id}.map{"\($0.id) \($0.completedWork)/\($0.totalWork)"})")
        print(w.records.suffix(10).map{"\($0.time): \($0.text)"}.joined(separator:"\n"))
        if let out=value("--output") {
            let dir=URL(fileURLWithPath:out,isDirectory:true);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            try encoder.encode(w).write(to:dir.appendingPathComponent("world.json"),options:.atomic)
            if args.contains("--trace"){try encoder.encode(samples).write(to:dir.appendingPathComponent("trace.json"),options:.atomic)}
            if args.contains("--preview") {if args.contains("--husbandry") {try HusbandryPreview.export(catalog:c,to:dir)} else {try preview(catalog:c,to:dir)}}
        }
    }
    static func preview(catalog:LifeCatalog,to dir:URL) throws {
        struct Frame:Encodable {let time:Int64;let svg:String;let summary:String}
        var e=try LifeRuntime(catalog:catalog,wallUTC:0);try e.requestSeal()
        let times:Array<Int64> = [0,240]+Array(stride(from:360,through:440,by:10))+[600,720,900,1200,1980,2400,2880,3600,7200,14400,28800,86400]
        var frames:[Frame]=[]
        for t in times {try e.advance(to:t);let w=e.world;frames.append(.init(time:t,svg:LifeVisual.svg(w),summary:"人口\(w.agents.count) · 实际收割\(w.counters["harvests",default:0])次 · 搬运\(w.counters["deliveries",default:0])次 · 已用餐\(w.counters["resident_meals_consumed",default:0])份 · 木印\(w.owned.contains("founders_seal") ? "已入藏":"制作中")"))}
        let data=try JSONEncoder().encode(frames)
        let json=String(decoding:data,as:UTF8.self).replacingOccurrences(of:"</",with:"<\\/")
        let html="""
        <!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>小城志 · 实际任务回放</title><style>*{box-sizing:border-box}body{margin:0;background:#253934;color:#f4ecd5;font:15px system-ui,-apple-system,'PingFang SC',sans-serif}header{padding:16px 24px}h1{font-size:23px;margin:0 0 6px}p{margin:6px 0;opacity:.8}button,select,input{font:inherit}button{padding:8px 15px;margin:5px;border:1px solid #708878;border-radius:8px;background:#e8dfc4;color:#24392f}#scene{width:100%;max-height:75vh;overflow:hidden}svg{width:100%;height:75vh;display:block}footer{padding:12px 24px}input{width:55%;vertical-align:middle}#stats{margin-top:10px}</style><header><h1>小城志 · 真实生产与城市生活</h1><p>由Swift引擎同一存档运行并导出：不是概念图，不是M4实机录像。回放不会修改存档或发放资源。</p><button id="play">播放收割片段</button><button onclick="jump(0)">开局</button><button onclick="jump(900)">第一份成果</button><button onclick="jump(2400)">夜间</button><button onclick="jump(86400)">一天后</button><input id="slider" type="range" min="0" value="0"><span id="clock"></span></header><div id="scene"></div><footer><div id="stats"></div><p>本批为单城可玩切片：真实工人、八资源、供餐、基础施工、30将数据与招募入口。猪、完整軍团/多城/装备仍未接入。</p></footer><script>const frames=\(json);let i=0,timer=null;const s=document.getElementById('slider');s.max=frames.length-1;function show(){const f=frames[i];document.getElementById('scene').innerHTML=f.svg;document.getElementById('clock').textContent=`模拟 ${Math.floor(f.time/60)}分 ${f.time%60}秒`;document.getElementById('stats').textContent=f.summary;s.value=i}function stop(){clearInterval(timer);timer=null;document.getElementById('play').textContent='播放收割片段'}function jump(time){stop();i=frames.findIndex(f=>f.time===time);show()}s.oninput=()=>{stop();i=Number(s.value);show()};document.getElementById('play').onclick=()=>{if(timer){stop();return}i=2;show();document.getElementById('play').textContent='暂停';timer=setInterval(()=>{i++;if(frames[i].time>440){stop();return}show()},160)};show();</script></html>
        """
        try Data(html.utf8).write(to:dir.appendingPathComponent("life-preview.html"))
    }
}
