import Foundation
import SanguoLife
import SanguoLifeVisual

enum HusbandryPreview {
    struct Frame: Encodable { let time: Int64; let svg: String; let summary: String }
    static func export(catalog: LifeCatalog, to dir: URL) throws {
        var engine = try LifeRuntime(catalog: catalog, wallUTC: 0)
        try engine.requestSeal()
        try engine.setHusbandry(enabled: true)
        let times: [Int64] = [0,240,360,420,600,900,2400,7200,14400,21600,25200,28800,
                              32400,36000,43200,50400,57600,64800,72000,86400,129600,172800]
        var frames: [Frame] = []
        for t in times {
            try engine.advance(to: t)
            let w = engine.world, h = w.husbandry!
            frames.append(.init(time: t, svg: LifeVisual.svg(w),
                summary: "人口\(w.agents.count) · 购入\(h.purchasedTotal)头 · 出栏\(h.processedTotal)头 · 在养/在途\(h.pigs.count)头 · 实际吃到肉食饭\(w.counters["hearty_meals_consumed",default:0])份 · 近期供餐\(w.foodCoverage/100)%"))
        }
        let json = String(decoding: try JSONEncoder().encode(frames), as: UTF8.self)
            .replacingOccurrences(of: "</", with: "<\\/")
        let html = """
        <!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>小城志 · 肉食供应真实模拟回放</title>
        <style>*{box-sizing:border-box}body{margin:0;background:#263c36;color:#f2e9d2;font:15px system-ui,-apple-system,'PingFang SC',sans-serif}header,footer{padding:14px 22px}h1{font-size:24px;margin:0 0 8px}p{opacity:.8;margin:6px 0}button,input{font:inherit}button{background:#e6dec2;border:0;border-radius:6px;padding:8px 12px;margin:4px;cursor:pointer}#scene svg{display:block;width:100%;height:74vh}#slider{width:45%;vertical-align:middle}.small{font-size:13px}#summary{font-size:17px}</style>
        <header><h1>从牧栏到居民的一餐饭</h1><p>同一Swift存档运行后导出；不是概念图、不是Mac实机录像，也不是浏览器在修改游戏资源。</p>
        <button onclick="jump(0)">开局</button><button onclick="jump(2400)">夜巡</button><button onclick="jump(64800)">养殖运行</button><button onclick="jump(86400)">一天后</button><button onclick="jump(172800)">两天后</button><button id="play">播放阶段</button>
        <input type="range" id="slider" min="0" value="0"><span id="clock"></span></header>
        <div id="scene"></div><footer><div id="summary"></div><p class="small">牧栏在城西、肉食台在其北侧；幼猪要有人牵入，成熟后有人牵往加工点。没看到猪可能是尚未建成、商旅在途或正在院内加工，不补假动物。</p><p class="small">回放中的时点间隔并不相等。正式游戏照现实累计时间运行，动画暂停不影响任务。完整军团、多城与名器仍未在本批完成。</p></footer>
        <script>const frames=\(json);let i=0,timer=null;const s=document.getElementById('slider');s.max=frames.length-1;function show(){let f=frames[i];document.getElementById('scene').innerHTML=f.svg;document.getElementById('clock').textContent='模拟 '+Math.floor(f.time/3600)+'时'+Math.floor(f.time%3600/60)+'分';document.getElementById('summary').textContent=f.summary;s.value=i}function stop(){clearInterval(timer);timer=null;document.getElementById('play').textContent='播放阶段'}function jump(t){stop();i=frames.findIndex(f=>f.time===t);show()}s.oninput=()=>{stop();i=Number(s.value);show()};document.getElementById('play').onclick=()=>{if(timer){stop();return}if(i===frames.length-1)i=0;show();document.getElementById('play').textContent='暂停';timer=setInterval(()=>{if(i===frames.length-1){stop();return}i++;show()},1300)};show();</script></html>
        """
        try Data(html.utf8).write(to: dir.appendingPathComponent("husbandry-preview.html"))
    }
}
