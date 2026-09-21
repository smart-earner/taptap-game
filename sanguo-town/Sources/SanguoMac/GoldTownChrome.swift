import SwiftUI
import SanguoPresentation
import SanguoLifeVisual

enum TownPalette {
    static let ink=color("#293F39"),muted=color("#667064"),paper=color("#F4F0E4")
    static let card=color("#FFFCF2"),jade=color("#3F695B"),gold=color("#99713C"),line=color("#DED9C8")
    static func color(_ hex:String)->Color {
        let value=UInt64(hex.replacingOccurrences(of:"#",with:""),radix:16) ?? 0
        return Color(red:Double((value>>16)&255)/255,green:Double((value>>8)&255)/255,blue:Double(value&255)/255)
    }
}

struct TownButtonStyle:ButtonStyle {
    var prominent=false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:13,weight:.medium))
            .padding(.horizontal,18).padding(.vertical,11)
            .foregroundStyle(prominent ? TownPalette.card:TownPalette.ink)
            .background(prominent ? TownPalette.jade:TownPalette.card,in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(prominent ? Color.clear:TownPalette.line,lineWidth:1))
            .opacity(enabled ? (configuration.isPressed ? 0.7:1):0.4)
    }
}

/// Uses the actual vector sprite, not an unrelated portrait placeholder or another simulation.
struct TownVectorArt:View {
    let art:VNode
    var bounds=CGRect(x:-35,y:-5,width:70,height:102)
    var body:some View {
        Canvas {context,size in
            let scale=min(size.width/bounds.width,size.height/bounds.height)
            context.translateBy(x:(size.width-bounds.width*scale)/2-bounds.minX*scale,
                                y:(size.height+bounds.height*scale)/2+bounds.minY*scale)
            context.scaleBy(x:scale,y:-scale)
            draw(art,in:context)
        }.accessibilityHidden(true)
    }
    private func draw(_ node:VNode,in original:GraphicsContext) {
        // Inventory props are displayed only by an actual task in town, not on idle cards.
        guard !["sword","spear","hammer","book","basket","hoe","axe"].contains(node.id) else{return}
        var context=original
        context.translateBy(x:node.transform.x,y:node.transform.y)
        context.rotate(by:.radians(node.transform.angle))
        context.scaleBy(x:node.transform.sx,y:node.transform.sy)
        context.opacity *= node.opacity
        if let shape=node.shape {
            var path=Path()
            switch shape {
            case .polygon(let points),.line(let points):
                if let first=points.first {
                    path.move(to:.init(x:first.x,y:first.y))
                    for p in points.dropFirst(){path.addLine(to:.init(x:p.x,y:p.y))}
                    if case .polygon=shape {path.closeSubpath()}
                }
            case .ellipse(let x,let y,let w,let h):path.addEllipse(in:.init(x:x,y:y,width:w,height:h))
            case .rect(let x,let y,let w,let h,let radius):path.addRoundedRect(in:.init(x:x,y:y,width:w,height:h),cornerSize:.init(width:radius,height:radius))
            }
            if node.fill != "none" {context.fill(path,with:.color(TownPalette.color(node.fill)))}
            if node.stroke != "none" {context.stroke(path,with:.color(TownPalette.color(node.stroke)),style:.init(lineWidth:node.strokeWidth,lineCap:.round,lineJoin:.round))}
        }
        for child in node.children {draw(child,in:context)}
    }
}

struct TownHeroPortrait:View {
    let id:String
    var body:some View {
        ZStack {
            RoundedRectangle(cornerRadius:16).fill(TownPalette.color(LifeHeroArt.appearances[id]?.coat ?? "#718576").opacity(0.12))
            Circle().fill(TownPalette.card.opacity(0.7)).padding(12)
            TownVectorArt(art:LifeHeroArt.artwork(id,fallback:.warrior)).padding(8)
        }.accessibilityHidden(true)
    }
}

struct TownCard<Content:View>:View {
    let content:Content
    init(@ViewBuilder content:()->Content){self.content=content()}
    var body:some View {
        content.padding(20).background(TownPalette.card,in:RoundedRectangle(cornerRadius:18))
            .overlay(RoundedRectangle(cornerRadius:18).strokeBorder(TownPalette.line.opacity(0.7),lineWidth:1))
    }
}
