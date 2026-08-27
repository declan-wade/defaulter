// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Defaulter",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DefaulterKit", targets: ["DefaulterKit"]),
        .executable(name: "Defaulter", targets: ["Defaulter"]),
    ],
    targets: [
        .target(
            name: "DefaulterKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Defaulter",
            dependencies: ["DefaulterKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
