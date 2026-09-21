import SwiftUI
import SanguoLife
import SanguoLifeVisual

@MainActor
struct GoldTownView:View {
    @ObservedObject private var model=LifeModel.shared
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var page=0
    @State private var selected="xunyu"
    @State private var reveal=false
    @State private var confirmation=false
    @State private var resourcesPresented=false
    @State private var showLabels=false
    @State private var pending:LifeGachaAction?
    @State private var confirmationText=""
    private let gold=TownPalette.gold
    private let titles=["小城春秋","酒馆招贤","武将名册","城中纪事"]
    private let subtitles=["一城烟火，各有所忙。","温一壶酒，静候同路人。","相逢是缘，共事成章。","把寻常日子，慢慢写成故事。"]
    var body:some View {
        HStack(spacing:0) {
            navigation
            VStack(spacing:0) {
                header
                if let w=model.world,let g=w.gacha,let d=model.definition {
                    resourceBar(w,g)
                    if let error=model.error {
                        Label(error,systemImage:"exclamationmark.circle").font(.callout).foregroundStyle(.red)
                            .textSelection(.enabled).padding(10)
                    }
                    Group {
                        if page==0 {town(w,g)}
                        else if page==1 {tavern(w,g,d)}
                        else if page==2 {cultivation(w,g,d)}
                        else {chronicle(w)}
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                    HStack(spacing:8) {
                        Image(systemName:"leaf")
                        Text(w.records.last?.text ?? "采集、冶炼与生活，都由太守安排。").lineLimit(1)
                        Spacer()
                        Text("原生试玩 · 视觉改版").fixedSize()
                    }.font(.system(size:10)).foregroundStyle(TownPalette.muted).padding(.horizontal,24).padding(.vertical,12)
                } else {
                    Spacer()
                    if let error=model.error {Text(error).foregroundStyle(.red).padding()}
                    else {ProgressView("正在开启小城…")}
                    Spacer()
                }
            }
        }
        .background(TownPalette.paper).foregroundStyle(TownPalette.ink)
        .tint(TownPalette.jade).preferredColorScheme(.light)
        .buttonStyle(TownButtonStyle())
        .frame(minWidth:1120,minHeight:740).task{await model.restore()}
        .confirmationDialog("确认培养操作",isPresented:$confirmation,titleVisibility:.visible) {
            Button("确认"){if let pending {submit(pending)}}
            Button("取消",role:.cancel){}
        } message:{Text(confirmationText)}
        .sheet(isPresented:$reveal) {revealSheet}
    }
    private var navigation:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(alignment:.top,spacing:10) {
                Text("志").font(.custom("Songti SC",size:26)).foregroundStyle(TownPalette.card)
                    .frame(width:42,height:48).background(TownPalette.jade,in:RoundedRectangle(cornerRadius:8))
                VStack(alignment:.leading,spacing:5) {
                    Text("小城志").font(.custom("Songti SC",size:24).weight(.bold))
                    Text("三 国 · 烟 火 人 间").font(.system(size:8)).tracking(1).foregroundStyle(TownPalette.muted)
                }
            }.padding(.bottom,42)
            Text("我的城池").font(.system(size:10,weight:.medium)).foregroundStyle(TownPalette.muted).padding(.bottom,14)
            ForEach(0..<4,id:\.self) {index in
                Button {page=index} label:{
                    HStack(spacing:12) {
                        Image(systemName:["map","cup.and.saucer","person.crop.rectangle.stack","text.book.closed"][index]).frame(width:20)
                        Text(["看看小城","酒馆招募","武将培养","城务记录"][index])
                        Spacer()
                        if page==index {Circle().fill(TownPalette.gold).frame(width:5,height:5)}
                    }.font(.system(size:13,weight:page==index ? .semibold:.regular))
                        .padding(.horizontal,14).padding(.vertical,15)
                        .foregroundStyle(page==index ? TownPalette.jade:TownPalette.muted)
                        .background(page==index ? TownPalette.jade.opacity(0.09):.clear,in:RoundedRectangle(cornerRadius:11))
                }.buttonStyle(.plain).padding(.bottom,6)
            }
            Spacer()
            Divider().overlay(TownPalette.line).padding(.bottom,18)
            Text("你来招贤与培养\n余下的，交给太守。")
                .font(.custom("Songti SC",size:14)).lineSpacing(7).foregroundStyle(TownPalette.muted)
            Text("无须领取 · 自在生活").font(.system(size:9)).foregroundStyle(TownPalette.muted).padding(.top,18)
        }.padding(.horizontal,20).padding(.vertical,30).frame(width:202)
            .background(TownPalette.card.opacity(0.65))
            .overlay(alignment:.trailing){Rectangle().fill(TownPalette.line).frame(width:1)}
    }
    private var header:some View {
        HStack(alignment:.center) {
            VStack(alignment:.leading,spacing:5) {
                Text(titles[page]).font(.custom("Songti SC",size:30).weight(.bold))
                Text(subtitles[page]).font(.system(size:12)).foregroundStyle(TownPalette.muted)
            }
            Spacer()
            if let w=model.world {
                Label(w.isNight ? "灯火可亲":"风和日暖",systemImage:w.isNight ? "moon.stars":"sun.max")
                    .font(.system(size:12)).foregroundStyle(TownPalette.muted)
                Text("第 \(w.cycle+1) 日").font(.system(size:12,weight:.medium))
                    .padding(.leading,10)
            }
        }.padding(.horizontal,26).padding(.top,24).padding(.bottom,14)
    }
    private func resourceBar(_ w:LifeWorld,_ g:LifeGachaState)->some View {
        HStack(spacing:18) {
            Label("\(w.treasury) 金币",systemImage:"circle.hexagongrid.fill").foregroundStyle(gold).monospacedDigit()
            Text("\(g.souls) 将魂").monospacedDigit()
            Button {resourcesPresented.toggle()} label:{Label("物资说明",systemImage:"info.circle")}
                .buttonStyle(.plain).help("查看实际库存与金币来源")
                .popover(isPresented:$resourcesPresented,arrowEdge:.bottom){resourceNote(w,g)}
            Spacer()
            Text("\(g.stars.count) 位武将 · 太守理城")
        }.font(.system(size:11)).foregroundStyle(TownPalette.muted)
            .padding(.horizontal,26).padding(.bottom,18)
    }
    private func town(_ w:LifeWorld,_ g:LifeGachaState)->some View {
        HStack(alignment:.top,spacing:16) {
            VStack(spacing:0) {
                HStack {
                    Label(w.isNight ? "一城灯火":"山水之间 · 小城人家",systemImage:"mountain.2")
                        .font(.custom("Songti SC",size:16))
                    Spacer()
                    Toggle("地名",isOn:$showLabels).toggleStyle(.switch).controlSize(.mini)
                        .font(.system(size:10)).fixedSize()
                }.padding(16)
                LifeCanvas(world:w,reducedMotion:reducedMotion,onSelect:{selected=$0;page=2},showLabels:showLabels)
                    .clipShape(RoundedRectangle(cornerRadius:14))
                    .padding(.horizontal,10)
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                HStack {
                    Text("点选城中武将，看看他的近况。")
                    Spacer()
                    Text(w.isNight ? "入夜归家":"各安其职")
                }.font(.system(size:10)).foregroundStyle(TownPalette.muted).padding(16)
            }.background(TownPalette.card,in:RoundedRectangle(cornerRadius:20))
                .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(TownPalette.line,lineWidth:1))
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    TownCard {
                        VStack(alignment:.leading,spacing:12) {
                            Text("城中此刻").font(.custom("Songti SC",size:19).weight(.bold))
                            Text("各有所长，各有所忙").font(.system(size:10)).foregroundStyle(TownPalette.muted)
                            ForEach(w.agents.values.sorted{$0.id<$1.id}.prefix(5)) {a in
                                Button {selected=a.id;page=2} label:{
                                    HStack(spacing:10) {
                                        TownHeroPortrait(id:a.heroID ?? a.id).frame(width:40,height:48)
                                        VStack(alignment:.leading,spacing:4) {
                                            Text(LifeVisual.actor(a,world:w,at:Double(w.time)).action).font(.system(size:11,weight:.medium))
                                            Text(LifeVisual.jobNames[a.job] ?? a.job).font(.system(size:9)).foregroundStyle(TownPalette.muted)
                                        }
                                        Spacer(minLength:0)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                            if w.agents.count>5 {
                                Button("查看全部 \(w.agents.count) 位武将"){page=2}.font(.caption).buttonStyle(.plain)
                            }
                        }
                    }
                    let projects=w.projects.values.filter{!$0.completed}.sorted{$0.id<$1.id}
                    if !projects.isEmpty {
                        TownCard {
                            VStack(alignment:.leading,spacing:10) {
                                Label("小城在生长",systemImage:"hammer").font(.custom("Songti SC",size:16))
                                ForEach(projects){p in
                                    Text(p.kind=="repair" ? "修缮府署":(p.kind.hasPrefix("house") ? "营造新居":"完善工坊")).font(.caption)
                                    ProgressView(value:Double(p.completedWork),total:Double(max(1,p.totalWork))).tint(TownPalette.gold)
                                    Text("材料与施工，由太守安排").font(.system(size:9)).foregroundStyle(TownPalette.muted)
                                }
                            }
                        }
                    }
                    Button {page=1} label:{
                        HStack {Image(systemName:"cup.and.saucer");Text("去酒馆坐坐");Spacer();Image(systemName:"arrow.right")}
                    }.buttonStyle(TownButtonStyle(prominent:true))
                    DisclosureGroup("试玩时间") {
                        Button("推进60秒"){Task{await model.send(.previewStep)}}.disabled(model.busy)
                        Text("真实生产与消耗，不赠币。").font(.system(size:9)).foregroundStyle(TownPalette.muted)
                    }.font(.system(size:10)).foregroundStyle(TownPalette.muted).padding(.horizontal,8)
                }
            }.frame(width:238)
        }.padding(.horizontal,24)
    }
    private func tavern(_ w:LifeWorld,_ g:LifeGachaState,_ d:LifeGachaDefinition)->some View {
        ScrollView {
            VStack(spacing:22) {
                HStack(spacing:28) {
                    ZStack {
                        Circle().fill(TownPalette.gold.opacity(0.10)).frame(width:240,height:240)
                        TownVectorArt(art:LifeTownArt.building("tavern",at:.init(0,0),night:false,level:2),
                                      bounds:.init(x:-95,y:-25,width:200,height:190))
                            .frame(width:300,height:280)
                    }
                    VStack(alignment:.leading,spacing:14) {
                        Text("酒  逢  知  己").font(.system(size:10,weight:.medium)).tracking(4).foregroundStyle(gold)
                        Text("今日，可有故人来？").font(.custom("Songti SC",size:32).weight(.bold))
                        Text("初见，添一位城中人。\n重逢，留一张同名卡，由你培养。")
                            .font(.system(size:13)).lineSpacing(7).foregroundStyle(TownPalette.muted)
                        HStack(spacing:12) {
                            drawButton("请一位同路人",count:1,w:w,g:g,d:d)
                            drawButton("设一席招贤宴",count:10,w:w,g:g,d:d)
                        }.padding(.top,8)
                        if g.isComplete {Text("全员满星，招募已关闭。余卡与金币保留。").font(.caption)}
                        else if w.treasury<100 {Text("还差 \(100-w.treasury) 金币可招募一次，太守正在安排生产。").font(.caption).foregroundStyle(TownPalette.muted)}
                    }
                    Spacer(minLength:0)
                }.padding(24).frame(maxWidth:.infinity)
                    .background(TownPalette.card,in:RoundedRectangle(cornerRadius:22))
                TownCard {
                    HStack(spacing:24) {
                        VStack(alignment:.leading,spacing:10) {
                            Text(g.isComplete ? "常驻池已满星":"再 \(20-g.pity) 抽，必遇传奇")
                                .font(.custom("Songti SC",size:21).weight(.bold))
                            ProgressView(value:Double(g.pity),total:20).tint(gold).frame(width:210)
                            Text("传奇可能重复 · 重逢传奇也重置保底").font(.system(size:10)).foregroundStyle(TownPalette.muted)
                        }
                        Divider().frame(height:62)
                        VStack(alignment:.leading,spacing:8) {
                            Text("良才 70%     名士 25%     传奇 5%").font(.system(size:12,weight:.medium))
                            Text("基础概率；连续19次非传奇，第20次必为传奇。\n常驻30人池包含开局五将，不移除已拥有武将，无每日重置。")
                                .font(.system(size:10)).foregroundStyle(TownPalette.muted).lineSpacing(5)
                        }
                        Spacer()
                    }
                }
                if !g.lastDraws.isEmpty {Button("翻看上次来信"){reveal=true}}
                DisclosureGroup("常驻名册 · 查看全部30位武将") {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:130))],spacing:14) {
                        ForEach(d.heroes){h in
                            VStack(spacing:8) {
                                TownHeroPortrait(id:h.id).frame(height:120)
                                Text(h.name).font(.custom("Songti SC",size:17))
                                Text(rarityName(h.rarity)).font(.system(size:10)).foregroundStyle(rarityColor(h.rarity))
                            }.padding(10).background(TownPalette.card,in:RoundedRectangle(cornerRadius:14))
                        }
                    }.padding(.top,18)
                }.font(.system(size:12)).padding(.horizontal,6)
            }.padding(.horizontal,24).padding(.bottom,20)
        }
    }
    private func drawButton(_ title:String,count:Int,w:LifeWorld,g:LifeGachaState,d:LifeGachaDefinition)->some View {
        Button {
            Task {await model.send(.gacha(.init(action:.draw(count:count,pool:d.gacha.pool_version))));if model.error==nil {reveal=true}}
        } label:{
            VStack(spacing:7) {
                Text(title).font(.system(size:14,weight:.semibold))
                Text("\(count==1 ? "单抽":"十连") · \(count*100) 金币").font(.system(size:11))
            }.frame(minWidth:135).padding(.vertical,5)
        }.buttonStyle(TownButtonStyle(prominent:count==1))
            .disabled(model.busy || w.treasury<Int64(count*100) || g.isComplete)
    }
    private func cultivation(_ w:LifeWorld,_ g:LifeGachaState,_ d:LifeGachaDefinition)->some View {
        HStack(alignment:.top,spacing:20) {
            ScrollView {
                LazyVStack(spacing:10) {
                    ForEach(d.heroes.filter{g.stars[$0.id] != nil}){h in
                        Button{selected=h.id}label:{
                            HStack(spacing:12) {
                                TownHeroPortrait(id:h.id).frame(width:50,height:60)
                                VStack(alignment:.leading,spacing:6) {
                                    Text(h.name).font(.custom("Songti SC",size:17).weight(.bold))
                                    Text(String(repeating:"★",count:g.stars[h.id]!)).font(.system(size:9)).foregroundStyle(gold)
                                }
                                Spacer()
                            }.padding(10)
                                .background(selected==h.id ? TownPalette.jade.opacity(0.10):TownPalette.card,in:RoundedRectangle(cornerRadius:14))
                                .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(selected==h.id ? TownPalette.jade.opacity(0.35):.clear))
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(width:205)
            ScrollView {
                if let h=d.hero(selected),let star=g.stars[selected] {
                    VStack(alignment:.leading,spacing:18) {
                        TownCard {
                            HStack(spacing:24) {
                                TownHeroPortrait(id:h.id).frame(width:140,height:165)
                                VStack(alignment:.leading,spacing:12) {
                                    Text(rarityName(h.rarity)+" · "+profileName(h.star_profile)).font(.system(size:11)).foregroundStyle(rarityColor(h.rarity))
                                    Text(h.name).font(.custom("Songti SC",size:34).weight(.bold))
                                    Text(String(repeating:"★",count:star)).font(.system(size:15)).foregroundStyle(gold)
                                    Text(g.arrivals[h.id] != nil ? "正在赴城，培养结果会随他一同抵达。":
                                            (w.agents[h.id].map{LifeVisual.actor($0,world:w,at:Double(w.time)).action} ?? "在城中生活"))
                                        .font(.system(size:12)).foregroundStyle(TownPalette.muted)
                                }
                                Spacer(minLength:0)
                            }
                        }
                        TownCard {
                            VStack(alignment:.leading,spacing:15) {
                                Text("一技之长").font(.custom("Songti SC",size:21).weight(.bold))
                                HStack(spacing:10) {
                                    skillMark("职业专长","1星解锁 · 2星强化",unlocked:star>=1)
                                    skillMark("第二专长","3星解锁 · 4星强化",unlocked:star>=3)
                                    skillMark("招牌能力","5星解锁",unlocked:star>=5)
                                }
                                Text(signatureText(h.star_profile)).font(.system(size:12)).foregroundStyle(TownPalette.muted)
                                Divider()
                                if star<5 {
                                    let cost=d.cultivation.duplicate_cost_by_next_star[String(star+1)]!
                                    HStack {
                                        VStack(alignment:.leading,spacing:5) {
                                            Text("下一星 · \(cost) 张同名卡").font(.system(size:13,weight:.medium))
                                            Text("未锁定可用 \(g.cardCount(h.id,unlockedOnly:true)) 张").font(.system(size:11)).foregroundStyle(TownPalette.muted)
                                        }
                                        Spacer()
                                        Button("升至 \(star+1) 星") {
                                            confirm(.starUp(hero:h.id,target:star+1),"消耗\(cost)张未锁定同名重复卡，为\(h.name)升一星。不消耗金币，不能撤销。")
                                        }.buttonStyle(TownButtonStyle(prominent:true)).disabled(model.busy || g.cardCount(h.id,unlockedOnly:true)<cost)
                                    }
                                } else {Text("已达五星，多余卡由你决定是否分解。").font(.callout)}
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }
                        TownCard {
                            VStack(alignment:.leading,spacing:14) {
                                Text("重逢留念").font(.custom("Songti SC",size:21).weight(.bold))
                                Text("同名重复卡默认保留，太守不会替你处理。").font(.system(size:11)).foregroundStyle(TownPalette.muted)
                                ForEach(g.cards.values.filter{$0.heroID==h.id}.sorted{$0.id<$1.id}){card in
                                    HStack {
                                        Label("\(card.count) 张",systemImage:card.locked ? "lock":"square.stack")
                                        Spacer()
                                        Button(card.locked ? "解锁":"锁定"){submit(.lock(card:card.id,locked:!card.locked))}.disabled(model.busy)
                                        Button("分解1张"){
                                            confirm(.disassemble(card:card.id,quantity:1),"分解\(h.name)的1张重复卡，获得\(d.cultivation.disassemble_yield[h.rarity]!)将魂。不可撤销；未满星时将减少升星材料，可能失去当前升星资格。武将本体不会消失。")
                                        }.disabled(model.busy || card.locked)
                                    }.font(.system(size:12))
                                }
                                if g.cardCount(h.id)==0 {Text("暂未重逢 · 还没有此人的重复卡").font(.system(size:12)).foregroundStyle(TownPalette.muted).padding(.vertical,8)}
                                Divider()
                                let price=d.cultivation.exchange_cost[h.rarity]!
                                HStack {
                                    VStack(alignment:.leading,spacing:5) {
                                        Text("将魂换同名卡").font(.system(size:13,weight:.medium))
                                        Text("每张 \(price) 将魂 · 余额 \(g.souls)").font(.system(size:11)).foregroundStyle(TownPalette.muted)
                                    }
                                    Spacer()
                                    Button("兑换1张") {
                                        confirm(.exchange(hero:h.id,quantity:1),"花费\(price)通用将魂兑换\(h.name)同名卡1张，不会自动升星。兑换卡再分解有损耗。")
                                    }.disabled(model.busy || star==5 || g.souls<price)
                                }
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }
                    }.padding(.bottom,20)
                }
            }
        }.padding(.horizontal,24)
    }
    private func skillMark(_ name:String,_ detail:String,unlocked:Bool)->some View {
        VStack(alignment:.leading,spacing:7) {
            Image(systemName:unlocked ? "seal":"lock").foregroundStyle(unlocked ? gold:TownPalette.muted)
            Text(name).font(.system(size:12,weight:.medium))
            Text(detail).font(.system(size:9)).foregroundStyle(TownPalette.muted)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(13)
            .background(unlocked ? gold.opacity(0.08):TownPalette.paper,in:RoundedRectangle(cornerRadius:11))
    }
    private func chronicle(_ w:LifeWorld)->some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:0) {
                ForEach(w.records.reversed()) {r in
                    HStack(alignment:.top,spacing:20) {
                        Text("第 \(r.time/2880+1) 日").font(.custom("Songti SC",size:16)).frame(width:76,alignment:.leading)
                        Circle().fill(gold).frame(width:6,height:6).padding(.top,6)
                        VStack(alignment:.leading,spacing:8) {
                            Text(r.text).font(.system(size:13)).textSelection(.enabled)
                            Text("城中记 · \(r.time/60) 分").font(.system(size:10)).foregroundStyle(TownPalette.muted)
                        }
                        Spacer()
                    }.padding(22)
                    Divider().padding(.leading,128)
                }
            }.background(TownPalette.card,in:RoundedRectangle(cornerRadius:20)).padding(.horizontal,24)
        }
    }
    private var revealSheet:some View {
        VStack(spacing:20) {
            if let g=model.world?.gacha,let d=model.definition {
                Text("酒馆来信").font(.custom("Songti SC",size:32).weight(.bold))
                Text("相逢已记入城中 · 关闭不会改变结果").font(.system(size:12)).foregroundStyle(TownPalette.muted)
                ScrollView {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:140))],spacing:14) {
                        ForEach(g.lastDraws){r in
                            VStack(spacing:10) {
                                TownHeroPortrait(id:r.heroID).frame(height:150)
                                Text(d.hero(r.heroID)?.name ?? r.heroID).font(.custom("Songti SC",size:22).weight(.bold))
                                Text(rarityName(r.rarity)).font(.system(size:11)).foregroundStyle(rarityColor(r.rarity))
                                Text(r.isNew ? "初见 · 30秒后抵达":"重逢 · 同名卡已收好").font(.system(size:10)).foregroundStyle(TownPalette.muted)
                            }.padding(12).background(TownPalette.card,in:RoundedRectangle(cornerRadius:16))
                                .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(rarityColor(r.rarity).opacity(0.3)))
                        }
                    }.padding(4)
                }
                Button("收好来信，回城看看"){reveal=false;page=0}.buttonStyle(TownButtonStyle(prominent:true))
            }
        }.padding(28).frame(width:780,height:600).background(TownPalette.paper).foregroundStyle(TownPalette.ink)
    }
    private func resourceNote(_ w:LifeWorld,_ g:LifeGachaState)->some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("城中物资").font(.custom("Songti SC",size:20).weight(.bold))
                Spacer()
                Button {resourcesPresented=false} label:{Image(systemName:"xmark")}
                    .buttonStyle(.plain).accessibilityLabel("关闭物资说明")
            }
            Text("太守安排采集、冶炼与供餐。金锭运抵府署后，每份换得10金币。")
                .font(.caption).foregroundStyle(TownPalette.muted).fixedSize(horizontal:false,vertical:true)
            Divider()
            ForEach(LifeResource.allCases,id:\.self){resource in
                HStack {Text(resource.title);Spacer();Text("\(Double(w.amount(resource))/1000,specifier:"%.1f")").monospacedDigit()}.font(.caption)
            }
            Divider()
            Text("累计铸币 \(g.minted) · 饭食覆盖 \(w.foodCoverage/100)%").font(.caption).foregroundStyle(TownPalette.muted)
        }.padding(20).frame(width:280).background(TownPalette.paper)
    }
    private func confirm(_ action:LifeGachaAction,_ text:String){pending=action;confirmationText=text;confirmation=true}
    private func submit(_ action:LifeGachaAction){Task{await model.send(.gacha(.init(action:action)))}}
    private func rarityName(_ r:String)->String {["talent":"良才","renowned":"名士","legend":"传奇"][r] ?? r}
    private func rarityColor(_ r:String)->Color {r=="legend" ? gold:(r=="renowned" ? TownPalette.color("#806587"):TownPalette.jade)}
    private func profileName(_ p:String)->String {["food":"民生","supply":"采集","craft":"工造","logistics":"转运","trade":"经营","guard":"守备"][p] ?? ""}
    private func signatureText(_ p:String)->String {
        ["food":"五星 · 丰盛素宴：亲自掌厨，制作更好的饭食。","supply":"五星 · 丰收：本人采集产量增加10%。","craft":"五星 · 巧工：亲自勘测后，新工程节省10%木材。","logistics":"五星 · 善运：本人搬运容量增加25%。","trade":"五星 · 精炼：本人准备金炉批次，节省10%木燃料。","guard":"五星 · 守望：完成真实晚巡后，本周期环境增加5。"][p] ?? ""
    }
}
