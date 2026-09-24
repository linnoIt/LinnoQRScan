//
//  ManualTestChecklist.swift
//  QRScan_Example
//
//  人工测试点清单（数据 + 模型）。
//
//  清单以数据形式存在，而不是硬编码在面板里，好处有两个：
//  1. 面板只负责渲染与打勾，UI 代码不掺业务文案；
//  2. 单测可以校验清单本身的完整性（编号唯一、每个改动面都有覆盖、字段不空），
//     避免以后改代码时悄悄漏掉验证点。
//
//  约定：`id` 前缀 = 所属 `area` 的 code，例如 AZ-03 属于 .autoZoom。
//  这个文件同时编译进 QRScan_Example 与 QRScan_Tests 两个 target。
//

import Foundation

/// 人工测试点的归属面。`code` 同时用作编号前缀。
enum ManualTestArea: String, CaseIterable {
    case autoZoom
    case multiFrame
    case permission
    case scanState
    case lifecycle
    case performance

    var code: String {
        switch self {
        case .autoZoom: return "AZ"
        case .multiFrame: return "MF"
        case .permission: return "PM"
        case .scanState: return "SS"
        case .lifecycle: return "LC"
        case .performance: return "PF"
        }
    }

    var title: String {
        switch self {
        case .autoZoom: return "自动变焦"
        case .multiFrame: return "多帧模式"
        case .permission: return "权限流程"
        case .scanState: return "识别类型过滤"
        case .lifecycle: return "线程与释放"
        case .performance: return "性能观测"
        }
    }

    /// 该面要验证的是哪一次改动。
    var changeSummary: String {
        switch self {
        case .autoZoom: return "本轮新增：isAutoFocusZoomEnabled / QRAutoZoomController"
        case .multiFrame: return "上一轮修复：fpsNum > 1 时识别永久停摆"
        case .permission: return "上一轮修复：未决定权限时不再静默黑屏"
        case .scanState: return "上一轮修复：displayResults 不再硬编码 .All"
        case .lifecycle: return "本轮修复：释放后摘除预览层并停相机"
        case .performance: return "本轮排查：装配移出主线程 / 检测类型数量的代价"
        }
    }
}

/// 一条人工测试点。
struct ManualTestItem: Equatable {
    let id: String
    let area: ManualTestArea
    /// 一句话说清测什么。
    let title: String
    /// 操作步骤。
    let howTo: String
    /// 判定标准（尽量带上可读数的阈值）。
    let expected: String
}

enum ManualTestChecklist {

    static let all: [ManualTestItem] = autoZoom + multiFrame + permission + scanState + lifecycle + performance

    static func items(in area: ManualTestArea) -> [ManualTestItem] {
        all.filter { $0.area == area }
    }

    // MARK: - 自动变焦

    private static let autoZoom: [ManualTestItem] = [
        ManualTestItem(
            id: "AZ-01",
            area: .autoZoom,
            title: "默认关闭，不干扰既有行为",
            howTo: "冷启动进入扫描页，先不要动任何开关；把测试码从远处慢慢靠近。",
            expected: "顶部「倍率」读数恒为 1.00，倍率变化次数为 0。默认关闭是本次改动的兼容性底线。"),
        ManualTestItem(
            id: "AZ-02",
            area: .autoZoom,
            title: "码偏小时按 +0.3 逐级拉近",
            howTo: "打开「自动变焦」，让测试码位于画面中央、宽度约占屏幕的 1/6，保持不动。",
            expected: "倍率按 1.00 → 1.30 → 1.60 … 逐级上升，每级 +0.30；直到码宽占比落进 25%~45% 后停住。"),
        ManualTestItem(
            id: "AZ-03",
            area: .autoZoom,
            title: "码过大时按 -0.3 逐级推远",
            howTo: "保持自动变焦开启，把手机慢慢贴近测试码，直到码几乎占满画面。",
            expected: "倍率按级递减（如 1.60 → 1.30 → 1.00），下限钳在 1.00，不会低于 1.00，画面不会出现 0.x 倍。"),
        ManualTestItem(
            id: "AZ-04",
            area: .autoZoom,
            title: "落在理想区间后停止调整",
            howTo: "把测试码稳定在画面宽度约 1/3 的位置，持续 10 秒。",
            expected: "倍率读数不再变化；「变化次数」在该时间段内不增加。判定依据是倍率变化，不是画面闪烁。"),
        ManualTestItem(
            id: "AZ-05",
            area: .autoZoom,
            title: "拉近受设备上限钳制",
            howTo: "自动变焦开启，用一个很小的码（或持续后退拉远距离），让码一直保持在画面 1/8 宽以下。",
            expected: "倍率升到当前设备的 videoMaxZoomFactor 后停止（常见机型 4.0~5.0，机型间会不同），不会无限增大，也不会卡住不响应。"),
        ManualTestItem(
            id: "AZ-06",
            area: .autoZoom,
            title: "两次调整至少间隔 0.5 秒",
            howTo: "自动变焦开启，反复把码拉近再推远，持续 20 秒，观察面板「最小调整间隔」读数。",
            expected: "最小调整间隔 ≥ 0.50s。若出现明显小于 0.5s 的值，说明节流窗口被绕过（首次调整不受限，已从计算中排除）。"),
        ManualTestItem(
            id: "AZ-07",
            area: .autoZoom,
            title: "一帧多码时以最宽的码为依据",
            howTo: "用另一台设备或电脑同时显示一个大码和一个小码，让两者同时进入取景框；然后让手机缓慢后退。",
            expected: "镜头向大码收敛（大码占比趋向 25%~45%），不会被远处的小码把倍率越推越小。"),
        ManualTestItem(
            id: "AZ-08",
            area: .autoZoom,
            title: "与手动 setZoom 的互斥关系",
            howTo: "自动变焦开启状态下，点「倍率 +2」（把倍率直接设到 3.00）。",
            expected: "下一轮评估会把倍率拉回理想区间，读数不会停在 3.00。这是设计约定：开启自动变焦后不要再手动设倍率。"),
        ManualTestItem(
            id: "AZ-09",
            area: .autoZoom,
            title: "关闭后手动倍率立刻生效且不被覆盖",
            howTo: "关掉自动变焦，再点「倍率 +2」，然后让码靠近 / 远离。",
            expected: "倍率稳定停在 3.00，不随码的大小变化被改写。"),
        ManualTestItem(
            id: "AZ-10",
            area: .autoZoom,
            title: "currentZoomLevel() 返回实时值而非缓存",
            howTo: "关闭自动变焦，点「倍率 +2」后立刻看面板倍率读数（面板 10Hz 轮询该接口）。",
            expected: "读数在 0.1 秒内变为 3.00。旧实现返回缓存的 currentZoomFactor，在 ramp 中途或外部改倍率后会读到过期值。")
    ]

    // MARK: - 多帧模式

    private static let multiFrame: [ManualTestItem] = [
        ManualTestItem(
            id: "MF-01",
            area: .multiFrame,
            title: "fpsNum = 3 能真正产出结果",
            howTo: "点「重建 (fps=3)」，把测试码放进取景框并保持不动 3 秒。",
            expected: "1~3 秒内出现绿框，点按绿框后日志出现回调记录。修复前该模式从第一次回调起就彻底停摆，永不产出。"),
        ManualTestItem(
            id: "MF-02",
            area: .multiFrame,
            title: "多帧模式展示的是码数量最多的那一帧",
            howTo: "fps=3 状态下，让画面里同时出现两个码。",
            expected: "绿框数量与画面内码数量一致（不是只画一个），说明取的是最优帧而不是空帧。"),
        ManualTestItem(
            id: "MF-03",
            area: .multiFrame,
            title: "单帧模式的 1 秒节流仍然有效",
            howTo: "点「重建 (fps=1)」，连续对着码扫描 15 秒，观察日志时间戳。",
            expected: "两次回调之间的间隔 ≥ 1s，不会出现每秒连续刷屏；这是产出结果后的冷却窗口，本次改动未触碰。")
    ]

    // MARK: - 权限流程

    private static let permission: [ManualTestItem] = [
        ManualTestItem(
            id: "PM-01",
            area: .permission,
            title: "首次启动弹出系统授权框",
            howTo: "删除 App 后重装（或在设置中重置相机权限），冷启动进入扫描页。",
            expected: "立即弹出系统相机授权弹窗。修复前 isAuther() 对 .notDetermined 直接返回 true，会静默拿到空画面。"),
        ManualTestItem(
            id: "PM-02",
            area: .permission,
            title: "拒绝授权后给出引导且能跳设置",
            howTo: "在 PM-01 的弹窗里选「不允许」，然后重启 App。",
            expected: "约 0.5 秒后弹出引导弹窗；点 Done 跳转到系统设置页，点 Cancel 仅关闭弹窗，App 不崩溃。"),
        ManualTestItem(
            id: "PM-03",
            area: .permission,
            title: "已授权时直接进相机、无多余弹窗",
            howTo: "在设置里允许相机权限后，冷启动 App。",
            expected: "直接出画面，不出现任何弹窗；这条同时验证已授权分支仍是同步放行。")
    ]

    // MARK: - 识别类型过滤

    private static let scanState: [ManualTestItem] = [
        ManualTestItem(
            id: "SS-01",
            area: .scanState,
            title: "仅二维码时不识别一维条码",
            howTo: "点「重建 (仅二维码)」，用另一台设备显示 Code128 条码（点「测试码」页可生成）。",
            expected: "无绿框、无回调。修复前 displayResults 硬编码 .All 过滤，会画出不属于当前 scanState 的框。"),
        ManualTestItem(
            id: "SS-02",
            area: .scanState,
            title: "仅二维码时二维码正常识别",
            howTo: "保持「仅二维码」，扫二维码。",
            expected: "正常出绿框并回调，qrState 为 Codes2D。"),
        ManualTestItem(
            id: "SS-03",
            area: .scanState,
            title: "仅条码时二维码不产出",
            howTo: "点「重建 (仅条码)」，扫二维码。",
            expected: "无绿框、无回调；再扫 Code128 条码应正常出框。"),
        ManualTestItem(
            id: "SS-04",
            area: .scanState,
            title: "全部类型下两类都能识别",
            howTo: "点「重建 (全部)」，分别扫二维码与条码。",
            expected: "两者都能识别，且 displayResults 画出的框不超出当前帧实际检出的类型。")
    ]

    // MARK: - 线程与释放

    private static let lifecycle: [ManualTestItem] = [
        ManualTestItem(
            id: "LC-01",
            area: .lifecycle,
            title: "start / stop 高频交替不崩不卡",
            howTo: "快速连点「停止」「启动」各 20 次（每轮间隔 0.2 秒以内），最后以「启动」收尾。",
            expected: "不崩溃、不卡死；结束后画面正常恢复。session 操作已串行化到内部队列，不应出现 isRunning 竞态。"),
        ManualTestItem(
            id: "LC-02",
            area: .lifecycle,
            title: "释放后预览画面立即消失（本轮修复点）",
            howTo: "点「释放 proxy」，观察屏幕与 Xcode 控制台。",
            expected: "预览画面与绿框在 1 帧内消失；控制台打印 `QRProxy -> deinit`。修复前预览层会留在视图上，画面定格不消失。"),
        ManualTestItem(
            id: "LC-03",
            area: .lifecycle,
            title: "释放后相机真正停止（本轮修复点）",
            howTo: "释放 proxy 后，看状态栏的相机使用指示灯（iPhone 14 及以后机型），并观察「内存」读数 3 秒。",
            expected: "指示灯熄灭；内存读数回落或至少不再增长。实测 AVCaptureVideoPreviewLayer 会强持有 session，不摘层相机就停不下来。"),
        ManualTestItem(
            id: "LC-04",
            area: .lifecycle,
            title: "释放后可以重新创建",
            howTo: "点「释放 proxy」，再点「重建 (全部)」。",
            expected: "重新正常出图，没有旧预览层的叠影或黑屏残影。"),
        ManualTestItem(
            id: "LC-05",
            area: .lifecycle,
            title: "回调闭包不持有宿主（否则释放不掉）",
            howTo: "点「释放 proxy」，确认控制台是否打印 `QRProxy -> deinit`。",
            expected: "必定打印。若未打印，说明 outPut 闭包强捕获了宿主控制器 —— 这是使用方最常见的循环引用，不是库的问题。")
    ]

    // MARK: - 性能观测

    private static let performance: [ManualTestItem] = [
        ManualTestItem(
            id: "PF-01",
            area: .performance,
            title: "持续扫描的帧率",
            howTo: "「全部」类型 + 自动变焦关闭，对着测试码持续扫描 30 秒，记录帧率读数。",
            expected: "帧率 ≥ 55fps（60Hz 屏）。明显低于此值说明主线程被元数据回调或 UI 工作拖住。"),
        ManualTestItem(
            id: "PF-02",
            area: .performance,
            title: "卡顿帧计数",
            howTo: "延续 PF-01 的 30 秒，读「卡顿(>50ms)」累计值。",
            expected: "≤ 5 次，且不随时间持续增长。持续增长说明存在每帧泄漏或逐帧累积的工作。"),
        ManualTestItem(
            id: "PF-03",
            area: .performance,
            title: "进入扫描页不卡顿（本轮修复点）",
            howTo: "从其他页面点进扫描页，反复 5 次，观察画面出现前的 UI 停顿。",
            expected: "无可感停顿。修复前相机装配（AVCaptureDeviceInput 初始化 + addInput/addOutput + lock 配置）在主线程同步执行，可能停顿数十毫秒。"),
        ManualTestItem(
            id: "PF-04",
            area: .performance,
            title: "识别类型数量的代价",
            howTo: "「全部」扫 30 秒记帧率，再「仅二维码」扫 30 秒记帧率，对比两次读数。",
            expected: "「仅二维码」帧率不低于「全部」。「全部」会开启 22 种检测类型（13 条码 + 6 二维码 + 3 人体），若差距明显，接入方应显式收窄 scanState 或 supportCodeTypes。"),
        ManualTestItem(
            id: "PF-05",
            area: .performance,
            title: "自动变焦本身的代价",
            howTo: "同一场景下，自动变焦关 / 开各扫 30 秒，对比帧率与卡顿计数。",
            expected: "两者差异不可察觉。该路径只做几何换算与（每 0.5 秒一次的）设备倍率下发，没有逐帧的硬件操作。"),
        ManualTestItem(
            id: "PF-06",
            area: .performance,
            title: "多帧模式的内存不累积",
            howTo: "fps=3 状态下持续扫描 60 秒，每 10 秒记录一次内存读数。",
            expected: "内存读数平稳（波动在数 MB 内），不出现持续单向增长。frameBuffer 的容量上限由 fpsNum 决定。")
    ]
}
