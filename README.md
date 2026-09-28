# LinnoQRScan (QRScan)

[![Swift](https://img.shields.io/badge/Swift-5-orange?style=flat-square)](https://img.shields.io/badge/Swift-5-Orange?style=flat-square)
[![Version](https://img.shields.io/cocoapods/v/LinnoQRScan.svg?style=flat)](https://cocoapods.org/pods/LinnoQRScan)
[![License](https://img.shields.io/cocoapods/l/LinnoQRScan.svg?style=flat)](https://cocoapods.org/pods/LinnoQRScan)
[![Platform:iOS 12.0](https://img.shields.io/cocoapods/p/LinnoQRScan.svg?style=flat)](https://cocoapods.org/pods/LinnoQRScan)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen?style=flat-square)](#安装)

基于 `AVCaptureSession` / `AVMetadataOutput` 的轻量扫描组件，支持二维码、一维条码与人体 / 猫狗识别。

## 功能

1. 支持 Objective-C 调用（提供 `@objc` 初始化入口，回调参数为 `Int` 而非 Swift 枚举）
2. 支持快速接入：一个初始化方法完成相机装配与预览挂载
3. 识别成功播放提示音（"滴"）与震动，可通过 `playSource` 关闭
4. session 的启动 / 停止在后台串行队列执行，不阻塞主线程
5. 支持手动调整焦距：`setZoom(factor:)` / `currentZoomLevel()`
6. 支持暂停与恢复扫描：`pause(_:)`
7. 支持自定义预览 `bounds` 与扫描区域 `scanFrame`
8. 支持自定义识别类型：`scanState` 组合，或 `supportCodeTypes` 完全指定
9. 支持开启广角：`turnWideAngle`
10. 支持自动变焦：按码在预览中的占比自动推近 / 拉远，见下文
11. 支持手电控制：`toggleTorch(mode:)` / `isTorchOn()`

## 环境要求

- iOS 12.0+
- Swift 5.0
- 相机权限描述（`NSCameraUsageDescription`），首次调用时会弹出系统授权框

## 安装

支持 **CocoaPods** 与 **Swift Package Manager** 两种方式，**在同一个工程里二选一**。
两条渠道共用同一份源码与同一套版本号（同一个版本号 = 同一份代码）。

> ⚠️ 不要在同一个 target 里同时用 pod 和 SPM 引入本库：两者生成同一个模块 `LinnoQRScan`，会冲突。

### Swift Package Manager

Xcode → `File` → `Add Package Dependencies…`，填入仓库地址：

```
https://github.com/linnoIt/LinnoQRScan.git
```

或在 `Package.swift` 中声明依赖：

```swift
.package(url: "https://github.com/linnoIt/LinnoQRScan.git", from: "0.2.7")
```

> SPM **从 0.2.7 起**支持。更早的 tag 里没有 `Package.swift`，SPM 拉不到。

### CocoaPods

LinnoQRScan is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'LinnoQRScan'
```

## 用法

```swift
import LinnoQRScan

let proxy = QRProxy(
    showView: view,
    scanFrame: scanFrame,          // nil 表示用整个 bounds
    fpsNum: 1,                     // 1 = 单帧直接回调；>= 2 在预览上画框、点击框回调
    scanState: .All,               // 或 .Barcodes / .Codes2D / .Bodies 等组合
    playSource: true,
    supportCodeTypes: nil,         // 传值则覆盖 scanState 的默认类型集合
    turnWideAngle: false
) { text, state in
    print(text, state)
}

// 按需开启自动变焦（默认关闭）
proxy.isAutoFocusZoomEnabled = true
```

### 自动变焦

开启后，识别到码时会以「码宽 / 预览层宽度」为依据自动调整倍率：

| 占比 | 行为 |
|---|---|
| < 25% | 逐步推近 |
| 25% ~ 45% | 保持不动（理想区间，闭区间） |
| > 45% | 逐步拉远 |

- 单次步进 `0.3`，两次调整至少间隔 `0.5 秒`，变化量小于 `0.05` 不下发
- 倍率上限为设备的 `activeFormat.videoMaxZoomFactor`，下限为 `1.0`
- 一帧出现多个码时，以**最宽的那个**作为依据
- 自动变焦与手动 `setZoom(factor:)` 互斥：开启自动变焦后请不要再手动设定倍率

### 注意事项

- `stop()` 是**异步**的：它把停止动作投递到内部串行队列后立即返回，不等待设备真正停止。不要假设 "`stop()` 返回 = 相机已释放"。
- 开自动变焦 + 多帧模式（`fpsNum >= 2`）时，变焦动画会让已绘制的识别框与码之间产生轻微偏移，下一次识别结果产出时会被重绘。

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

```bash
cd Example && pod install
open QRScan.xcworkspace
```

## 测试

CocoaPods 渠道（Example 工程，含人工测试台）：

```bash
cd Example
xcodebuild test -workspace QRScan.xcworkspace -scheme QRScan-Example \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

SPM 渠道（直接对 Package 跑，24 例）：

```bash
xcodebuild test -scheme LinnoQRScan \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.0' \
  CODE_SIGNING_ALLOWED=NO
```

> 该库依赖 UIKit / AVFoundation，**不能用 `swift test` / `swift build`**（那只面向 macOS 宿主机），必须用 `xcodebuild` 指定 iOS 模拟器。

## 发版（双渠道）

两条渠道共用**同一个 git tag**：SPM 的版本来自 tag，podspec 的 `:tag => s.version.to_s` 也指向它。
因此发版顺序是固定的——**先打 tag，再按需发布各渠道**：

```bash
# 1) 发版前预检：podspec 版本 / 模块名 / 部署目标 是否与 Package.swift 自洽
Scripts/check-release-consistency.sh --worktree

# 2) 打 tag 并推送（这一步同时解锁 SPM 与 CocoaPods 两条渠道）
git tag 0.2.7 && git push origin 0.2.7

# 3) 此时 SPM 已可用；CocoaPods 渠道在你想发布时再推
pod trunk push LinnoQRScan.podspec

# 4) 发版终检
Scripts/check-release-consistency.sh 0.2.7
```

注意：

- **tag 一旦推送就不可移动**。SPM 按 tag 缓存，改 tag 会让所有使用方解析失败；有改动就发下一个版本号。
- 两条渠道的"当前最新可获取版本"可以短暂不同（如 SPM 已到 `0.2.7`、pod 还停在 `0.2.6`），但**同一个版本号在两边的代码永远一致**。
- 改了 `s.version` 却没打 tag（或反之）会被 `Scripts/check-release-consistency.sh` 拦下。

## Author

linnoIt, it@linno.cn

## License

QRScan is available under the MIT license. See the LICENSE file for more info.
