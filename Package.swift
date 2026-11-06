// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DefectDash",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DefectDashCore", targets: ["DefectDashCore"]),
        .executable(name: "DefectDash", targets: ["DefectDash"]),
    ],
    targets: [
        .target(
            name: "DefectDashCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "DefectDash",
            dependencies: ["DefectDashCore"],
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DefectDashCoreTests",
            dependencies: ["DefectDashCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
