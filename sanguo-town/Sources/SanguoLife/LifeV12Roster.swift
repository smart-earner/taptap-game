import Foundation

/// Additional identities are content, not duplicate bodies. The original
/// thirty definitions remain byte-for-byte intact for old draw receipts.
public struct LifeV12Roster: Decodable, Sendable {
    public struct Entry: Decodable, Sendable {
        public var id:String
        public var name:String
        public var phase:Int
        public var rarity:String
        public var profile:String
        public var attributes:[Int]
    }
    public var version:String
    public var heroes:[Entry]
    public static func load() throws -> LifeV12Roster {
        guard let url=Bundle.module.url(forResource:"hero-town-v0.12-roster",withExtension:"json") else {
            throw LifeError.invalid("v0.12新人内容包缺失")
        }
        let roster=try JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
        guard roster.version=="0.12.0",roster.heroes.count==30,
              Set(roster.heroes.map(\.id)).count==30,
              Set(roster.heroes.map(\.name)).count==30,
              (1...3).allSatisfy({phase in roster.heroes.filter{$0.phase==phase}.count==10}),
              roster.heroes.filter({$0.rarity=="talent"}).count==10,
              roster.heroes.filter({$0.rarity=="renowned"}).count==12,
              roster.heroes.filter({$0.rarity=="legend"}).count==8,
              roster.heroes.allSatisfy({entry in
                  ["talent","renowned","legend"].contains(entry.rarity) &&
                  ["food","supply","craft","logistics","trade","guard"].contains(entry.profile) &&
                  entry.attributes.count==4 && entry.attributes.allSatisfy{(0...100).contains($0)}
              }) else {throw LifeError.invalid("v0.12新人内容包不合法")}
        return roster
    }
}

extension LifeGachaDefinition {
    static func formalV12() throws -> Self {
        var definition=try bundled()
        let roster=try LifeV12Roster.load()
        let originalIDs=Set(definition.heroes.map(\.id))
        guard originalIDs.isDisjoint(with:Set(roster.heroes.map(\.id))) else {throw LifeError.invalid("v0.12新人ID与原卡池冲突")}
        for entry in roster.heroes {
            guard let template=definition.heroes.first(where:{$0.star_profile==entry.profile}) else {
                throw LifeError.invalid("新人缺少岗位技能模板：\(entry.id)")
            }
            let skills=template.skills.enumerated().map { index,skill in
                Skill(id:"\(entry.id).s\(index+1)",unlock_star:skill.unlock_star,kind:skill.kind,
                      jobs:skill.jobs,values_by_star:skill.values_by_star)
            }
            definition.heroes.append(.init(id:entry.id,name:entry.name,rarity:entry.rarity,
                                           star_profile:entry.profile,skills:skills))
        }
        definition.spec_version="0.12.0"
        definition.gacha.pool_version="tavern-standard-v12-p0"
        return definition
    }
}

extension LifeCatalog {
    func withV12Roster(using definition:LifeGachaDefinition) throws -> Self {
        var result=self
        let roster=try LifeV12Roster.load()
        let originalIDs=Set(result.heroes.map(\.id))
        guard originalIDs.isDisjoint(with:Set(roster.heroes.map(\.id))) else {throw LifeError.invalid("v0.12新人ID与生活目录冲突")}
        for entry in roster.heroes {
            guard let templateDefinition=definition.heroes.first(where:{$0.id==entry.id}),
                  let existing=definition.heroes.prefix(30).first(where:{$0.star_profile==templateDefinition.star_profile}),
                  let template=result.hero(existing.id) else {throw LifeError.invalid("新人缺少四维/外形模板：\(entry.id)")}
            result.heroes.append(.init(id:entry.id,name:entry.name,starting:false,
                                       attributes:Dictionary(uniqueKeysWithValues:zip(["administration","strategy","valor","command"],entry.attributes)),
                                       skill_ids:template.skill_ids,art_family:template.art_family,art:template.art))
        }
        return result
    }
}
