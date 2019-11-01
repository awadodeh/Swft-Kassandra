// swift-tools-version:5.0
//
//  Copyright © 2019 Apple, Inc. All rights reserved.
//

import PackageDescription

let package = Package(
    name: "Kassandra",
    products: [
        .library(
            name: "Kassandra",
            targets: ["Kassandra"]),
    ],
    dependencies: [
        .package(url: "https://github.com/IBM-Swift/BlueSSLService.git", from:"1.0.50"),
    ],
    targets: [
        .target(
            name: "Kassandra",
            dependencies: ["SSLService"]),
        .testTarget(
            name: "KassandraTests",
            dependencies: ["Kassandra"]),
    ]
)
