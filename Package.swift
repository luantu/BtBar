// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BtBar",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // 蓝牙相关依赖
    ],
    targets: [
        .executableTarget(
            name: "BtBar",
            path: "Sources",
            resources: [
                .copy("../Resources")
            ]
        )
    ]
)