import Foundation

/// Single authorization ledger. This does not mint cash or replace inventory checks.
public struct BudgetLedger: Codable, Equatable, Sendable {
    public let grant: Int64
    public private(set) var spent: Int64 = 0
    public private(set) var reservations: [String: Int64] = [:]
    public var reserved: Int64 { reservations.values.reduce(0, +) }
    public var available: Int64 { grant - spent - reserved }
    public init(grant: Int64) throws {
        guard (0...1_000_000_000).contains(grant) else { throw GameError.invalid("预算上限") }
        self.grant = grant
    }
    public mutating func reserve(id: String, amount: Int64) throws {
        try validate()
        guard !id.isEmpty, id.count <= 80, amount > 0 else { throw GameError.invalid("预留参数") }
        if let old = reservations[id] {
            guard old == amount else { throw GameError.duplicateID }; return
        }
        guard amount <= available else { throw GameError.denied("预算不足") }
        reservations[id] = amount
    }
    public mutating func consume(id: String) throws {
        try validate()
        guard let amount = reservations.removeValue(forKey: id) else { throw GameError.invalid("预留不存在或已消费") }
        spent += amount
    }
    public mutating func release(id: String) throws {
        try validate()
        guard reservations.removeValue(forKey: id) != nil else { throw GameError.invalid("预留不存在") }
    }
    public func validate() throws {
        guard (0...1_000_000_000).contains(grant), (0...grant).contains(spent), reservations.count <= 1000,
              reservations.values.allSatisfy({ (1...1_000_000_000).contains($0) }),
              spent + reserved <= grant else { throw GameError.invalid("预算账本") }
    }
}
