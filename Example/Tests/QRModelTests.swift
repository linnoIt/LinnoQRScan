//
//  QRModelTests.swift
//  QRScan_Tests
//
//  QRModel 里纯映射逻辑的回归测试。
//
//  这些函数（码类型 -> QRState、状态 + 自定义类型 -> 实际参与识别的类型集合）
//  是「用户传什么参数 → 实际扫什么」的唯一依据，改错了不会有编译错误，
//  所以值得用测试钉住。
//

import XCTest
import AVFoundation
@testable import LinnoQRScan

final class QRModelTests: XCTestCase {

    // MARK: - 码类型 -> QRState

    /// 二维码归 Codes2D，一维条码归 Barcodes。
    func testCoderStateClassifiesMappings() {
        XCTAssertEqual(QRModel.coderState(for: .qr), .Codes2D)
        XCTAssertEqual(QRModel.coderState(for: .pdf417), .Codes2D)
        XCTAssertEqual(QRModel.coderState(for: .dataMatrix), .Codes2D)
        XCTAssertEqual(QRModel.coderState(for: .aztec), .Codes2D)

        XCTAssertEqual(QRModel.coderState(for: .ean13), .Barcodes)
        XCTAssertEqual(QRModel.coderState(for: .ean8), .Barcodes)
        XCTAssertEqual(QRModel.coderState(for: .code128), .Barcodes)
        XCTAssertEqual(QRModel.coderState(for: .code39), .Barcodes)
    }

    /// iOS 13 起新增的 micro 系列应被识别为二维码。
    func testCoderStateClassifiesMicroCodesAsCodes2D() throws {
        guard #available(iOS 15.4, *) else {
            throw XCTSkip("microQR / microPDF417 需要 iOS 15.4+")
        }
        XCTAssertEqual(QRModel.coderState(for: .microQR), .Codes2D)
        XCTAssertEqual(QRModel.coderState(for: .microPDF417), .Codes2D)
    }

    /// 人体 / 动物识别归 Bodies。
    func testCoderStateClassifiesBodyObjects() throws {
        guard #available(iOS 13.0, *) else {
            throw XCTSkip("Bodies 类型需要 iOS 13+")
        }
        XCTAssertEqual(QRModel.coderState(for: .humanBody), .Bodies)
        XCTAssertEqual(QRModel.coderState(for: .catBody), .Bodies)
        XCTAssertEqual(QRModel.coderState(for: .dogBody), .Bodies)
    }

    // MARK: - 扫描类型集合

    /// `scanState` 决定默认参与识别的类型集合。
    func testSupportedCodeTypesFollowScanState() {
        XCTAssertEqual(QRModel.supportedCodeTypes(for: .Barcodes).contains(.qr), false)
        XCTAssertEqual(QRModel.supportedCodeTypes(for: .Barcodes).contains(.ean13), true)

        XCTAssertEqual(QRModel.supportedCodeTypes(for: .Codes2D).contains(.qr), true)
        XCTAssertEqual(QRModel.supportedCodeTypes(for: .Codes2D).contains(.ean13), false)
    }

    /// Bodies 相关类型只在 iOS 13+ 可用，单独一条用例并带版本守卫。
    func testSupportedCodeTypesForBodies() throws {
        guard #available(iOS 13.0, *) else {
            throw XCTSkip("Bodies 类型需要 iOS 13+")
        }
        XCTAssertEqual(QRModel.supportedCodeTypes(for: .Bodies), [.humanBody, .dogBody, .catBody])

        let all = QRModel.supportedCodeTypes(for: .All)
        XCTAssertEqual(all.contains(.qr), true)
        XCTAssertEqual(all.contains(.humanBody), true)
    }

    /// 显式传入 `optional` 时，应覆盖该分组的默认类型集合。
    ///
    /// 注意：这里只覆盖 Barcodes / Codes2D / 三组合中的前几种。
    /// `.Codes2D_Bodies` 的二维码分组目前**没有**读取 `optional`（见调用方反馈），
    /// 属于既有缺陷，另行处理，不在此处把错误行为钉成期望。
    func testExplicitCodeTypesOverrideDefaults() {
        let custom: [AVMetadataObject.ObjectType] = [.qr]

        let barcodes = QRModel.supportedCodeTypes(for: .Barcodes, optional: custom)
        XCTAssertEqual(barcodes, custom)

        let codes2D = QRModel.supportedCodeTypes(for: .Codes2D, optional: custom)
        XCTAssertEqual(codes2D, custom)

        let mixed = QRModel.supportedCodeTypes(for: .Barcodes_Codes2D, optional: custom)
        XCTAssertEqual(mixed, custom)
    }

    // MARK: - 结果提取

    /// 空输入走兜底值，不应崩、也不应返回随机内容。
    func testSingleOutputFallsBackOnEmptyInput() {
        let (value, state) = QRModel.singleOutput(from: [])
        XCTAssertEqual(value, "12345678->测试数据")
        XCTAssertEqual(state, .Barcodes)
    }
}
