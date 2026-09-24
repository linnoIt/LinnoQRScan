//
//  QRAutoZoom.swift
//  QRScan
//
//  自动变焦：把检出的码在预览层中的宽度占比拉进理想区间，
//  改善「码小 / 离得远」时识别慢、识别不出的问题。
//
//  分层（为了可测）：
//  1. QRAutoZoomPolicy       —— 纯决策，不碰 AVFoundation，输入输出都是值类型；
//  2. QRCameraZooming        —— 「改变焦」这一步的抽象，生产实现包装 AVCaptureDevice；
//  3. QRAutoZoomController   —— 串起决策与执行，并负责节流（唯一持有状态的地方）。
//
//  AVCaptureDevice 在单测里无法构造，所以真正需要覆盖的逻辑全部下沉到 1 和 3，
//  测试只需注入一个假 QRCameraZooming，不需要 KVC / runtime 黑魔法。
//

import Foundation
import AVFoundation

// MARK: - 决策策略

/// 自动变焦的决策策略。纯值语义，无副作用、无时间依赖。
struct QRAutoZoomPolicy {

    /// 码宽占预览宽度的理想下限。低于它说明码太小（离得远），需要拉近。
    var idealMinProportion: CGFloat = 0.25

    /// 码宽占预览宽度的理想上限。高于它说明码太大（贴太近），需要推远。
    var idealMaxProportion: CGFloat = 0.45

    /// 单次调整的步进倍率。
    var zoomFactorStep: CGFloat = 0.3

    /// 两次调整之间的最小间隔（秒），避免画面来回推拉。
    var minAdjustmentInterval: TimeInterval = 0.5

    /// 小于该变化量的调整直接丢弃，避免无意义抖动。
    var minChangeThreshold: CGFloat = 0.05

    /// `ramp(toVideoZoomFactor:withRate:)` 的速率。
    var rampRate: Float = 3.0

    /// 一次评估的结论。
    enum Decision: Equatable {
        /// 保持现状，不做任何操作。
        case keep
        /// 平滑变焦到 `factor`，速率为 `rate`。
        case zoom(to: CGFloat, rate: Float)
    }

    /// 根据当前帧里码的尺寸决定是否需要变焦。
    ///
    /// 纯函数：相同输入必然得到相同输出，因此可以被单测穷举边界。
    ///
    /// - Parameters:
    ///   - codeWidthProportion: 码宽 / 预览层宽度。
    ///   - currentZoomFactor: 设备当前变焦倍率。
    ///   - maxZoomFactor: 设备支持的最大变焦倍率；`<= 1` 视为不支持变焦。
    ///   - timeSinceLastAdjustment: 距上次「真正下发成功」的调整过了多久（秒）。
    /// - Returns: `.keep` 或 `.zoom(to:rate:)`。
    func decide(codeWidthProportion: CGFloat,
                currentZoomFactor: CGFloat,
                maxZoomFactor: CGFloat,
                timeSinceLastAdjustment: TimeInterval) -> Decision {

        // 设备不支持变焦（例如某些外接摄像头），任何调整都无意义。
        guard maxZoomFactor > 1.0 else { return .keep }

        // 距上次调整太近，这一帧先不动，避免画面抖动。
        guard timeSinceLastAdjustment >= minAdjustmentInterval else { return .keep }

        let target: CGFloat
        if codeWidthProportion < idealMinProportion, currentZoomFactor < maxZoomFactor {
            // 码太小且还有拉近余量 -> 拉近
            target = min(currentZoomFactor + zoomFactorStep, maxZoomFactor)
        } else if codeWidthProportion > idealMaxProportion, currentZoomFactor > 1.0 {
            // 码太大且还有推远余量 -> 推远
            target = max(currentZoomFactor - zoomFactorStep, 1.0)
        } else {
            // 已落在理想区间，或已顶到变焦边界，保持现状
            return .keep
        }

        // 变化量太小就不下发，省掉一次 lock / unlock
        guard abs(target - currentZoomFactor) > minChangeThreshold else { return .keep }

        return .zoom(to: target, rate: rampRate)
    }

    /// 从当前帧里挑出「参考码」的宽度占比：取最宽的那一个。
    ///
    /// 一帧里可能同时有多个码，以最大的那个作为变焦依据，
    /// 避免被远处的小码把镜头越推越远。
    ///
    /// - Returns: 占比；输入不可用时返回 `nil`（此时上层应跳过本次评估）。
    static func widestProportion(codeWidths: [CGFloat], previewWidth: CGFloat) -> CGFloat? {
        guard previewWidth > 0 else { return nil }
        guard let widest = codeWidths.filter({ $0 > 0 }).max() else { return nil }
        return widest / previewWidth
    }
}

// MARK: - 变焦能力抽象

/// 「改变焦」这一动作的抽象。
///
/// 生产实现是 `QRDeviceZooming`（包装 `AVCaptureDevice`）；
/// 测试实现只需记录被下发的倍率，不依赖任何硬件。
protocol QRCameraZooming: AnyObject {
    /// 设备当前变焦倍率。每次评估都实时读取，不缓存。
    var currentZoomFactor: CGFloat { get }

    /// 设备支持的最大变焦倍率。`<= 1` 表示不支持变焦。
    var maxZoomFactor: CGFloat { get }

    /// 平滑变焦到指定倍率。失败时抛错，由调用方决定是否重试。
    func rampZoom(to factor: CGFloat, rate: Float) throws
}

/// 生产实现：直接操作 `AVCaptureDevice`。
final class QRDeviceZooming: QRCameraZooming {

    private let device: AVCaptureDevice

    init(device: AVCaptureDevice) {
        self.device = device
    }

    var currentZoomFactor: CGFloat {
        // 实时读取：用户手动调用 setZoom 或画面还在 ramp 时，这里拿到的是真实值，
        // 避免控制器持有一份会过期的缓存。
        device.videoZoomFactor
    }

    var maxZoomFactor: CGFloat {
        device.activeFormat.videoMaxZoomFactor
    }

    func rampZoom(to factor: CGFloat, rate: Float) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.ramp(toVideoZoomFactor: factor, withRate: rate)
    }
}

// MARK: - 控制器

/// 自动变焦控制器：把「评估 -> 下发 -> 记录节流时间」收在一处。
///
/// 这是唯一持有状态（上次调整时间）的对象，也是测试的主要目标。
final class QRAutoZoomController {

    /// 开关。默认关闭，避免影响既有接入方的行为。
    var isEnabled: Bool = false

    /// 决策参数，测试里可以替换成更严格的阈值。
    var policy: QRAutoZoomPolicy

    private let zooming: QRCameraZooming

    /// 上次「成功下发」调整的时间。使用 `.distantPast` 保证首次评估一定能通过节流。
    private var lastAdjustmentTime: Date = .distantPast

    init(zooming: QRCameraZooming, policy: QRAutoZoomPolicy = QRAutoZoomPolicy()) {
        self.zooming = zooming
        self.policy = policy
    }

    /// 用当前帧里码的宽度占比评估并执行一次变焦。
    ///
    /// - Parameters:
    ///   - codeWidthProportion: 码宽 / 预览层宽度。
    ///   - now: 当前时间。注入是为了让节流逻辑可以被确定性地测试。
    /// - Returns: 本次的决策结果，便于测试断言与埋点。
    @discardableResult
    func adjust(codeWidthProportion: CGFloat, now: Date = Date()) -> QRAutoZoomPolicy.Decision {
        guard isEnabled else { return .keep }

        let decision = policy.decide(
            codeWidthProportion: codeWidthProportion,
            currentZoomFactor: zooming.currentZoomFactor,
            maxZoomFactor: zooming.maxZoomFactor,
            timeSinceLastAdjustment: now.timeIntervalSince(lastAdjustmentTime)
        )

        guard case .zoom(let target, let rate) = decision else { return decision }

        do {
            try zooming.rampZoom(to: target, rate: rate)
            // 只有下发成功才记录时间。失败时保持原值，允许下一帧立刻重试。
            lastAdjustmentTime = now
        } catch {
            #if DEBUG
            print("LinnoQRScan: 自动变焦下发失败 - \(error)")
            #endif
        }

        return decision
    }
}
