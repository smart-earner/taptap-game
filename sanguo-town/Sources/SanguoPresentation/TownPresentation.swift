import Foundation
import SanguoCore

public struct RoadGraph: Sendable {
    public var points: [String: VPoint]
    public var edges: [(String, String)]
    public init(points: [String: VPoint], edges: [(String, String)]) { self.points = points; self.edges = edges }
    /// Deterministic Dijkstra. Missing/disconnected destinations never become a straight-line shortcut.
    public func route(from start: String, to end: String) -> [VPoint]? {
        guard points[start] != nil, points[end] != nil else { return nil }
        var distances = [start: 0.0], previous: [String: String] = [:], visited = Set<String>()
        while let current = distances.keys.filter({ !visited.contains($0) }).sorted(by: {
            distances[$0]! == distances[$1]! ? $0 < $1 : distances[$0]! < distances[$1]!
        }).first {
            if current == end {
                var ids = [end]
                while let p = previous[ids.last!] { ids.append(p) }
                return ids.reversed().compactMap { points[$0] }
            }
            visited.insert(current)
            let neighbors = edges.compactMap { a, b in a == current ? b : b == current ? a : nil }.sorted()
            for neighbor in neighbors where !visited.contains(neighbor) {
                guard let a = points[current], let b = points[neighbor] else { continue }
                let next = distances[current]! + a.distance(to: b)
                if next < distances[neighbor, default: .infinity] { distances[neighbor] = next; previous[neighbor] = current }
            }
        }
        return nil
    }
    public static let town = RoadGraph(points: [
        "gate": .init(900,76), "r0": .init(75,76), "r1": .init(225,76),
        "r2": .init(455,76), "r3": .init(700,76),
        "hall": .init(225,130), "forge": .init(455,125), "field": .init(700,123),
        "store": .init(75,120), "timber": .init(790,96), "mine": .init(555,102),
        "patrol": .init(840,76)
    ], edges: [("r0","r1"),("r1","r2"),("r2","r3"),("r3","patrol"),("patrol","gate"),
               ("r1","hall"),("r2","forge"),("r3","field"),("r0","store"),
               ("patrol","timber"),("r2","mine")])
}
public struct ActorSpec: Equatable, Sendable, Identifiable {
    public var id: String, name: String
    public var costume: Costume
    public var home: String, destination: String
    public var work: Motion
    public var representative: Bool
    public init(id: String, name: String, costume: Costume, home: String = "gate", destination: String,
                work: Motion = .idle, representative: Bool = false) {
        self.id = id; self.name = name; self.costume = costume; self.home = home
        self.destination = destination; self.work = work; self.representative = representative
    }
}
public struct TownProjection: Equatable, Sendable {
    public var cityID: String, title: String
    public var actors: [ActorSpec]
    public var hasWorkshop: Bool, hasField: Bool, isDemo: Bool
    /// Only projects the requested city's real residents. Representatives are never added to WorldState.
    public static func live(_ world: WorldState, cityID: String) -> TownProjection? {
        guard let city = world.cities[cityID] else { return nil }
        let people = world.people.values.filter { $0.cityID == cityID }.sorted { $0.id < $1.id }
        var actors = people.prefix(8).map { person in
            let official = person.office != nil || person.isProxy
            return ActorSpec(id: "person:"+person.id, name: person.name,
                costume: official ? .official : .warrior,
                home: official ? "hall" : "gate", destination: official ? "patrol" : "store",
                work: official ? .idle : .read)
        }
        let work: [(String, String, Motion)] = [
            ("grain","field",.cultivate), ("wood","timber",.chop), ("iron","mine",.hammer),
            ("wine","store",.carry), ("tools","forge",.hammer)]
        for (resource, place, motion) in work where city.jobs[resource, default: 0] > 0 {
            let title = Resource(rawValue: resource)?.title ?? resource
            actors.append(.init(id: "representative:\(cityID):\(resource)", name: title+"岗位示意",
                                costume: .artisan, destination: place, work: motion, representative: true))
        }
        return .init(cityID: cityID, title: city.name, actors: actors, hasWorkshop: city.jobCapacity["tools", default: 0] > 0,
                     hasField: city.jobCapacity["grain", default: 0] > 0, isDemo: false)
    }
    public static let demo = TownProjection(cityID: "animation-demo", title: "动作样板 · 不改存档", actors: [
        .init(id: "demo-warrior", name: "演示武将", costume: .warrior, home: "hall", destination: "forge", work: .hammer),
        .init(id: "demo-official", name: "演示文官", costume: .official, home: "gate", destination: "hall", work: .read),
        .init(id: "demo-artisan", name: "演示工匠", costume: .artisan, home: "store", destination: "field", work: .cultivate)
    ], hasWorkshop: true, hasField: true, isDemo: true)
}
public struct ActorState: Equatable, Sendable {
    public var spec: ActorSpec
    public private(set) var position: VPoint
    public private(set) var motion: Motion = .idle
    public private(set) var facing: Double = 1
    public private(set) var distance: Double = 0
    public private(set) var phaseTime: Double = 0
    public private(set) var legOfTrip: Int = 0
    private var path: [VPoint] = []
    private var waypoint = 0
    private var wait: Double
    private var returning = false
    private var node: String
    public init(_ spec: ActorSpec, delay: Double = 0, graph: RoadGraph = .town) {
        self.spec = spec; position = graph.points[spec.home] ?? .init(900,76)
        node = spec.home; wait = 1 + max(0, delay)
    }
    public var depth: Double { 500 - position.y }
    public mutating func step(_ delta: Double, graph: RoadGraph = .town) {
        guard delta.isFinite, delta > 0, delta <= 0.25 else { return }
        phaseTime += delta
        if motion != .walk {
            wait -= delta
            guard wait <= 0 else { return }
            let target = returning ? spec.home : spec.destination
            guard let route = graph.route(from: node, to: target), route.count > 1 else {
                motion = .idle; wait = 3; return
            }
            path = route; waypoint = 1; motion = .walk; phaseTime = 0
        }
        var remaining = delta * 38
        while waypoint < path.count, remaining > 0 {
            let target = path[waypoint], gap = position.distance(to: target)
            let movement = min(gap, remaining)
            if abs(target.x-position.x) > 0.01 { facing = target.x > position.x ? 1 : -1 }
            position = gap < 0.001 ? target : position.toward(target, fraction: movement/gap)
            distance += movement; remaining -= movement
            if gap <= movement + 0.001 { waypoint += 1 } else { break }
        }
        if waypoint >= path.count {
            node = returning ? spec.home : spec.destination
            motion = returning ? (spec.costume == .official ? .read : .idle) : spec.work
            returning.toggle(); phaseTime = 0; wait = motion == .idle ? 2.5 : 6
            legOfTrip += 1
        }
    }
}
public struct TownDirector: Sendable {
    public private(set) var projection: TownProjection?
    public private(set) var actors: [String: ActorState] = [:]
    public private(set) var visibleTime: Double = 0
    public var paused = false
    public init() {}
    public mutating func sync(_ next: TownProjection) {
        let sameCity = projection?.cityID == next.cityID && projection?.isDemo == next.isDemo
        let old = sameCity ? actors : [:]
        var replacement: [String: ActorState] = [:]
        for (index, spec) in next.actors.enumerated() {
            guard replacement[spec.id] == nil else { continue }
            // Unchanged actors retain their route/phase across every snapshot refresh.
            if let actor = old[spec.id], actor.spec == spec { replacement[spec.id] = actor }
            else { replacement[spec.id] = .init(spec, delay: Double(index)*0.8) }
        }
        actors = replacement; projection = next
    }
    public mutating func tick(_ delta: Double) {
        // No visual catch-up after sleep/occlusion. Economic catch-up belongs solely to GameSession.
        guard !paused, delta.isFinite, delta > 0, delta <= 0.25 else { return }
        visibleTime += delta
        for id in actors.keys.sorted() { actors[id]?.step(delta) }
    }
}
