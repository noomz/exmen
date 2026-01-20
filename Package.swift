// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Exmen",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.4.0")
    ],
    targets: [
        .executableTarget(
            name: "Exmen",
            dependencies: ["TOMLDecoder"],
            path: "Exmen"
        )
    ]
)
