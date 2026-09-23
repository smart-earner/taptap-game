import Foundation
import SanguoLife

/// Development-only structured diagnostics. Bridge stdout is reserved for its
/// JSON response, so diagnostics are appended to a bounded JSONL sidecar.
enum DebugTrace {
    static let maximumBytes: UInt64 = 8 * 1024 * 1024
    static let retainedFiles = 5

    static var enabled: Bool {
        let value = ProcessInfo.processInfo.environment["SANGUO_DEBUG_LOG"]?.lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    static func path(in saveDirectory: URL) -> URL {
        saveDirectory.appendingPathComponent("debug/engine-debug.jsonl")
    }

    static func log(in saveDirectory: URL, event: String, level: String = "debug", fields: [String: Any] = [:]) {
        guard enabled else { return }
        do {
            let url = path(in: saveDirectory)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try rotateIfNeeded(url)
            var row = fields
            row["timestamp"] = ISO8601DateFormatter().string(from: Date())
            row["source"] = "engine"
            row["event"] = event
            row["level"] = level
            row["pid"] = ProcessInfo.processInfo.processIdentifier
            let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) + Data([0x0A])
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Never contaminate bridge stdout or fail gameplay because logging failed.
            FileHandle.standardError.write(Data("debug log failure: \(error)\n".utf8))
        }
    }

    static func shouldWriteDetail(input: GodotBridge.Input, before: LifeWorld, after: LifeWorld) -> Bool {
        input.operation != "advance" || input.seconds >= 30 || before.cycle != after.cycle ||
            before.isNight != after.isNight || before.tasks != after.tasks || before.projects != after.projects ||
            before.stations != after.stations || before.time / 30 != after.time / 30
    }

    static func worldState(_ world: LifeWorld) -> [String: Any] {
        let activeMeals = world.meals.filter { !$0.closed }.map { meal in
            ["id": meal.id, "at": meal.at, "deadline": meal.deadline,
             "expected": meal.expected.count, "served": meal.served.count] as [String: Any]
        }
        let agents = world.agents.values.sorted { $0.id < $1.id }.map { agent -> [String: Any] in
            var row: [String: Any] = [
                "id": agent.id, "job": agent.job, "node": agent.node, "home": agent.home,
                "taskID": agent.taskID ?? "", "busyCycle": agent.busyCycle,
                "serviceSeconds": agent.serviceSeconds, "restedCycle": agent.restedCycle,
                "status": idleReason(agent, world: world)
            ]
            if let restStart = agent.restStart { row["restStart"] = restStart; row["restSeconds"] = max(0, world.time - restStart) }
            if let condition = world.heroTown?.health?.conditions[agent.id] {
                row["health"] = condition.kind
                row["healthModifierBP"] = condition.workModifierBP
                row["blockedJobs"] = condition.blockedJobs
            }
            return row
        }
        let tasks = world.tasks.values.sorted { $0.id < $1.id }.map { task -> [String: Any] in
            ["id": task.id, "worker": task.worker, "kind": task.kind, "job": task.job,
             "subject": task.subject, "target": task.target, "step": task.step,
             "stepKind": task.current.kind, "stepSeconds": task.current.seconds,
             "started": task.started, "due": task.due, "rate": task.rate,
             "resource": task.resource?.rawValue ?? "", "quantity": task.quantity,
             "routePoints": task.current.route.count]
        }
        let projects = world.projects.values.sorted { $0.id < $1.id }.map { project -> [String: Any] in
            let site = "project-\(project.id)"
            let materialRows = project.materials.keys.sorted().map { key -> [String: Any] in
                let resource = LifeResource(rawValue: key)!
                return ["resource": key, "required": project.materials[key]!,
                        "atSite": world.amount(resource, at: site), "total": world.amount(resource)]
            }
            return ["id": project.id, "kind": project.kind, "node": project.node,
                    "phase": project.phase, "stageStarted": project.stageStarted,
                    "completed": project.completed, "completedWork": project.completedWork,
                    "totalWork": project.totalWork, "allocatedWork": project.allocatedWork,
                    "cash": project.cash, "materials": materialRows]
        }
        let stations = world.stations.values.sorted { $0.id < $1.id }.map { station -> [String: Any] in
            ["id": station.id, "kind": station.kind, "phase": station.phase,
             "recipe": station.recipe ?? "", "taskID": station.taskID ?? "",
             "input": station.input, "output": station.output,
             "inputVolume": world.volume(at: station.input), "outputVolume": world.volume(at: station.output),
             "foodInProcess": station.foodInProcess]
        }
        let resources = LifeResource.allCases.map { resource -> [String: Any] in
            let inTransit = world.lots.values.filter { $0.resource == resource && world.tasks[$0.location] != nil }.reduce(Int64(0)) { $0 + $1.amount }
            return ["id": resource.rawValue, "total": world.amount(resource),
                    "free": world.amount(resource, free: true), "warehouse": world.amount(resource, at: "warehouse"),
                    "inTransit": inTransit, "produced": world.produced[resource.rawValue, default: 0],
                    "consumed": world.consumed[resource.rawValue, default: 0]]
        }
        return [
            "time": world.time, "cycle": world.cycle, "phase": world.phase, "night": world.isNight,
            "sequence": world.sequence, "policy": world.policy, "treasury": world.treasury,
            "reservedCash": world.reservedCash, "population": world.agents.count, "housing": world.housing,
            "happiness": world.happiness, "foodCoverage": world.foodCoverage,
            "activeTaskCount": world.tasks.count, "idleAgentCount": world.agents.values.filter { $0.taskID == nil }.count,
            "agents": agents, "tasks": tasks, "projects": projects, "stations": stations,
            "resources": resources, "activeMeals": activeMeals,
            "recentRecords": world.records.suffix(20).map { ["time": $0.time, "kind": $0.kind, "text": $0.text] }
        ]
    }

    private static func idleReason(_ agent: LifeAgent, world: LifeWorld) -> String {
        if let taskID = agent.taskID, let task = world.tasks[taskID] { return "task:\(task.kind):\(task.current.kind)" }
        if world.heroTown?.health?.treatments[agent.id] != nil { return "health_treatment" }
        if agent.restStart != nil { return world.isNight ? "night_rest_at_home" : "rest_at_home" }
        if agent.job == "guard_night", (900..<1740).contains(world.phase) { return "night_guard_sleep_window" }
        if agent.job != "guard_night", world.phase >= 2160 { return "night_rest_window" }
        if world.phase < 240 { return "before_day_shift" }
        if world.phase >= 1920 { return "day_shift_closed" }
        if agent.busyCycle == world.cycle, agent.serviceSeconds >= 1920 { return "service_budget_exhausted" }
        if world.meals.contains(where: { !$0.closed && $0.expected.contains(agent.id) && $0.served[agent.id] == nil }) { return "awaiting_meal" }
        return "planner_no_feasible_task"
    }

    private static func rotateIfNeeded(_ url: URL) throws {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
        guard size >= maximumBytes else { return }
        let manager = FileManager.default
        let oldest = URL(fileURLWithPath: url.path + ".\(retainedFiles)")
        try? manager.removeItem(at: oldest)
        if retainedFiles >= 2 {
            for index in stride(from: retainedFiles - 1, through: 1, by: -1) {
                let source = URL(fileURLWithPath: url.path + ".\(index)")
                let destination = URL(fileURLWithPath: url.path + ".\(index + 1)")
                if manager.fileExists(atPath: source.path) { try? manager.moveItem(at: source, to: destination) }
            }
        }
        if manager.fileExists(atPath: url.path) { try manager.moveItem(at: url, to: URL(fileURLWithPath: url.path + ".1")) }
    }
}
