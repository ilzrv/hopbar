// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Hopbar",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "Hopbar", targets: ["Hopbar"])
    ],
    targets: [
        .executableTarget(
            name: "Hopbar"
        ),
        .testTarget(
            name: "HopbarTests",
            dependencies: ["Hopbar"]
        )
    ]
)
