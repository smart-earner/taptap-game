import Foundation

public protocol WorldPersistence: Sendable {
    func save(_ world: WorldState) throws
}
public struct SaveStore: WorldPersistence, Sendable {
    public let fileURL: URL
    public static let maximumBytes = 8 * 1024 * 1024
    public init(fileURL: URL) { self.fileURL = fileURL }
    private struct Envelope: Codable { let version: Int; let payload: String; let checksum: String }
    /// FNV-1a is an accidental-corruption check only, NOT a security signature.
    private static func checksum(_ bytes: Data) -> String {
        let hash = bytes.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }
    public static func encode(_ world: WorldState) throws -> Data {
        try world.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(world)
        let data = try encoder.encode(Envelope(version: 1, payload: String(decoding: payload, as: UTF8.self), checksum: checksum(payload)))
        guard data.count <= maximumBytes else { throw GameError.invalid("存档超过8MB原型上限") }
        return data
    }
    public static func decode(_ data: Data) throws -> WorldState {
        guard data.count <= maximumBytes else { throw GameError.invalid("存档过大") }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        let payload = Data(envelope.payload.utf8)
        guard envelope.version == 1, envelope.checksum == checksum(payload) else { throw GameError.invalid("存档版本或完整性校验失败") }
        let world = try JSONDecoder().decode(WorldState.self, from: payload)
        try world.validate(); return world
    }
    public var backupURLs: [URL] { (1...3).map { fileURL.appendingPathExtension("bak\($0)") } }
    public func load() throws -> WorldState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= Self.maximumBytes else { throw GameError.invalid("存档过大") }
        // A damaged primary is an error, never an automatic empty world or silent rollback.
        return try Self.decode(Data(contentsOf: fileURL))
    }
    public func save(_ world: WorldState) throws {
        let data = try Self.encode(world), fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: fileURL.path) {
            _ = try load() // Refuse to overwrite a corrupt primary.
            for index in stride(from: 2, through: 1, by: -1) {
                let source = backupURLs[index - 1], destination = backupURLs[index]
                if fm.fileExists(atPath: source.path) { try Data(contentsOf: source).write(to: destination, options: .atomic) }
            }
            try Data(contentsOf: fileURL).write(to: backupURLs[0], options: .atomic)
        }
        try data.write(to: fileURL, options: .atomic)
    }
}

public actor GameSession {
    private var world: WorldState
    private let persistence: (any WorldPersistence)?
    public init(world: WorldState, persistence: (any WorldPersistence)? = nil) throws {
        try world.validate(); self.world = world; self.persistence = persistence
    }
    public func snapshot() -> WorldState { world }
    @discardableResult
    public func send(_ command: GameCommand) throws -> Receipt {
        var draft = world
        let receipt = try GameEngine.apply(command, to: &draft)
        if draft != world { try persistence?.save(draft); world = draft }
        return receipt
    }
    @discardableResult
    public func advance(to wallUTC: Int64) throws -> AdvanceResult {
        var draft = world
        let result = try GameEngine.advance(to: wallUTC, world: &draft)
        if draft != world { try persistence?.save(draft); world = draft }
        return result
    }
    public func save() throws { try persistence?.save(world) }
}
