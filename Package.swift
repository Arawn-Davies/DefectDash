// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DefectDash",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DefectDashCore", targets: ["DefectDashCore"]),
        .executable(name: "DefectDash", targets: ["DefectDash"]),
        // Named differently from "DefectDash" in more than case: both products land in one build directory
        // on a case-insensitive filesystem. The Makefile installs it as `defectdash`.
        .executable(name: "defectdash-tui", targets: ["DefectDashTUI"]),
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
        .executableTarget(
            name: "DefectDashTUI",
            dependencies: ["DefectDashCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DefectDashTUITests",
            dependencies: ["DefectDashTUI"],
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
