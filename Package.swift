// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BroadMonetization",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "BroadMonetization", targets: ["BroadMonetization"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/BroadApps-official/broad-core-ios.git",
            from: "1.2.0"
        ),
        .package(
            url: "https://github.com/Swinject/Swinject.git",
            exact: "2.10.0"
        ),
        .package(
            url: "https://github.com/adaptyteam/AdaptySDK-iOS.git",
            exact: "3.17.3"
        )
    ],
    targets: [
        .target(name: "BroadMonetization",
            dependencies: [
                .product(name: "BroadCore", package: "broad-core-ios"),
                .product(name: "Swinject", package: "Swinject"),
                .product(
                    name: "Adapty",
                    package: "AdaptySDK-iOS",
                    condition: .when(platforms: [.iOS])
                )
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
