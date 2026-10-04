// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EndfieldCharge",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ChargeCore", targets: ["ChargeCore"]),
        .executable(name: "EndfieldCharge", targets: ["EndfieldCharge"])
    ],
    targets: [
        .target(name: "ChargeCore"),
        .executableTarget(name: "EndfieldCharge", dependencies: ["ChargeCore"]),
        .testTarget(name: "ChargeCoreTests", dependencies: ["ChargeCore"])
    ]
)
