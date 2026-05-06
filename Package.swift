// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fledge-json",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.12.0"),
    ],
    targets: [
        .target(name: "JsonLib", path: "Sources/JsonLib"),
        .executableTarget(name: "fledge-json", dependencies: ["JsonLib"], path: "Sources", exclude: ["JsonLib"]),
        .testTarget(
            name: "JsonTests",
            dependencies: [
                "JsonLib",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests"
        ),
    ]
)
