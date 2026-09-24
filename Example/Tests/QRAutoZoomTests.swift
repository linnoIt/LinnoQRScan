//
//  QRAutoZoomTests.swift
//  QRScan_Tests
//
//  自动变焦的单元测试。
//
//  这些用例能跑起来的原因只有一个：QRAutoZoomController 依赖的是 QRCameraZooming 协议，
//  而不是具体的 AVCaptureDevice。测试注入一个假实现即可，不需要用 KVC 去改私有属性
//  （KVC 对纯 Swift 的 private 属性会直接抛 NSUnknownKeyException），也不依赖真机。
//

import XCTest
@testable import LinnoQRScan

final class QRAutoZoomTests: XCTestCase {

    // MARK: - 测试替身

    /// 假的可变焦设备：只记录被下发的指令，不碰任何硬件。
    private final class FakeZooming: QRCameraZooming {
        var currentZoomFactor: CGFloat
        let maxZoomFactor: CGFloat
        var rampError: Error?

        private(set) var rampCalls: [CGFloat] = []
        private(set) var rampRates: [Float] = []

        init(currentZoomFactor: CGFloat = 1.0, maxZoomFactor: CGFloat = 5.0) {
            self.currentZoomFactor = currentZoomFactor
            self.maxZoomFactor = maxZoomFactor
        }

        func rampZoom(to factor: CGFloat, rate: Float) throws {
            rampCalls.append(factor)
            rampRates.append(rate)
            if let error = rampError { throw error }
            // 真机 ramp 结束后停在新倍率上，假设备照做，保证连续评估的行为贴近真机
            currentZoomFactor = factor
        }
    }

    private struct FakeError: Error {}

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeController(_ fake: FakeZooming, enabled: Bool = true) -> QRAutoZoomController {
        let controller = QRAutoZoomController(zooming: fake)
        controller.isEnabled = enabled
        return controller
    }

    /// 断言决策是「变焦到某倍率」，并顺带校验速率。
    private func assertZoom(_ decision: QRAutoZoomPolicy.Decision,
                            to expected: CGFloat,
                            rate expectedRate: Float = 3.0,
                            file: StaticString = #filePath,
                            line: UInt = #line) {
        guard case .zoom(let factor, let rate) = decision else {
            XCTFail("期望 .zoom，实际是 \(decision)", file: file, line: line)
            return
        }
        XCTAssertEqual(factor, expected, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(rate, expectedRate, accuracy: 1e-6, file: file, line: line)
    }

    // MARK: - 纯决策：阈值与边界

    /// 设备本身不支持变焦（最大倍率 <= 1）时，任何情况下都不该下发指令。
    func testDeviceWithoutZoomSupportNeverAdjusts() {
        let policy = QRAutoZoomPolicy()
        let decision = policy.decide(codeWidthProportion: 0.01,
                                     currentZoomFactor: 1.0,
                                     maxZoomFactor: 1.0,
                                     timeSinceLastAdjustment: 100)
        XCTAssertEqual(decision, .keep)
    }

    /// 码太小（占比低于下限）-> 按步进拉近。
    func testSmallCodeZoomsInByOneStep() {
        let policy = QRAutoZoomPolicy()
        let decision = policy.decide(codeWidthProportion: 0.10,
                                     currentZoomFactor: 1.0,
                                     maxZoomFactor: 5.0,
                                     timeSinceLastAdjustment: 100)
        assertZoom(decision, to: 1.3)
    }

    /// 码太大（占比高于上限）-> 按步进推远。
    func testLargeCodeZoomsOutByOneStep() {
        let policy = QRAutoZoomPolicy()
        let decision = policy.decide(codeWidthProportion: 0.90,
                                     currentZoomFactor: 2.0,
                                     maxZoomFactor: 5.0,
                                     timeSinceLastAdjustment: 100)
        assertZoom(decision, to: 1.7)
    }

    /// 理想区间是闭区间：正好等于上下限时都不动。
    func testIdealRangeIsKept() {
        let policy = QRAutoZoomPolicy()
        for proportion in [0.25, 0.35, 0.45] as [CGFloat] {
            let decision = policy.decide(codeWidthProportion: proportion,
                                         currentZoomFactor: 2.0,
                                         maxZoomFactor: 5.0,
                                         timeSinceLastAdjustment: 100)
            XCTAssertEqual(decision, .keep, "占比 \(proportion) 应落在理想区间内")
        }
    }

    /// 拉近不会越过设备上限。
    func testZoomInStopsAtMaxZoomFactor() {
        let policy = QRAutoZoomPolicy()
        let decision = policy.decide(codeWidthProportion: 0.05,
                                     currentZoomFactor: 4.9,
                                     maxZoomFactor: 5.0,
                                     timeSinceLastAdjustment: 100)
        assertZoom(decision, to: 5.0)
    }

    /// 推远不会低于 1.0 倍。
    func testZoomOutStopsAtMinimumOne() {
        let policy = QRAutoZoomPolicy()
        let decision = policy.decide(codeWidthProportion: 0.95,
                                     currentZoomFactor: 1.1,
                                     maxZoomFactor: 5.0,
                                     timeSinceLastAdjustment: 100)
        assertZoom(decision, to: 1.0)
    }

    /// 已经在最小倍率上、码又太大时，不能再推远，保持现状。
    func testCannotZoomOutBelowOne() {
        let policy = QRAutoZoomPolicy()
        let decision = policy.decide(codeWidthProportion: 0.95,
                                     currentZoomFactor: 1.0,
                                     maxZoomFactor: 5.0,
                                     timeSinceLastAdjustment: 100)
        XCTAssertEqual(decision, .keep)
    }

    /// 变化量小于阈值时丢弃，避免贴着上限反复下发无意义的指令。
    func testChangeSmallerThanThresholdIsDiscarded() {
        let policy = QRAutoZoomPolicy()
        // 4.97 -> 目标 5.0，变化 0.03，小于 0.05 的阈值
        let decision = policy.decide(codeWidthProportion: 0.05,
                                     currentZoomFactor: 4.97,
                                     maxZoomFactor: 5.0,
                                     timeSinceLastAdjustment: 100)
        XCTAssertEqual(decision, .keep)
    }

    // MARK: - 控制器：开关与节流

    /// 开关关闭时什么都不做 —— 这是默认状态，保证不影响既有接入方。
    func testDisabledControllerDoesNotTouchDevice() {
        let fake = FakeZooming()
        let controller = makeController(fake, enabled: false)

        let decision = controller.adjust(codeWidthProportion: 0.05, now: t0)

        XCTAssertEqual(decision, .keep)
        XCTAssertTrue(fake.rampCalls.isEmpty, "关闭状态下不应下发任何变焦指令")
    }

    /// 首次评估不受节流限制（上次调整时间初始化为 distantPast）。
    func testFirstEvaluationIsNotThrottled() {
        let fake = FakeZooming()
        let controller = makeController(fake)

        controller.adjust(codeWidthProportion: 0.10, now: t0)

        XCTAssertEqual(fake.rampCalls.count, 1)
        XCTAssertEqual(fake.rampCalls.first ?? 0, 1.3, accuracy: 1e-9)
    }

    /// 间隔不足 0.5 秒时不允许再次调整。
    func testAdjustmentIsThrottledWithinInterval() {
        let fake = FakeZooming()
        let controller = makeController(fake)

        controller.adjust(codeWidthProportion: 0.10, now: t0)
        let throttled = controller.adjust(codeWidthProportion: 0.10, now: t0.addingTimeInterval(0.2))

        XCTAssertEqual(throttled, .keep)
        XCTAssertEqual(fake.rampCalls.count, 1, "0.2 秒内不应产生第二次调整")
    }

    /// 正好到 0.5 秒边界时允许调整 —— 这里把边界语义钉死。
    func testAdjustmentAllowedAtExactlyTheIntervalBoundary() {
        let fake = FakeZooming()
        let controller = makeController(fake)

        controller.adjust(codeWidthProportion: 0.10, now: t0)
        controller.adjust(codeWidthProportion: 0.10, now: t0.addingTimeInterval(0.5))

        XCTAssertEqual(fake.rampCalls.count, 2)
        XCTAssertEqual(fake.rampCalls.last ?? 0, 1.6, accuracy: 1e-9)
    }

    /// 下发失败不应消耗节流窗口，否则一次瞬时失败要等 0.5 秒才能重试。
    func testFailedRampDoesNotConsumeThrottleWindow() {
        let fake = FakeZooming()
        fake.rampError = FakeError()
        let controller = makeController(fake)

        // 连续两次失败（同一时刻）：第二次仍会尝试下发，说明失败没把节流时钟推走
        controller.adjust(codeWidthProportion: 0.10, now: t0)
        controller.adjust(codeWidthProportion: 0.10, now: t0)
        XCTAssertEqual(fake.rampCalls.count, 2, "失败后应允许立即重试")

        // 对照：成功一次之后，同一时刻再评估就应被节流挡住
        fake.rampError = nil
        controller.adjust(codeWidthProportion: 0.10, now: t0)
        XCTAssertEqual(fake.rampCalls.count, 3)

        controller.adjust(codeWidthProportion: 0.10, now: t0)
        XCTAssertEqual(fake.rampCalls.count, 3, "成功之后 0.5 秒内不应再下发")
    }

    /// 每次评估都实时读取设备倍率，不缓存 —— 用户手动改过倍率后不会按旧值决策。
    func testControllerReadsZoomFactorLiveFromDevice() {
        let fake = FakeZooming(currentZoomFactor: 1.0)
        let controller = makeController(fake)

        controller.adjust(codeWidthProportion: 0.10, now: t0) // 1.0 -> 1.3
        // 模拟外部（用户手动 / ramp 中途 / 设备自身钳制）把倍率改到 3.0
        fake.currentZoomFactor = 3.0
        controller.adjust(codeWidthProportion: 0.10, now: t0.addingTimeInterval(1))

        XCTAssertEqual(fake.rampCalls.last ?? 0, 3.3, accuracy: 1e-9)
    }

    /// 端到端收敛：码的占比随倍率线性放大，反复评估后应稳定落在理想区间内并停止调整。
    func testRepeatedEvaluationConvergesAndThenStops() {
        let fake = FakeZooming(currentZoomFactor: 1.0, maxZoomFactor: 5.0)
        let controller = makeController(fake)

        let baseProportionAtOneX: CGFloat = 0.10   // 1.0 倍时码宽占预览的 10%
        var time = t0

        // 最多评估 30 次（每次间隔 1 秒，远超 0.5 秒的节流窗口）
        for _ in 0..<30 {
            let proportion = baseProportionAtOneX * fake.currentZoomFactor
            controller.adjust(codeWidthProportion: proportion, now: time)
            time = time.addingTimeInterval(1)
        }

        let settledZoom = fake.currentZoomFactor
        let settledProportion = baseProportionAtOneX * settledZoom

        XCTAssertGreaterThanOrEqual(settledProportion, 0.25 - 1e-6, "应收敛到理想区间内")
        XCTAssertLessThanOrEqual(settledProportion, 0.45 + 1e-6, "不应冲过理想区间上限")
        XCTAssertLessThanOrEqual(settledZoom, 5.0, "不应超过设备上限")

        // 收敛后必须停下：再评估若干次不应产生新的指令
        let callsWhenSettled = fake.rampCalls.count
        for _ in 0..<5 {
            controller.adjust(codeWidthProportion: baseProportionAtOneX * fake.currentZoomFactor, now: time)
            time = time.addingTimeInterval(1)
        }
        XCTAssertEqual(fake.rampCalls.count, callsWhenSettled, "已进入理想区间后不应再调整")
    }

    // MARK: - 参考码的选择

    /// 一帧里多个码时，取最宽的那个作为变焦依据。
    func testWidestProportionSelectsTheLargestCode() {
        let proportion = QRAutoZoomPolicy.widestProportion(codeWidths: [30, 120, 75], previewWidth: 300)
        XCTAssertEqual(proportion ?? 0, 0.4, accuracy: 1e-9)
    }

    /// 输入不可用（空帧 / 预览宽为 0 / 全是非正宽度）时返回 nil，上层据此跳过本次评估。
    func testWidestProportionReturnsNilForUnusableInput() {
        XCTAssertNil(QRAutoZoomPolicy.widestProportion(codeWidths: [], previewWidth: 300))
        XCTAssertNil(QRAutoZoomPolicy.widestProportion(codeWidths: [100], previewWidth: 0))
        XCTAssertNil(QRAutoZoomPolicy.widestProportion(codeWidths: [0, -5], previewWidth: 300))
    }
}
