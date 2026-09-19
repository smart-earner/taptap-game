// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .library(name: "SanguoCore", targets: ["SanguoCore"]),
    .executable(name: "SanguoCLI", targets: ["SanguoCLI"])
]
var targets: [Target] = [
    .target(name: "SanguoCore"),
    .executableTarget(name: "SanguoCLI", dependencies: ["SanguoCore"]),
    .testTarget(name: "SanguoCoreTests", dependencies: ["SanguoCore"])
]
#if os(macOS)
products.append(.executable(name: "SanguoMac", targets: ["SanguoMac"]))
targets.append(.executableTarget(name: "SanguoMac", dependencies: ["SanguoCore"]))
#endif
let package = Package(name: "SanguoTown", platforms: [.macOS(.v15)],
                      products: products, targets: targets, swiftLanguageModes: [.v6])
