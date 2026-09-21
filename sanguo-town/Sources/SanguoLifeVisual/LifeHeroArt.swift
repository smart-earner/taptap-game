import SanguoPresentation

/// Original, animated paper-diorama heroes. The same rig is used in town and on cards.
public enum LifeHeroArt {
    public struct Appearance:Sendable {
        public let coat:String,trim:String,hat:Int,beard:Int,build:Double
    }
    public static let appearances:[String:Appearance] = {
        let rows:[(String,String,String,Int,Int,Double)] = [
            ("xunyu","#416D72","#CFBE83",0,1,1),
            ("liubei","#648365","#DCCC9A",1,1,1),
            ("zhangfei","#8D483B","#C9A36B",2,3,1.23),
            ("zhaoyun","#C8D8D1","#668D96",3,0,0.98),
            ("huangyueying","#CC9F53","#547F74",4,0,0.96),
            ("liang","#B7C4A1","#577A75",5,2,1),
            ("guanyu","#427362","#D1B177",2,4,1.14),
            ("lusu","#A08566","#DFCB9B",0,2,1.08),
            ("caocao","#435969","#BF9A5C",0,2,1.08),
            ("sunquan","#886949","#DDC18B",1,2,1.06),
            ("simayi","#645B72","#BDBAA1",0,1,0.98),
            ("guojia","#7E9695","#DDD0AA",5,0,0.96),
            ("jiaxu","#72624F","#C5AC7A",0,2,1),
            ("pangtong","#97775D","#C6C7A2",5,3,1.06),
            ("xunyou","#546E62","#C0B58C",0,1,1.02),
            ("chenqun","#717D8B","#D7C39B",1,1,1),
            ("manchong","#7B735C","#C6B27C",2,1,1.08),
            ("zhangzhao","#89795D","#E0D0AD",0,4,0.98),
            ("zhouyu","#A45447","#D8BD83",3,0,1),
            ("luxun","#73A08B","#E2CAA0",1,0,0.97),
            ("lumeng","#537B82","#CCAD71",2,1,1.1),
            ("zhangliao","#52738C","#C6BEA3",3,2,1.1),
            ("xuhuang","#9B9C88","#5F796B",2,2,1.12),
            ("xiahoudun","#556169","#BB9E73",3,2,1.12),
            ("xuchu","#976449","#DCC088",2,0,1.28),
            ("machao","#D2D4BF","#A77C4C",3,0,1.06),
            ("huangzhong","#B78D51","#D9D2B5",3,4,1.1),
            ("weiyan","#865D50","#B7AA7E",2,2,1.13),
            ("ganning","#408B89","#D6BC73",2,0,1.06),
            ("lvbu","#805264","#D0AF6E",6,0,1.16)]
        return Dictionary(uniqueKeysWithValues:rows.map{($0.0,Appearance(coat:$0.1,trim:$0.2,hat:$0.3,beard:$0.4,build:$0.5))})
    }()
    public static func artwork(_ id:String?,fallback:Costume)->VNode {
        guard let look=appearances[id ?? ""] else{return CharacterRig.artwork(fallback)}
        let costume:Costume = [0,1,5].contains(look.hat) ? .official:(look.hat==4 ? .artisan:.warrior)
        let ink="#34423F",skin="#E9C299"
        func decorate(_ node:VNode)->VNode {
            var n=node;n.children=n.children.map(decorate)
            if ["robe","near-sleeve","armor-chest","cape-cloth"].contains(n.id) {n.fill=look.coat}
            if ["cuff","lapel","buckle","robe-fold"].contains(n.id) {n.fill=look.trim}
            if n.stroke != "none" {n.stroke=ink;n.strokeWidth=0.8}
            if n.id=="face" {n.fill=skin;n.stroke="none"}
            if n.id=="shadow" {n.fill="#567165";n.opacity=0.3}
            if n.id=="torso" {
                n.children += [.polygon("coat-shade",[(-11,32),(-5,29),(-7,12),(-14,9),(-10,22)],"#314B44",stroke:"none"),
                    .line("embroidered-edge",[(8,31),(3,23),(9,10)],look.trim,width:1.5),
                    .rect("jade-pendant",7,14,3,6,"#D2D4AA",radius:1)]
                if costume == .warrior {
                    for row in 0..<3 {for col in 0..<4 {
                        n.children.append(.rect("armor-plate-\(row)-\(col)",-7+Double(col)*4,22+Double(row)*3,3,2,look.trim,radius:0.4))
                    }}
                    n.children.append(.polygon("shoulder-guard",[(7,36),(16,33),(17,27),(9,28)],look.trim,stroke:ink,width:0.7))
                }
                if id=="huangyueying" {
                    n.children += [.rect("tool-satchel",-15,14,11,12,"#705B42",radius:2),
                        .line("tool-strap",[(-14,34),(10,17)],"#E1CF9C",width:2),
                        .rect("blueprint",-16,19,5,13,"#B7CFBA",radius:1)]
                }
                if id=="liubei" {n.children.append(.line("woven-belt",[(-10,20),(11,20)],"#D4B879",width:2))}
            }
            if n.id=="head" {
                n.children.removeAll{["hat","hat-crown","hat-band","hat-jade","topknot","headband","ribbon"].contains($0.id)}
                switch look.hat {
                case 0:
                    n.children += [.rect("scholar-crown",-9,12,18,16,ink,radius:3),
                        .polygon("crown-top",[(-9,23),(-5,33),(5,33),(9,23)],ink,stroke:"none"),
                        .line("crown-band",[(-11,14),(11,14)],look.trim,width:3),
                        .rect("crown-jade",-2,14,4,5,"#AFCAAC",radius:1)]
                case 1,2:
                    n.children += [.ellipse("knot",-6,14,12,11,ink),
                        .rect("cloth-band",-12,10,25,5,look.trim,radius:2),
                        .polygon("band-tail",[(-11,13),(-20,9),(-18,-1),(-14,6)],look.coat,stroke:"none")]
                case 3,6:
                    n.children += [.polygon("helmet",[(-13,7),(-12,18),(0,27),(12,18),(14,7),(7,12),(0,16),(-7,12)],look.coat,stroke:ink,width:0.8),
                        .line("helmet-ridge",[(0,17),(0,27)],look.trim,width:3),
                        .polygon("plume",[(0,26),(0,39),(7,47),(6,30)],look.hat==6 ? "#563D42":"#B46347",stroke:"none")]
                    if look.hat==6 {n.children += [.line("long-feather-a",[(-3,25),(-17,43),(-22,58)],"#B9905B",width:2),.line("long-feather-b",[(3,25),(20,47),(23,59)],"#B9905B",width:2)]}
                case 4:
                    n.children += [.ellipse("hair-bun",-18,8,12,15,ink),
                        .line("hairpin",[(-21,17),(-4,18)],look.trim,width:2),
                        .ellipse("hairpin-bead",-22,15,4,4,"#6E9C88"),
                        .polygon("hair-ribbon",[(-14,10),(-23,1),(-15,3),(-19,-8),(-11,7)],look.trim,stroke:"none")]
                default:
                    n.children += [.polygon("soft-cap",[(-12,11),(-8,25),(0,29),(11,23),(13,11)],look.coat,stroke:ink,width:0.7),
                        .line("cap-edge",[(-12,12),(12,12)],look.trim,width:2)]
                }
                if look.beard>0 {
                    let length=Double(look.beard==4 ? 24:(look.beard==3 ? 14:8)),wide=look.beard>=3 ? 10.0:5.0
                    n.children.append(.polygon("hero-beard",[(-wide,-4),(-wide+2,-10),(2,-length),(wide,-9),(wide,-4)],id=="huangzhong" || id=="zhangzhao" ? "#D4D1B9":ink,stroke:"none"))
                }
                if id=="xiahoudun" {n.children.append(.line("eye-patch",[(-8,4),(11,2)],ink,width:3))}
            }
            return n
        }
        return .init("hero-proportions",transform:.init(sx:look.build,sy:1.08),children:[decorate(CharacterRig.artwork(costume))])
    }
}
