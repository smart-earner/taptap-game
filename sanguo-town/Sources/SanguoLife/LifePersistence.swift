import Foundation

public protocol LifePersistence: Sendable {func save(_ world:LifeWorld) throws}
public struct LifeSaveStore: LifePersistence, Sendable {
    public let url: URL
    public init(url:URL){self.url=url}
    private struct Envelope: Codable {let format:Int;let payload:String;let checksum:String}
    private static func checksum(_ data:Data)->String {String(data.reduce(UInt64(14695981039346656037)){($0 ^ UInt64($1)) &* 1099511628211},radix:16)}
    public static func encode(_ world:LifeWorld) throws -> Data {
        try world.validate();let e=JSONEncoder();e.outputFormatting=[.sortedKeys]
        let bytes=try e.encode(world)
        let data=try e.encode(Envelope(format:1,payload:String(decoding:bytes,as:UTF8.self),checksum:checksum(bytes)))
        guard data.count<=16*1024*1024 else{throw LifeError.invalid("生活版存档超过16MB安全上限")};return data
    }
    public static func decode(_ data:Data) throws -> LifeWorld {
        guard data.count<=16*1024*1024 else{throw LifeError.invalid("存档过大")}
        let envelope=try JSONDecoder().decode(Envelope.self,from:data),bytes=Data(envelope.payload.utf8)
        guard envelope.format==1,envelope.checksum==checksum(bytes) else{throw LifeError.invalid("存档完整性失败，未清空或回退")}
        let world=try JSONDecoder().decode(LifeWorld.self,from:bytes);try world.validate();return world
    }
    public func load() throws -> LifeWorld? {
        let fm=FileManager.default
        guard fm.fileExists(atPath:url.path) else{return nil}
        let a=try fm.attributesOfItem(atPath:url.path)
        guard (a[.size] as? NSNumber)?.intValue ?? Int.max <= 16*1024*1024 else{throw LifeError.invalid("存档过大")}
        return try Self.decode(Data(contentsOf:url))
    }
    public func save(_ world:LifeWorld) throws {
        let bytes=try Self.encode(world),fm=FileManager.default
        try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        if fm.fileExists(atPath:url.path) {
            let previousBytes=try Data(contentsOf:url)
            let previous=try Self.decode(previousBytes)
            if previous.isFormalHeroTown && !previous.isCurrentHeroTown && world.isCurrentHeroTown {
                // Rotating backups are overwritten by ordinary autosaves. Keep the exact
                // pre-upgrade bytes in a content-addressed archive that rotation never touches.
                let archive=url.appendingPathExtension("pre-v012-\(Self.checksum(previousBytes))")
                if fm.fileExists(atPath:archive.path) {
                    guard try Data(contentsOf:archive)==previousBytes else {
                        throw LifeError.invalid("旧版存档归档校验失败，未覆盖原档")
                    }
                } else {
                    try previousBytes.write(to:archive,options:.atomic)
                }
            }
            for i in stride(from:2,through:1,by:-1) {let source=url.appendingPathExtension("bak\(i)");if fm.fileExists(atPath:source.path){try Data(contentsOf:source).write(to:url.appendingPathExtension("bak\(i+1)"),options:.atomic)}}
            try previousBytes.write(to:url.appendingPathExtension("bak1"),options:.atomic)
        }
        try bytes.write(to:url,options:.atomic)
    }
    public func availableBackups() -> [Int] {
        (1...3).filter{FileManager.default.fileExists(atPath:url.appendingPathExtension("bak\($0)").path)}
    }
    /// Recovery is deliberately explicit.  The current bytes are preserved before a
    /// validated backup replaces them, even when the current file is corrupt.
    public func restoreBackup(_ index:Int,confirmed:Bool) throws -> LifeWorld {
        guard confirmed,(1...3).contains(index) else{throw LifeError.invalid("恢复备份需要明确确认")}
        let backup=url.appendingPathExtension("bak\(index)")
        guard FileManager.default.fileExists(atPath:backup.path) else{throw LifeError.invalid("备份不存在")}
        let bytes=try Data(contentsOf:backup),world=try Self.decode(bytes)
        let fm=FileManager.default
        if fm.fileExists(atPath:url.path) {
            let stamp=Int64(Date().timeIntervalSince1970)
            try Data(contentsOf:url).write(to:url.appendingPathExtension("before-restore-\(stamp)"),options:.atomic)
        }
        try bytes.write(to:url,options:.atomic)
        return world
    }
}
public enum LifeCommand: Sendable {case husbandry(Bool),policy(String),seal,recruit(String?),growth(Bool),rations(Int64),prefect(String),heroPreference(String,String),previewStep,gacha(LifeGachaRequest)}
/// Serial actor publishes a candidate only after persistence succeeds.
public actor LifeSession {
    private var engine:LifeRuntime
    private let store:(any LifePersistence)?
    public init(engine:LifeRuntime,store:(any LifePersistence)?=nil){self.engine=engine;self.store=store}
    public func snapshot()->LifeWorld {engine.world}
    public func save() throws {try store?.save(engine.world)}
    public func advance(wallUTC:Int64) throws {
        guard wallUTC>engine.world.wallUTC else{return}
        var draft=engine
        let delta=min(2_592_000,wallUTC-draft.world.wallUTC)
        try draft.advance(to:draft.world.time+delta);draft.world.wallUTC=wallUTC
        try store?.save(draft.world);engine=draft
    }
    public func send(_ command:LifeCommand) throws {
        var draft=engine
        if draft.world.isGacha {
            switch command {
            case .gacha:break
            case .previewStep where !draft.world.isFormalHeroTown:break
            default:throw LifeError.invalid("DENIED_SCOPE：城务由太守安排；玩家只开放招募与手动培养")
            }
        }
        switch command {
        case .gacha(let request):_ = try draft.performGacha(request)
        case .heroPreference(let id,let job):try draft.setHeroPreference(id,job)
        case .previewStep:
            guard draft.world.isHeroPreview else{throw LifeError.invalid("仅试玩支持演示推进")}
            try draft.advance(to:draft.world.time+60)
        case .husbandry(let enabled):try draft.setHusbandry(enabled:enabled)
        case .policy(let p):try draft.setPolicy(p)
        case .seal:try draft.requestSeal()
        case .recruit(let id):try draft.requestRecruit(id)
        case .growth(let value):draft.world.growthEnabled=value
        case .prefect(let id):
            guard !draft.world.isHeroPreview else{throw LifeError.invalid("五将试玩暂未开放调任")}
            guard draft.world.owned.contains(id),let person=draft.world.agents[id],person.heroID != nil,person.taskID==nil else{throw LifeError.invalid("请在已加入人物完成当前任务后调任")}
            draft.world.agents[draft.world.prefect]?.job="flex"
            draft.world.prefect=id;draft.world.agents[id]!.job="prefect"
            draft.world.record("appointment","\(person.name)接任本城太守，已开始工序保留原效率快照。")
        case .rations(let quantity):guard quantity>=0 && quantity<=160000 else{throw LifeError.invalid("军粮试制目标必须在0—160份")};draft.world.rationTarget=quantity
        }
        try draft.world.validate();try store?.save(draft.world);engine=draft
    }
}
