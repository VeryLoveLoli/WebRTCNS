// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WebRTCNS",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "WebRTCNS",
            targets: ["WebRTCNSSwift"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://gitee.com/cchsora/Print", .branch("master")),
        .package(url: "https://gitee.com/cchsora/AudioInfo", .branch("master")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "WebRTCNS",
            dependencies: []),
        .target(
            name: "WebRTCNSSwift",
            dependencies: ["WebRTCNS", "Print", "AudioInfo"]),
        .testTarget(
            name: "WebRTCNSTests",
            dependencies: ["WebRTCNS"]),
    ]
)
