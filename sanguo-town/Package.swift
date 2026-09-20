// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .library(name: "SanguoCore", targets: ["SanguoCore"]),
    .executable(name:"SanguoGrowth",targets:["SanguoGrowth"]),
    .executable(name: "SanguoCLI", targets: ["SanguoCLI"]),
    .library(name: "SanguoPresentation", targets: ["SanguoPresentation"]),
    .executable(name: "SanguoPreview", targets: ["SanguoPreview"])
]
var targets: [Target] = [
    .target(name: "SanguoCore"),
    .executableTarget(name:"SanguoGrowth",dependencies:["SanguoCore","SanguoPresentation"]),
    .target(name: "SanguoPresentation", dependencies: ["SanguoCore"]),
    .executableTarget(name: "SanguoPreview", dependencies: ["SanguoPresentation"]),
    .testTarget(name: "SanguoPresentationTests", dependencies: ["SanguoPresentation"]),
    .executableTarget(name: "SanguoCLI", dependencies: ["SanguoCore"]),
    .testTarget(name: "SanguoCoreTests", dependencies: ["SanguoCore"])
]
#if os(macOS)
products.append(.executable(name: "SanguoMac", targets: ["SanguoMac"]))
targets.append(.target(name: "SanguoDesktopHost", dependencies: ["SanguoPresentation"]))
targets.append(.testTarget(name: "SanguoDesktopHostTests", dependencies: ["SanguoDesktopHost", "SanguoPresentation"]))
targets.append(.executableTarget(name: "SanguoMac", dependencies: ["SanguoCore", "SanguoPresentation", "SanguoDesktopHost"]))
#endif
let package = Package(name: "SanguoTown", platforms: [.macOS(.v15)],
                      products: products, targets: targets, swiftLanguageModes: [.v6])
