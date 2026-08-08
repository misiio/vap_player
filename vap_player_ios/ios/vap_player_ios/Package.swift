// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "vap_player_ios",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(name: "vap-player-ios", targets: ["vap_player_ios"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/misiio/vap.git",
            exact: "1.0.19-spm"
        )
    ],
    targets: [
        .target(
            name: "vap_player_ios",
            dependencies: [
                .product(name: "QGVAPlayer", package: "vap")
            ]
        )
    ]
)
