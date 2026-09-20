import Foundation

extension LifeRules {
    /// The installed app carries an explicit resource file; CLI/tests use SwiftPM's bundle.
    public static func loadForApplication() throws -> Self {
        if let url=Bundle.main.resourceURL?.appendingPathComponent("life-rules.json"),
           FileManager.default.fileExists(atPath:url.path) {
            let rules=try JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
            try rules.validate();return rules
        }
        return try load()
    }
}
