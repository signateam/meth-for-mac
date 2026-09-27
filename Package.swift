// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Meth",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Meth", targets: ["Meth"]),
        .executable(name: "MethDealer", targets: ["MethDealer"]),
    ],
    targets: [
        .target(name: "MethShared"),
        .executableTarget(name: "Meth", dependencies: ["MethShared"]),
        .executableTarget(name: "MethDealer", dependencies: ["MethShared"]),
    ]
)
