// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TabPlusPlus",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TabApp", targets: ["TabApp"]),
        .library(name: "TabCore", targets: ["TabCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", exact: "0.5.5"),
    ],
    targets: [
        .target(
            name: "TabCore",
            dependencies: [
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),
        .executableTarget(
            name: "TabApp",
            dependencies: [
                .target(name: "TabCore"),
            ]
        ),
        .testTarget(
            name: "TabCoreTests",
            dependencies: [
                .target(name: "TabCore"),
            ]
        ),
    ]
)
