// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Exmen",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.4.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.11.2")
    ],
    targets: [
        .executableTarget(
            name: "Exmen",
            dependencies: [
                "TOMLDecoder",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Exmen"
        )
    ]
)
