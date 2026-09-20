import Foundation
import SanguoPresentation

private struct PreviewActor: Codable {
    let id: String, motion: String
    let x: Double, y: Double, z: Double
    let transforms: [String: [Double]]
    let hidden: [String]
}
@main
struct Preview {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let destination = URL(fileURLWithPath:args.first ?? "dist/animation-preview",isDirectory:true)
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        var director = TownDirector(); director.sync(.demo)
        let initial = TownArt.svg(director:director,includeHiddenParts:true).replacingOccurrences(of:" / t=0.000s",with:" / SHARED SWIFT POSE DATA")
        var frames: [[PreviewActor]] = []
        // 36 seconds at 10 preview FPS. The actual Mac adapter uses 30 FPS (15 in low-power mode).
        for index in 0..<360 {
            let item: HandItem = index < 180 ? .spear : .sword
            frames.append(director.actors.keys.sorted().compactMap { id in
                guard let a = director.actors[id] else { return nil }
                let pose = CharacterRig.pose(motion:a.motion,time:a.phaseTime,distance:a.distance,
                                            facing:a.facing,item:a.spec.costume == .warrior ? item : .none)
                return .init(id:id,motion:a.motion.rawValue,x:a.position.x,y:a.position.y,z:a.depth,
                    transforms:pose.transforms.mapValues { [$0.x,$0.y,$0.angle,$0.sx,$0.sy] },hidden:pose.hidden.sorted())
            })
            if args.contains("--frames") {
                try TownArt.svg(director:director,item:item).write(to:destination.appendingPathComponent(String(format:"frame-%03d.svg",index)),atomically:true,encoding:.utf8)
            }
            for _ in 0..<3 { director.tick(1.0/30) }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding:try encoder.encode(frames),as:UTF8.self)
        let html = """
        <!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>小城志 · 人物动作样板</title>
        <style>body{margin:0;background:#233e3a;color:#eee9d8;font:16px system-ui,sans-serif}main{max-width:1120px;margin:5vh auto;padding:24px}h1{font-size:32px;margin:8px 0}p{line-height:1.8;color:#c3d1c3}.tag{font-size:12px;letter-spacing:3px}svg{width:100%;height:auto;border-radius:14px;display:block}section{margin:20px 0}button{background:#dccda3;color:#203d38;border:0;border-radius:6px;padding:9px 18px;cursor:pointer}input{width:55%;vertical-align:middle;margin:0 16px}output{font-variant-numeric:tabular-nums}.note{font-size:13px}#status{min-height:28px}</style>
        <main><div class="tag">SANGUO TOWN / VISUAL-0.2</div><h1>会走路，也会做事的小城人物</h1>
        <p>文官、武将与工匠 · 行走 / 转身 / 读简 / 挥锤 / 耕作<br>前18秒试装长枪，后18秒换佩剑；工作时切换为工作工具。</p>
        <section id="scene">\(initial)</section><button id="play">暂停</button><input aria-label="动画进度" id="seek" type="range" min="0" max="359" value="0"><output id="time"></output>
        <p id="status"></p><p class="note">这不是M4实机录像：页面播放的是Swift共享骨架、姿态和道路状态机导出的帧数据。<br>Mac客户端使用同一份造型与姿态，通过SpriteKit绘制。此页无网络请求、不读取或修改游戏存档；在36秒处循环。</p></main>
        <script type="application/json" id="frames">\(json)</script>
        <script>
        'use strict';const frames=JSON.parse(document.getElementById('frames').textContent);
        const actors=new Map([...document.querySelectorAll('[data-actor]')].map(n=>[n.dataset.actor,{node:n,parts:new Map([...n.querySelectorAll('[data-part]')].map(p=>[p.dataset.part,p]))}]));
        const tree=document.querySelector('[data-part="tree"]');const parent=tree.parentNode;
        const seek=document.getElementById('seek'),button=document.getElementById('play');
        const reduce=matchMedia('(prefers-reduced-motion: reduce)').matches;let playing=!reduce,index=0,last=0,acc=0;
        function draw(){const row=frames[index],order=[{z:438,id:'tree',node:tree}];for(const a of row){const e=actors.get(a.id);e.node.setAttribute('transform',`translate(${a.x} ${a.y})`);for(const [id,v] of Object.entries(a.transforms)){e.parts.get(id).setAttribute('transform',`translate(${v[0]} ${v[1]}) rotate(${v[2]*180/Math.PI}) scale(${v[3]} ${v[4]})`);}for(const id of ['sword','spear','hammer','book','basket','hoe','axe']){e.parts.get(id).style.display=a.hidden.includes(id)?'none':'';}order.push({z:a.z,id:a.id,node:e.node});}order.sort((a,b)=>a.z-b.z||a.id.localeCompare(b.id));for(const o of order)parent.appendChild(o.node);seek.value=index;document.getElementById('time').textContent=(index/10).toFixed(1)+' / 36s';document.getElementById('status').textContent=row.map(a=>a.id.replace('demo-','')+': '+a.motion).join('　');}
        function animate(t){if(last&&playing&&!document.hidden){acc+=Math.min(t-last,100);if(acc>=100){index=(index+Math.floor(acc/100))%frames.length;acc%=100;draw();}}last=t;requestAnimationFrame(animate);}
        button.onclick=()=>{playing=!playing;button.textContent=playing?'暂停':'播放';};seek.oninput=()=>{index=Number(seek.value);draw();};
        document.addEventListener('visibilitychange',()=>{last=0;acc=0;});button.textContent=playing?'暂停':'播放';draw();requestAnimationFrame(animate);
        </script></html>
        """
        try html.write(to:destination.appendingPathComponent("animation-preview.html"),atomically:true,encoding:.utf8)
        let poses = Motion.allCases.enumerated().map { index, motion in
            let pose = CharacterRig.pose(motion:motion,time:0.45,distance:8,item:.sword)
            return "<g transform=\"translate(\(60+index*108) 105) scale(1.25 -1.25)\">" + SVG.node(CharacterRig.artwork(.warrior),overrides:pose.transforms,hidden:pose.hidden) + "</g><text x=\"\(22+index*108)\" y=\"140\" font-family=\"sans-serif\" font-size=\"13\">\(motion.rawValue)</text>"
        }.joined()
        let sheet = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"880\" height=\"160\"><rect width=\"880\" height=\"160\" fill=\"#EBE9D7\"/>\(poses)</svg>"
        try sheet.write(to:destination.appendingPathComponent("poses.svg"),atomically:true,encoding:.utf8)
        print("Exported animation-preview.html and poses.svg; 360 deterministic recorded pose frames. Not an M4 screenshot.")
    }
}
