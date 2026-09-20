import Foundation

/// Renderer-independent, original vector artwork. Coordinates are y-up, feet at (0, 0).
public struct VPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public func distance(to b: VPoint) -> Double { hypot(b.x - x, b.y - y) }
    public func toward(_ b: VPoint, fraction: Double) -> VPoint {
        .init(x + (b.x - x) * fraction, y + (b.y - y) * fraction)
    }
}
public struct VTransform: Equatable, Sendable {
    public var x: Double = 0, y: Double = 0, angle: Double = 0
    public var sx: Double = 1, sy: Double = 1
    public init(x: Double = 0, y: Double = 0, angle: Double = 0, sx: Double = 1, sy: Double = 1) {
        self.x = x; self.y = y; self.angle = angle; self.sx = sx; self.sy = sy
    }
}
public enum VShape: Equatable, Sendable {
    case polygon([VPoint])
    case line([VPoint])
    case ellipse(x: Double, y: Double, w: Double, h: Double)
    case rect(x: Double, y: Double, w: Double, h: Double, radius: Double)
}
public struct VNode: Equatable, Sendable {
    public var id: String
    public var shape: VShape?
    public var fill: String
    public var stroke: String
    public var strokeWidth: Double
    public var opacity: Double
    public var transform: VTransform
    public var children: [VNode]
    public init(_ id: String, shape: VShape? = nil, fill: String = "none", stroke: String = "none",
                width: Double = 1, opacity: Double = 1, transform: VTransform = .init(), children: [VNode] = []) {
        self.id = id; self.shape = shape; self.fill = fill; self.stroke = stroke
        self.strokeWidth = width; self.opacity = opacity; self.transform = transform; self.children = children
    }
    public static func polygon(_ id: String, _ points: [(Double, Double)], _ fill: String,
                               stroke: String = "#273638", width: Double = 1.2) -> VNode {
        .init(id, shape: .polygon(points.map(VPoint.init)), fill: fill, stroke: stroke, width: width)
    }
    public static func line(_ id: String, _ points: [(Double, Double)], _ stroke: String, width: Double = 1) -> VNode {
        .init(id, shape: .line(points.map(VPoint.init)), stroke: stroke, width: width)
    }
    public static func ellipse(_ id: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                               _ fill: String, stroke: String = "none") -> VNode {
        .init(id, shape: .ellipse(x: x, y: y, w: w, h: h), fill: fill, stroke: stroke)
    }
    public static func rect(_ id: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                            _ fill: String, radius: Double = 0, stroke: String = "none") -> VNode {
        .init(id, shape: .rect(x: x, y: y, w: w, h: h, radius: radius), fill: fill, stroke: stroke)
    }
    public var allIDs: [String] { [id] + children.flatMap(\.allIDs) }
}
public enum SVG {
    public static func number(_ n: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), n)
    }
    public static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    public static func node(_ node: VNode, overrides: [String: VTransform] = [:], hidden: Set<String> = []) -> String {
        guard !hidden.contains(node.id) else { return "" }
        let t = overrides[node.id] ?? node.transform
        var s = "<g data-part=\"\(escape(node.id))\" transform=\"translate(\(number(t.x)) \(number(t.y))) rotate(\(number(t.angle * 180 / .pi))) scale(\(number(t.sx)) \(number(t.sy)))\" opacity=\"\(number(node.opacity))\">"
        let style = "fill=\"\(node.fill)\" stroke=\"\(node.stroke)\" stroke-width=\"\(number(node.strokeWidth))\" stroke-linejoin=\"round\" stroke-linecap=\"round\""
        if let shape = node.shape {
            switch shape {
            case .polygon(let p), .line(let p):
                let tag: String
                if case .polygon = shape { tag = "polygon" } else { tag = "polyline" }
                s += "<\(tag) points=\"\(p.map { "\(number($0.x)),\(number($0.y))" }.joined(separator: " "))\" \(style)/>"
            case .ellipse(let x, let y, let w, let h):
                s += "<ellipse cx=\"\(number(x+w/2))\" cy=\"\(number(y+h/2))\" rx=\"\(number(w/2))\" ry=\"\(number(h/2))\" \(style)/>"
            case .rect(let x, let y, let w, let h, let r):
                s += "<rect x=\"\(number(x))\" y=\"\(number(y))\" width=\"\(number(w))\" height=\"\(number(h))\" rx=\"\(number(r))\" \(style)/>"
            }
        }
        s += node.children.map { self.node($0, overrides: overrides, hidden: hidden) }.joined()
        return s + "</g>"
    }
}
