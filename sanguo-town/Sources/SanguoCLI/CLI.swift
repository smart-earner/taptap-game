import Foundation
import SanguoCore
#if os(Linux)
import Glibc
#else
import Darwin
#endif

@main
enum SanguoCLI {
    static func main() async {
        do {
            var oneCity = false, hours: Int64 = 6, policy = Policy.trade, savePath: String?
            var args = Array(CommandLine.arguments.dropFirst())
            while !args.isEmpty {
                let flag = args.removeFirst()
                if flag == "--one-city" { oneCity = true; continue }
                if flag == "--help" {
                    print("SanguoCLI [--one-city] [--hours 0...8760] [--policy supply|trade|industry|military|balanced] [--save PATH]")
                    return
                }
                guard !args.isEmpty else { throw GameError.invalid("缺少参数：\(flag)") }
                let value = args.removeFirst()
                switch flag {
                case "--hours":
                    guard let h = Int64(value), (0...8760).contains(h) else { throw GameError.invalid("hours范围") }; hours = h
                case "--policy":
                    guard let p = Policy(rawValue: value) else { throw GameError.invalid("未知方针") }; policy = p
                case "--save": savePath = value
                default: throw GameError.invalid("未知参数：\(flag)")
                }
            }
            let store = savePath.map { SaveStore(fileURL: URL(fileURLWithPath: $0)) }
            var world = try store?.load() ?? (oneCity ? Seed.oneCity(wallUTC: 1_700_000_000) : Seed.threeCityDemo(wallUTC: 1_700_000_000))
            if !oneCity && world.cities.count == 3 && world.districts.isEmpty {
                try GameEngine.apply(.init(id: "demo-district", expectedRevision: world.revision,
                    action: .establishDistrict(id: "east", cityIDs: ["plain", "stone", "river"], governorID: "xunyu")), to: &world)
            }
            let session = try GameSession(world: world, persistence: store)
            try await session.send(.init(id: "policy-\(world.revision)", expectedRevision: world.revision,
                                         action: .setPolicy(scope: .realm, policy: policy)))
            let result = try await session.advance(to: world.lastWallUTC + hours * 3600)
            try await session.save()
            let final = await session.snapshot()
            print("桌面三国·小城志｜开发切片 core-0.1（非完整游戏）")
            print("场景：\(final.cities.count)城；方针：\(policy.title)；模拟：\(result.simulatedSeconds / 3600)小时；休整：\(result.restedSeconds / 3600)小时")
            for city in final.cities.values.sorted(by: { $0.id < $1.id }) {
                let prefect = final.people[city.prefectID]!
                let jobs = city.jobs.keys.sorted().map { "\($0):\(city.jobs[$0]!)" }.joined(separator: ", ")
                print("\(city.name)｜太守：\(prefect.name)｜岗位[\(jobs)]｜粮\(city.inventory[.grain] / 1000) 酒\(city.inventory[.wine] / 1000) 器材\(city.inventory[.tools] / 1000)｜治理XP \(prefect.experience["governance", default: 0])")
            }
            print("最新奏报：")
            for event in final.events.suffix(3) { print("  [\(event.time)s] \(event.message)") }
            print("尚未实现：建造队列、跨城运输、战斗、完整收藏、行情与按键。")
        } catch {
            FileHandle.standardError.write(Data("错误：\(error.localizedDescription)\n".utf8)); exit(1)
        }
    }
}
