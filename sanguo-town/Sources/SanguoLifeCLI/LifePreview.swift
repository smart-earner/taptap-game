import Foundation
import SanguoLife
import SanguoLifeVisual

/// Actual-state samples. Preview controls only select previously computed frames.
enum LifePreview {
    struct Frame: Encodable { let time:Int64; let title:String; let svg:String; let summary:String }
    static func export(catalog:LifeCatalog,to dir:URL,husbandry:Bool,policy:String,herd:Int,budget:Int64) throws {
        var e = try LifeRuntime(catalog:catalog,wallUTC:0)
        try e.setPolicy(policy); try e.requestSeal()
        if husbandry { try e.authorizeHusbandry(herdTarget:herd,purchaseLimit:budget) }
        var frames:[Frame] = [], seen=Set<String>()
        func append(_ title:String) {
            let w=e.world,s=LifeFoodStatus(world:w)
            frames.append(.init(time:w.time,title:title,svg:LifeLiveVisual.svg(w),summary:"人口\(w.agents.count) · 出栏\(s.pigsProcessed) · 肉料累计\(s.meatProduced/1000) · 实际肉食用餐\(s.heartyMealsConsumed)份 · 近期供餐\(w.foodCoverage/100)% · 满意\(w.happiness)"))
        }
        append("开局：先保供，再改善")
        for t in stride(from:Int64(10),through:86400,by:10) {
            try e.advance(to:t)
            var title:String?
            if [900,2400,28800,86400].contains(t) { title=t==2400 ? "夜间：居民休息，巡兵守夜":"模拟\(t/60)分钟" }
            if husbandry {
                for p in e.world.projects.values.sorted(by:{$0.id<$1.id}) where ["pasture","butcher"].contains(p.kind) {
                    let key="project-\(p.kind)-\(p.phase)"
                    if seen.insert(key).inserted { title="\(e.buildingName(p.kind)) · \(p.completed ? "建成":"施工第\(p.phase+1)阶段")" }
                }
                for pig in (e.world.husbandry?.animals.values.sorted(by:{$0.id<$1.id}) ?? []) {
                    let key="pig-\(pig.stage.rawValue)-\(pig.stage == .growing ? pig.completedSegments : 0)"
                    if seen.insert(key).inserted { title="\(pig.stage.title) · 已成长\(pig.completedSegments)段" }
                }
                if e.world.counters["hearty_meals_consumed",default:0]>0 && seen.insert("first-hearty").inserted {title="居民第一次实际吃到肉食饭"}
            }
            if let title,frames.count<32 || t==86400 { append(title) }
        }
        let json=String(decoding:try JSONEncoder().encode(frames),as:UTF8.self).replacingOccurrences(of:"</",with:"<\\/")
        let html="""
        <!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>小城志 · 饭食改善实际回放</title><style>*{box-sizing:border-box}body{margin:0;background:#233a32;color:#efe8d2;font:15px system-ui,-apple-system,'PingFang SC',sans-serif}header,footer{padding:14px 24px}h1{font-size:23px;margin:0 0 8px}p{line-height:1.6;margin:6px 0;opacity:.8}button,select,input{font:inherit}button,select{padding:8px 12px;border-radius:7px;border:1px solid #a0b4a3;margin:4px;background:#eee3c6;color:#263d31}#scene svg{width:100%;height:68vh;display:block}#title{font-size:18px}input{width:55%;vertical-align:middle}</style><header><h1>小城志 · 真实养殖与饭食改善</h1><p>Swift同一存档的实际采样：牧栏建设、幼猪到货、牵引、饲喂、成长、出栏、肉饭和消费。不是真实Mac录像，不补发任何资源。</p><button id="play">播放阶段回顾</button><select id="stages" aria-label="回放节点"></select><input id="slider" type="range" min="0" value="0" aria-label="回放进度"><span id="clock"></span><h2 id="title"></h2></header><div id="scene"></div><footer><div id="stats"></div><p>这是采样时点回放，不是可操作游戏。幼猪只有付款到货后才出现；进入院内加工时不再显示活猪。本预览使用独立模拟，不读取或修改你的存档。</p></footer><script>const frames=\(json);let i=0,timer=null;const slider=document.getElementById('slider'),stages=document.getElementById('stages');slider.max=frames.length-1;frames.forEach((f,j)=>{const o=document.createElement('option');o.value=j;o.textContent=f.title;stages.append(o)});function show(){const f=frames[i];document.getElementById('scene').innerHTML=f.svg;document.getElementById('title').textContent=f.title;document.getElementById('clock').textContent=`模拟 ${Math.floor(f.time/3600)}小时 ${Math.floor(f.time%3600/60)}分`;document.getElementById('stats').textContent=f.summary;slider.value=i;stages.value=i}function stop(){clearInterval(timer);timer=null;document.getElementById('play').textContent='播放阶段回顾'}slider.oninput=()=>{stop();i=Number(slider.value);show()};stages.onchange=()=>{stop();i=Number(stages.value);show()};document.getElementById('play').onclick=()=>{if(timer){stop();return}if(i===frames.length-1)i=0;show();document.getElementById('play').textContent='暂停';timer=setInterval(()=>{if(++i>=frames.length){i=frames.length-1;stop()}show()},1200)};show();</script></html>
        """
        try Data(html.utf8).write(to:dir.appendingPathComponent("life-preview.html"),options:.atomic)
        try JSONEncoder().encode(frames).write(to:dir.appendingPathComponent("preview-frames.json"),options:.atomic)
    }
}
