// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "fledge-json",
    targets: [
        .executableTarget(
            name: "fledge-json",
            path: "Sources"
        ),
    ]
)
