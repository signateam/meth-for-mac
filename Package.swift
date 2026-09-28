// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Meth",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Meth", targets: ["Meth"]),
        .executable(name: "MethDealer", targets: ["MethDealer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "MethShared"),
        .executableTarget(name: "Meth", dependencies: ["MethShared", .product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "MethDealer", dependencies: ["MethShared"]),
    ]
)
