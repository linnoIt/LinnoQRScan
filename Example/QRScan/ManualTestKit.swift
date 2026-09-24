//
//  ManualTestKit.swift
//  QRScan_Example
//
//  人工测试用的计量工具。全部是纯逻辑，不依赖相机硬件，因此可以喂合成数据做单元测试
//  （一个算错的计量器会把人工测试的结论一起带偏，所以这里值得单独测）。
//
//  这个文件同时编译进 QRScan_Example 与 QRScan_Tests 两个 target。
//

import Foundation

// MARK: - 帧率 / 卡顿

/// 用 CADisplayLink 的时间戳统计帧率与「卡顿帧」数量。
///
/// 只接受时间戳、不自己驱动显示，所以单测可以直接喂合成数据。
final class FrameRateMeter {

    struct Snapshot {
        /// 最近一窗帧间隔换算出的帧率。
        let fps: Double
        /// 帧间隔超过阈值的次数（累计，直到 reset）。
        let hitchCount: Int
        /// 观察到的最长帧间隔（毫秒）。
        let worstFrameMilliseconds: Double
        /// 已采集的帧间隔样本数。
        let sampleCount: Int
    }

    /// 帧间隔超过该值即记一次卡顿。默认 50ms：60Hz 下掉 3 帧，属于肉眼可感的顿挫。
    var hitchThreshold: TimeInterval = 0.05

    /// 参与平均的最近帧数。
    var windowSize: Int = 60

    private var intervals: [TimeInterval] = []
    private var lastTimestamp: CFTimeInterval?
    private(set) var hitchCount = 0
    private(set) var worstInterval: TimeInterval = 0

    func tick(timestamp: CFTimeInterval) {
        defer { lastTimestamp = timestamp }
        guard let last = lastTimestamp else { return }
        let interval = timestamp - last
        // 时间戳必须单调递增；相等或倒退（重置 / 换屏）一律丢弃
        guard interval > 0 else { return }

        intervals.append(interval)
        if intervals.count > windowSize {
            intervals.removeFirst(intervals.count - windowSize)
        }
        if interval > hitchThreshold { hitchCount += 1 }
        if interval > worstInterval { worstInterval = interval }
    }

    func reset() {
        intervals.removeAll()
        lastTimestamp = nil
        hitchCount = 0
        worstInterval = 0
    }

    var snapshot: Snapshot {
        let average = intervals.isEmpty ? 0 : intervals.reduce(0, +) / Double(intervals.count)
        return Snapshot(fps: average > 0 ? 1 / average : 0,
                        hitchCount: hitchCount,
                        worstFrameMilliseconds: worstInterval * 1000,
                        sampleCount: intervals.count)
    }
}

// MARK: - 滑动窗口频率

/// 统计「最近一段窗口内事件发生了多少次」，用于观察识别回调频率。
final class RollingCounter {

    /// 统计窗口长度（秒）。
    let window: TimeInterval

    private var timestamps: [Date] = []
    private(set) var totalCount = 0

    init(window: TimeInterval = 1) {
        self.window = window
    }

    func mark(at now: Date = Date()) {
        totalCount += 1
        timestamps.append(now)
        trim(now)
    }

    /// 最近 `window` 秒内的事件数 / 窗口长度。
    func rate(at now: Date = Date()) -> Double {
        trim(now)
        return Double(timestamps.count) / window
    }

    func reset() {
        timestamps.removeAll()
        totalCount = 0
    }

    private func trim(_ now: Date) {
        let cutoff = now.addingTimeInterval(-window)
        // 时间戳按写入顺序天然递增，从头部批量丢弃即可
        var drop = 0
        while drop < timestamps.count, timestamps[drop] < cutoff { drop += 1 }
        if drop > 0 { timestamps.removeFirst(drop) }
    }
}

// MARK: - 倍率变化轨迹

/// 记录倍率采样中的「变化点」，用来从 UI 侧验证步进值与最小调整间隔。
///
/// 面板以 10Hz 轮询 `currentZoomLevel()`，把结果喂进来；只有与上一个值不同的采样才会被记为变化点，
/// 因此 `changes` 里相邻两项的时间差就是「倍率真正变动」的间隔。
final class ZoomTrace {

    struct Change: Equatable {
        let factor: CGFloat
        let previousFactor: CGFloat
        let at: Date

        /// 本次相对上一次的变化量（拉近为正、推远为负）。
        var step: CGFloat { factor - previousFactor }
    }

    /// 小于该变化量视为读数的抖动，不计为一次变化。
    var epsilon: CGFloat = 0.001

    /// 最多保留的变化点数。
    var maxChanges: Int = 500

    /// 最近一次被记录的倍率（首次采样时写入）。
    private(set) var currentFactor: CGFloat?

    /// 变化点，按时间顺序。
    private(set) var changes: [Change] = []

    /// 累计采样次数。
    private(set) var sampleCount = 0

    /// - Returns: 本次采样是否构成一次变化。
    @discardableResult
    func record(factor: CGFloat, at now: Date = Date()) -> Bool {
        sampleCount += 1

        guard let last = currentFactor else {
            currentFactor = factor
            return false
        }
        guard abs(factor - last) > epsilon else { return false }

        changes.append(Change(factor: factor, previousFactor: last, at: now))
        if changes.count > maxChanges {
            changes.removeFirst(changes.count - maxChanges)
        }
        currentFactor = factor
        return true
    }

    /// 相邻变化点之间的最小时间间隔。
    ///
    /// 首个变化点只作为起点参与计算：它的**前一段**（从开始观察到首次下发）不受节流限制
    /// —— 控制器把上次调整时间初始化为 `distantPast`，首次一定放行 —— 而这一段并不在 `changes` 里，
    /// 所以从 `changes[0]` 到 `changes[1]` 的间隔才是真正反映节流窗口的那一段。
    var minimumChangeInterval: TimeInterval? {
        guard changes.count >= 2 else { return nil }
        var minimum = TimeInterval.greatestFiniteMagnitude
        for index in 1..<changes.count {
            let interval = changes[index].at.timeIntervalSince(changes[index - 1].at)
            if interval < minimum { minimum = interval }
        }
        return minimum == .greatestFiniteMagnitude ? nil : minimum
    }

    /// 最近若干次的变化量，用来核对步进值（预期 ±0.3）。
    func recentSteps(limit: Int = 8) -> [CGFloat] {
        changes.suffix(limit).map { $0.step }
    }

    func reset() {
        currentFactor = nil
        changes.removeAll()
        sampleCount = 0
    }
}

// MARK: - 内存

/// 进程常驻内存读数。用于确认释放 QRProxy 后相机相关内存是否回落。
enum MemoryProbe {

    /// 当前进程常驻内存（MB）。取不到时返回 nil。
    static func residentMemoryMB() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.resident_size) / 1024 / 1024
    }

    /// 便于展示的格式化文本。
    static func residentMemoryText() -> String {
        guard let value = residentMemoryMB() else { return "--" }
        return String(format: "%.1f MB", value)
    }
}
