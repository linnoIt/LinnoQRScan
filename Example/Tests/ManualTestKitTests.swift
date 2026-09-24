//
//  ManualTestKitTests.swift
//  QRScan_Tests
//
//  人工测试工具集本身的单测。
//
//  为什么要测「测试工具」：帧率计、回调计数器、倍率轨迹是人工测试的判据来源，
//  它们算错会让整轮人工测试得出反向结论。所以这里对每个计量器都钉住语义边界。
//
//  这些文件同时编译进 QRScan_Tests，因此无需 import 应用模块。
//

import XCTest

final class ManualTestKitTests: XCTestCase {

    // MARK: - FrameRateMeter

    /// 稳定 60Hz：帧率约 60，无卡顿。
    func testSteadyDisplayLinkYieldsSixtyFPSWithoutHitches() {
        let meter = FrameRateMeter()
        var timestamp: CFTimeInterval = 1000
        // 第一个时间戳只作为基准，不产生帧间隔
        meter.tick(timestamp: timestamp)

        for _ in 0..<60 {
            timestamp += 1.0 / 60.0
            meter.tick(timestamp: timestamp)
        }

        let snapshot = meter.snapshot
        XCTAssertEqual(snapshot.fps, 60, accuracy: 0.5)
        XCTAssertEqual(snapshot.hitchCount, 0)
        XCTAssertEqual(snapshot.sampleCount, 60)
    }

    /// 首个时间戳不产生样本：没有基准就谈不上帧间隔。
    func testFirstTickProducesNoSample() {
        let meter = FrameRateMeter()
        meter.tick(timestamp: 10)
        XCTAssertEqual(meter.snapshot.sampleCount, 0)
        XCTAssertEqual(meter.snapshot.fps, 0)
    }

    /// 超过阈值的帧间隔记为一次卡顿，并记录最长帧。
    func testLongIntervalCountsAsHitch() {
        let meter = FrameRateMeter()
        meter.tick(timestamp: 0)
        meter.tick(timestamp: 0.016)   // 正常帧
        meter.tick(timestamp: 0.200)   // 184ms 的停顿

        let snapshot = meter.snapshot
        XCTAssertEqual(snapshot.hitchCount, 1)
        XCTAssertEqual(snapshot.worstFrameMilliseconds, 184, accuracy: 0.5)
    }

    /// 阈值是「大于」而非「大于等于」：正好等于阈值不算卡顿。
    func testIntervalExactlyAtThresholdIsNotAHitch() {
        let meter = FrameRateMeter()
        meter.tick(timestamp: 0)
        meter.tick(timestamp: 0.05)
        XCTAssertEqual(meter.snapshot.hitchCount, 0)
    }

    /// 帧率只看最近 windowSize 个间隔：早期的慢帧不应永久拖低读数。
    func testFPSUsesOnlyTheMostRecentWindow() {
        let meter = FrameRateMeter()
        meter.windowSize = 10
        var timestamp: CFTimeInterval = 0
        meter.tick(timestamp: timestamp)

        // 先来 20 个慢帧（60ms，明确超过 50ms 阈值）
        for _ in 0..<20 {
            timestamp += 0.06
            meter.tick(timestamp: timestamp)
        }
        // 再来 10 个 60fps 的帧，把窗口填满
        for _ in 0..<10 {
            timestamp += 1.0 / 60.0
            meter.tick(timestamp: timestamp)
        }

        XCTAssertEqual(meter.snapshot.fps, 60, accuracy: 1.0)
        // 但卡顿计数是累计量，不清零
        XCTAssertGreaterThanOrEqual(meter.snapshot.hitchCount, 20)
    }

    /// 时间戳倒退（重置 / 切屏）应被丢弃，并以新时间戳重建基准 —— 不能产生一个假的巨大间隔。
    func testNonMonotonicTimestampsRebuildBaseline() {
        let meter = FrameRateMeter()
        meter.tick(timestamp: 10)
        meter.tick(timestamp: 5)                 // 倒退：丢弃，并把基准移到 5
        XCTAssertEqual(meter.snapshot.sampleCount, 0)

        meter.tick(timestamp: 5)                 // 相同时间戳：丢弃
        XCTAssertEqual(meter.snapshot.sampleCount, 0)

        meter.tick(timestamp: 5.02)              // 正常前进
        XCTAssertEqual(meter.snapshot.sampleCount, 1)
        XCTAssertEqual(meter.snapshot.fps, 50, accuracy: 0.5)
    }

    /// reset 之后一切归零。
    func testResetClearsEverything() {
        let meter = FrameRateMeter()
        meter.tick(timestamp: 0)
        meter.tick(timestamp: 0.1)
        meter.reset()

        let snapshot = meter.snapshot
        XCTAssertEqual(snapshot.sampleCount, 0)
        XCTAssertEqual(snapshot.hitchCount, 0)
        XCTAssertEqual(snapshot.worstFrameMilliseconds, 0)
        XCTAssertEqual(snapshot.fps, 0)
    }

    // MARK: - RollingCounter

    /// 落在窗口内的事件计入频率，窗口外的被丢弃。
    func testRollingCounterOnlyCountsEventsInsideWindow() {
        let counter = RollingCounter(window: 1)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        counter.mark(at: base)
        counter.mark(at: base.addingTimeInterval(0.2))
        counter.mark(at: base.addingTimeInterval(0.4))

        XCTAssertEqual(counter.rate(at: base.addingTimeInterval(0.5)), 3, accuracy: 1e-9)
        // 1.6 秒后，前两个事件已滑出窗口
        XCTAssertEqual(counter.rate(at: base.addingTimeInterval(1.6)), 0, accuracy: 1e-9)
    }

    /// 累计次数不受窗口影响，reset 才清零。
    func testRollingCounterTotalIsCumulative() {
        let counter = RollingCounter(window: 1)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<5 {
            counter.mark(at: base.addingTimeInterval(Double(index) * 2))
        }
        XCTAssertEqual(counter.totalCount, 5)
        XCTAssertEqual(counter.rate(at: base.addingTimeInterval(100)), 0, accuracy: 1e-9)

        counter.reset()
        XCTAssertEqual(counter.totalCount, 0)
    }

    /// 正好在窗口边界上的事件仍然计入（cutoff 用严格小于比较）。
    func testRollingCounterKeepsEventsExactlyOnBoundary() {
        let counter = RollingCounter(window: 1)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        counter.mark(at: base)
        XCTAssertEqual(counter.rate(at: base.addingTimeInterval(1)), 1, accuracy: 1e-9)
    }

    // MARK: - ZoomTrace

    /// 首次采样只建立基准，不算一次变化。
    func testFirstSampleIsBaselineNotAChange() {
        let trace = ZoomTrace()
        let changed = trace.record(factor: 1.0, at: Date())
        XCTAssertFalse(changed)
        XCTAssertTrue(trace.changes.isEmpty)
        XCTAssertEqual(trace.sampleCount, 1)
        XCTAssertEqual(trace.currentFactor, 1.0)
    }

    /// 小于 epsilon 的抖动不算变化 —— 否则设备端的浮点噪声会污染间隔统计。
    func testNoiseBelowEpsilonIsNotAChange() {
        let trace = ZoomTrace()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        trace.record(factor: 1.0, at: base)
        XCTAssertFalse(trace.record(factor: 1.0005, at: base.addingTimeInterval(0.1)))
        XCTAssertTrue(trace.changes.isEmpty)
    }

    /// 变化点记录步进方向与大小：拉近为正、推远为负。
    func testChangeRecordsStepMagnitudeAndDirection() {
        let trace = ZoomTrace()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        trace.record(factor: 1.0, at: base)
        trace.record(factor: 1.3, at: base.addingTimeInterval(1))
        trace.record(factor: 1.0, at: base.addingTimeInterval(2))

        XCTAssertEqual(trace.changes.count, 2)
        XCTAssertEqual(trace.changes[0].step, 0.3, accuracy: 1e-9)
        XCTAssertEqual(trace.changes[1].step, -0.3, accuracy: 1e-9)

        // 步进序列不做浮点精确比较：1.3 - 1.0 在 Double 下是 0.30000000000000004
        let steps = trace.recentSteps()
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0], 0.3, accuracy: 1e-9)
        XCTAssertEqual(steps[1], -0.3, accuracy: 1e-9)
    }

    /// 相邻变化点的最小间隔：从 changes[0] 到 changes[1] 起算，
    /// 因为 changes[0] 之前那一段（开始观察到首次下发）不受节流限制。
    func testMinimumIntervalSkipsTheUnthrottledFirstSegment() {
        let trace = ZoomTrace()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        trace.record(factor: 1.0, at: base)                                     // 基准
        trace.record(factor: 1.3, at: base.addingTimeInterval(0.05))            // 首次变化（不受节流，间隔很短）
        trace.record(factor: 1.6, at: base.addingTimeInterval(0.55))            // +0.5s
        trace.record(factor: 1.9, at: base.addingTimeInterval(1.20))            // +0.65s

        let interval = trace.minimumChangeInterval
        XCTAssertNotNil(interval)
        XCTAssertEqual(interval ?? 0, 0.5, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(interval ?? 0, 0.5, "最小间隔不应小于节流窗口")
    }

    /// 变化点不足两个时无法计算间隔。
    func testMinimumIntervalIsNilWithFewerThanTwoChanges() {
        let trace = ZoomTrace()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        trace.record(factor: 1.0, at: base)
        XCTAssertNil(trace.minimumChangeInterval)

        trace.record(factor: 1.3, at: base.addingTimeInterval(1))
        XCTAssertNil(trace.minimumChangeInterval)
    }

    /// 保留上限生效，且只丢弃最旧的变化点。
    func testChangesAreCapped() {
        let trace = ZoomTrace()
        trace.maxChanges = 5
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        trace.record(factor: 1.0, at: base)

        for index in 1...10 {
            trace.record(factor: 1.0 + CGFloat(index) * 0.3, at: base.addingTimeInterval(Double(index)))
        }

        XCTAssertEqual(trace.changes.count, 5)
        XCTAssertEqual(trace.changes.last?.factor ?? 0, 4.0, accuracy: 1e-9)
    }

    /// reset 后重新建立基准。
    func testResetClearsBaseline() {
        let trace = ZoomTrace()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        trace.record(factor: 1.0, at: base)
        trace.record(factor: 1.3, at: base.addingTimeInterval(1))
        trace.reset()

        XCTAssertNil(trace.currentFactor)
        XCTAssertTrue(trace.changes.isEmpty)
        XCTAssertEqual(trace.sampleCount, 0)
        XCTAssertFalse(trace.record(factor: 5.0, at: base), "reset 后第一次采样应重新成为基准")
    }

    // MARK: - MemoryProbe

    /// 常驻内存是可读的且大于 0。
    func testResidentMemoryIsReadable() {
        let value = MemoryProbe.residentMemoryMB()
        XCTAssertNotNil(value)
        XCTAssertGreaterThan(value ?? 0, 0)
    }

    // MARK: - 清单完整性

    /// 编号唯一。
    func testChecklistIdentifiersAreUnique() {
        let ids = ManualTestChecklist.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "存在重复的测试点编号")
    }

    /// 编号前缀与所属面一致，避免归类写错。
    func testChecklistIdentifierPrefixMatchesArea() {
        for item in ManualTestChecklist.all {
            XCTAssertTrue(item.id.hasPrefix("\(item.area.code)-"),
                          "\(item.id) 的前缀与所属面 \(item.area.code) 不一致")
        }
    }

    /// 三段文案都不为空 —— 缺任何一段，测试点就不可执行。
    func testChecklistFieldsAreNotEmpty() {
        for item in ManualTestChecklist.all {
            XCTAssertFalse(item.title.isEmpty, "\(item.id) 缺少标题")
            XCTAssertFalse(item.howTo.isEmpty, "\(item.id) 缺少操作步骤")
            XCTAssertFalse(item.expected.isEmpty, "\(item.id) 缺少预期结果")
        }
    }

    /// 每个面都有测试点，且按面筛选不丢条目。
    func testEveryAreaHasItemsAndFilteringIsLossless() {
        var total = 0
        for area in ManualTestArea.allCases {
            let items = ManualTestChecklist.items(in: area)
            XCTAssertFalse(items.isEmpty, "\(area.title) 没有任何测试点")
            total += items.count
        }
        XCTAssertEqual(total, ManualTestChecklist.all.count, "按面筛选后数量与总表不一致")
        XCTAssertEqual(ManualTestArea.allCases.count, 6, "面数量变化时请同步清单")
    }

    /// 本轮改动的面至少各有 3 条覆盖，防止以后删测试点把验证面挖空。
    func testChangedAreasHaveEnoughCoverage() {
        let minimum = 3
        for area in [ManualTestArea.autoZoom, .lifecycle, .performance] {
            XCTAssertGreaterThanOrEqual(ManualTestChecklist.items(in: area).count, minimum,
                                        "\(area.title) 的测试点少于 \(minimum) 条")
        }
    }

    /// 关键行为必须在清单里有对应测试点：这些关键字分别锚定一次修复，删掉就会红。
    func testChecklistCoversEveryFixedBehaviour() {
        let corpus = ManualTestChecklist.all
            .map { "\($0.title)\n\($0.howTo)\n\($0.expected)" }
            .joined(separator: "\n")

        let anchors: [(keyword: String, behaviour: String)] = [
            ("0.50", "自动变焦最小调整间隔"),
            ("0.30", "自动变焦步进"),
            ("currentZoomLevel", "倍率实时读取而非缓存"),
            ("fpsNum", "多帧模式修复"),
            ("scanState", "识别类型过滤"),
            ("授权", "权限流程"),
            ("deinit", "释放时摘除预览层"),
            ("videoMaxZoomFactor", "拉近上限钳制"),
            ("最宽", "一帧多码取最宽的码")
        ]

        for anchor in anchors {
            XCTAssertTrue(corpus.contains(anchor.keyword),
                          "清单缺少对「\(anchor.behaviour)」的测试点（锚点：\(anchor.keyword)）")
        }
    }
}
