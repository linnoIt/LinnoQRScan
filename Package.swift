// swift-tools-version:5.7
//
// LinnoQRScan —— 同时支持 CocoaPods 与 Swift Package Manager。
//
// ⚠️ 不要把 tools 版本抬到 6.x：本仓库为 Swift 6 工具链编译时会默认进入
//    「Swift 6 严格并发」模式，与 AVCaptureMetadataOutput 委托 + @objc 的写法冲突。
//    这里显式声明 swiftLanguageVersions: [.v5]，与 podspec 的 swift_version = 5.0 对齐。
//
// ⚠️ 版本号不在这里写：SPM 的版本来自 git tag，podspec 的 s.version 也取自同一个 tag，
//    两者共用一套裸版本号（0.1.0 / 0.2.6 / …），保证「同一个版本号 = 同一份代码」。

import PackageDescription

let package = Package(
    name: "LinnoQRScan",
    platforms: [
        .iOS(.v12)          // 与 podspec 的 s.ios.deployment_target = '12.0' 保持一致
    ],
    products: [
        .library(
            name: "LinnoQRScan",
            targets: ["LinnoQRScan"]
        )
    ],
    targets: [
        // 零移动：直接指向 podspec 中 s.source_files 的同一批源码，
        // 两个包管理器共用单一数据源，避免两边代码漂移。
        .target(
            name: "LinnoQRScan",
            path: "QRScan/Classes"
        ),
        // 零重复：复用 Example/Tests 下只依赖本库的两个测试文件。
        // ManualTestKitTests 依赖 Example App 内的 ManualTestKit，故排除；
        // 人工测试台（ManualTestPanel 等）仍只在 Example 工程里跑。
        .testTarget(
            name: "LinnoQRScanTests",
            dependencies: ["LinnoQRScan"],
            path: "Example/Tests",
            exclude: ["Info.plist", "ManualTestKitTests.swift"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
