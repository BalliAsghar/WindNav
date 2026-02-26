// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WindNav",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WindNav", targets: ["WindNavApp"]),
        .library(name: "WindNavCore", targets: ["WindNavCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", exact: "0.5.5"),
    ],
    targets: [
        .target(
            name: "WindNavCore",
            dependencies: [
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
        ),
        .executableTarget(
            name: "WindNavApp",
            dependencies: [
                .target(name: "WindNavCore"),
            ],
        ),
        .testTarget(
            name: "WindNavCoreTests",
            dependencies: [
                .target(name: "WindNavCore"),
            ],
        ),
    ],
)
