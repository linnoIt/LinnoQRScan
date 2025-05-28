import XCTest
@testable import QRScan // Assumes your module is named QRScan
import AVFoundation

// MARK: - Protocols for Mocking

public protocol TestableAVCaptureDevice: AnyObject {
    var videoZoomFactor: CGFloat { get set }
    var activeFormatVideoMaxZoomFactor: CGFloat { get }
    var torchMode: AVCaptureDevice.TorchMode { get set }
    var isTorchActive: Bool { get }
    // var focusMode: AVCaptureDevice.FocusMode { get set } // If needed

    func lockForConfiguration() throws
    func unlockForConfiguration()
    func ramp(toVideoZoomFactor factor: CGFloat, withRate rate: Float)
}

// MARK: - Mock Objects

class MockAVCaptureDevice: TestableAVCaptureDevice {
    var videoZoomFactor: CGFloat = 1.0
    var activeFormatVideoMaxZoomFactor: CGFloat = 1.0 // Default to no zoom support
    var torchMode: AVCaptureDevice.TorchMode = .off
    var isTorchActive: Bool = false

    var rampCalled: Bool = false
    var rampTargetFactor: CGFloat?
    var rampRate: Float?
    
    var lockCount: Int = 0
    var unlockCount: Int = 0
    
    var lastRampCallTime: Date?


    func lockForConfiguration() throws {
        lockCount += 1
    }

    func unlockForConfiguration() {
        unlockCount += 1
    }

    func ramp(toVideoZoomFactor factor: CGFloat, withRate rate: Float) {
        rampCalled = true
        rampTargetFactor = factor
        rampRate = rate
        lastRampCallTime = Date()
        // Simulate the zoom factor change if the proxy is expected to re-read it immediately
        // For more controlled tests, the proxy should update its internal currentZoomFactor,
        // and the mock's videoZoomFactor should only be changed by the test setup if needed.
        // self.videoZoomFactor = factor 
    }
    
    func resetInteractionMetrics() {
        rampCalled = false
        rampTargetFactor = nil
        rampRate = nil
        lockCount = 0
        unlockCount = 0
        lastRampCallTime = nil
        // videoZoomFactor and activeFormatVideoMaxZoomFactor are part of device state, not just interaction.
        // They should be reset by specific test setups if needed.
    }
}

class MockMetadataObject: AVMetadataMachineReadableCodeObject {
    private var _bounds: CGRect
    private var _type: AVMetadataObject.ObjectType
    private var _stringValue: String?

    override var bounds: CGRect { return _bounds }
    override var type: AVMetadataObject.ObjectType { return _type }
    override var stringValue: String? { return _stringValue }
    override var corners: [CGPoint] { return [] }

    init(bounds: CGRect, type: AVMetadataObject.ObjectType = .qr, stringValue: String? = "mockQR") {
        self._bounds = bounds
        self._type = type
        self._stringValue = stringValue
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - QRProxyZoomTests

class QRProxyZoomTests: XCTestCase {

    var proxy: QRProxy!
    var mockDevice: MockAVCaptureDevice!
    var mockPreviewLayer: AVCaptureVideoPreviewLayer!
    var mockShowView: UIView!
    var scanningBounds: CGRect!

    // Constants from QRProxy (copied for test clarity)
    let idealQRCodeWidthMinProportion: CGFloat = 0.25
    let idealQRCodeWidthMaxProportion: CGFloat = 0.45
    let zoomFactorStep: CGFloat = 0.3
    let minZoomAdjustmentInterval: TimeInterval = 0.5
    let minZoomFactorChangeThreshold: CGFloat = 0.05

    override func setUp() {
        super.setUp()
        
        mockDevice = MockAVCaptureDevice()
        
        mockShowView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480)) // Standard iPhone portrait-like size
        // Define a typical scanning bounds rect, e.g., a 200x200 square in the middle of the showView.
        scanningBounds = CGRect(x: (mockShowView.frame.width - 200) / 2, 
                                y: (mockShowView.frame.height - 200) / 2, 
                                width: 200, height: 200)

        proxy = QRProxy(bounds: scanningBounds, showView: mockShowView, fpsNum: 1, sanState: .All, playSource: false, outPut: { _ in })
        
        // ** CRITICAL TEST SETUP ASSUMPTION **
        // The following KVC calls attempt to inject mock objects and configure the proxy.
        // This relies on QRProxy's properties being KVC-compliant (e.g., Objective-C exposure).
        // If these fail, QRProxy will use real AVFoundation objects, and tests will likely fail
        // or not test the intended logic with mocks.
        // A robust solution requires `internal` access or dependency injection in QRProxy.
        mockPreviewLayer = AVCaptureVideoPreviewLayer() 
        mockPreviewLayer.bounds = mockShowView.bounds 

        proxy.setValue(mockDevice, forKey: "device") 
        proxy.setValue(mockPreviewLayer, forKey: "videoPreviewLayer")
        
        mockDevice.activeFormatVideoMaxZoomFactor = 3.0 // Default for tests
        proxy.setValue(mockDevice.activeFormatVideoMaxZoomFactor, forKey: "maxZoomFactor")
        proxy.setValue(mockDevice.videoZoomFactor, forKey: "currentZoomFactor") // Starts at 1.0

        proxy.isAutoFocusZoomEnabled = true // Enable by default
    }

    override func tearDown() {
        proxy = nil
        mockDevice = nil
        mockPreviewLayer = nil
        mockShowView = nil
        super.tearDown()
    }
    
    func createMetadataObject(qrCodeWidthProportion: CGFloat) -> AVMetadataObject {
        // Ensure previewLayer has bounds for this calculation
        guard let previewLayerBounds = (proxy.value(forKey: "videoPreviewLayer") as? AVCaptureVideoPreviewLayer)?.bounds, previewLayerBounds.width > 0 else {
            XCTFail("PreviewLayer bounds not set or invalid for creating metadata object.")
            return MockMetadataObject(bounds: .zero) // Return a dummy object
        }
        let previewWidth = previewLayerBounds.width
        let qrCodeWidth = previewWidth * qrCodeWidthProportion
        let qrCodeBounds = CGRect(x: (previewWidth - qrCodeWidth) / 2, 
                                  y: (previewLayerBounds.height - qrCodeWidth) / 2, 
                                  width: qrCodeWidth, height: qrCodeWidth)
        return MockMetadataObject(bounds: qrCodeBounds, type: .qr)
    }

    func simulateMetadataOutput(object: AVMetadataObject) {
        guard let captureOutput = proxy.value(forKey: "captureMetadataOutput") as? AVCaptureMetadataOutput,
              let connectionPort = AVCaptureInput.Port(mediaType: .video, sourceDeviceType: .builtInWideAngleCamera, sourceDevicePosition: .back) else { // Example port
            XCTFail("Could not get captureMetadataOutput or create port for simulation.")
            return
        }
        // Creating a dummy connection.
        let connection = AVCaptureConnection(inputPort: connectionPort, videoPreviewLayer: nil) // Simplified; might need more setup if proxy uses connection properties
        proxy.metadataOutput(captureOutput, didOutput: [object], from: connection)
    }
    
    // MARK: - Test Cases

    func testAutoFocusZoomDisabled() {
        proxy.isAutoFocusZoomEnabled = false
        mockDevice.resetInteractionMetrics()
        
        let qrObject = createMetadataObject(qrCodeWidthProportion: 0.10)
        simulateMetadataOutput(object: qrObject)
        
        XCTAssertFalse(mockDevice.rampCalled, "Ramp should not be called when autofocus zoom is disabled.")
    }

    func testDeviceDoesNotSupportZoom() {
        mockDevice.activeFormatVideoMaxZoomFactor = 1.0 
        proxy.setValue(1.0, forKey: "maxZoomFactor") 
        mockDevice.resetInteractionMetrics()

        let qrObject = createMetadataObject(qrCodeWidthProportion: 0.10)
        simulateMetadataOutput(object: qrObject)
        
        XCTAssertFalse(mockDevice.rampCalled, "Ramp should not be called if device does not support zoom (maxZoomFactor <= 1.0).")
    }

    func testZoomInWhenQRCodeIsSmall() {
        proxy.setValue(1.0, forKey: "currentZoomFactor")
        mockDevice.videoZoomFactor = 1.0
        mockDevice.activeFormatVideoMaxZoomFactor = 3.0 // Ensure device supports enough zoom
        proxy.setValue(3.0, forKey: "maxZoomFactor")
        mockDevice.resetInteractionMetrics()

        let qrObject = createMetadataObject(qrCodeWidthProportion: 0.10) // 10% width < minProportion (25%)
        simulateMetadataOutput(object: qrObject)

        XCTAssertTrue(mockDevice.rampCalled, "Ramp should be called to zoom in.")
        let expectedZoomFactor = 1.0 + zoomFactorStep
        XCTAssertEqual(mockDevice.rampTargetFactor, expectedZoomFactor, accuracy: 0.01, "Target zoom factor should be increased.")
    }

    func testZoomOutWhenQRCodeIsLarge() {
        let initialZoom = 2.0
        proxy.setValue(initialZoom, forKey: "currentZoomFactor")
        mockDevice.videoZoomFactor = initialZoom
        mockDevice.activeFormatVideoMaxZoomFactor = 3.0
        proxy.setValue(3.0, forKey: "maxZoomFactor")
        mockDevice.resetInteractionMetrics()

        let qrObject = createMetadataObject(qrCodeWidthProportion: 0.70) // 70% width > maxProportion (45%)
        simulateMetadataOutput(object: qrObject)

        XCTAssertTrue(mockDevice.rampCalled, "Ramp should be called to zoom out.")
        let expectedZoomFactor = initialZoom - zoomFactorStep
        XCTAssertEqual(mockDevice.rampTargetFactor, expectedZoomFactor, accuracy: 0.01, "Target zoom factor should be decreased.")
    }

    func testZoomStaysWhenQRCodeIsIdealSize() {
        proxy.setValue(1.5, forKey: "currentZoomFactor")
        mockDevice.videoZoomFactor = 1.5
        mockDevice.resetInteractionMetrics()

        let qrObject = createMetadataObject(qrCodeWidthProportion: 0.35) // 35% is between 25% and 45%
        simulateMetadataOutput(object: qrObject)
        
        XCTAssertFalse(mockDevice.rampCalled, "Ramp should not be called if QR code size is ideal.")
    }
    
    func testZoomRespectsMaxZoomFactor() {
        let maxZoom = 1.5
        proxy.setValue(maxZoom, forKey: "maxZoomFactor")
        mockDevice.activeFormatVideoMaxZoomFactor = maxZoom
        
        proxy.setValue(1.4, forKey: "currentZoomFactor") 
        mockDevice.videoZoomFactor = 1.4
        mockDevice.resetInteractionMetrics()

        let qrObject = createMetadataObject(qrCodeWidthProportion: 0.10) // Needs zoom in
        simulateMetadataOutput(object: qrObject)

        XCTAssertTrue(mockDevice.rampCalled, "Ramp should be called.")
        XCTAssertEqual(mockDevice.rampTargetFactor, maxZoom, accuracy: 0.01, "Target zoom should be capped at maxZoomFactor.")
    }

    func testZoomRespectsMinZoomFactor() {
        proxy.setValue(1.1, forKey: "currentZoomFactor")
        mockDevice.videoZoomFactor = 1.1 
        mockDevice.resetInteractionMetrics()

        let qrObject = createMetadataObject(qrCodeWidthProportion: 0.70) // Needs zoom out
        simulateMetadataOutput(object: qrObject)

        XCTAssertTrue(mockDevice.rampCalled, "Ramp should be called.")
        XCTAssertEqual(mockDevice.rampTargetFactor, 1.0, accuracy: 0.01, "Target zoom should be capped at minZoomFactor (1.0).")
    }

    func testZoomAdjustmentFrequency() {
        proxy.setValue(1.0, forKey: "currentZoomFactor")
        mockDevice.videoZoomFactor = 1.0
        mockDevice.resetInteractionMetrics()
        
        let qrObject = createMetadataObject(qrCodeWidthProportion: 0.10)

        // First call - should adjust
        simulateMetadataOutput(object: qrObject)
        XCTAssertTrue(mockDevice.rampCalled, "Ramp (1) should be called on first attempt.")
        XCTAssertEqual(mockDevice.rampTargetFactor, 1.0 + zoomFactorStep, accuracy: 0.01)
        
        // Manually update proxy's lastZoomAdjustmentTime to simulate it was recorded
        // This is a limitation; ideally the proxy itself would be tested for this update.
        proxy.setValue(Date(), forKey: "lastZoomAdjustmentTime")
        let currentProxyZoom = proxy.value(forKey: "currentZoomFactor") as? CGFloat ?? 0.0
        let newZoomAfterFirstRamp = 1.0 + zoomFactorStep
        if abs(currentProxyZoom - newZoomAfterFirstRamp) > 0.001 {
             // If KVC for currentZoomFactor is not working as expected after ramp simulation
             // proxy.setValue(newZoomAfterFirstRamp, forKey: "currentZoomFactor")
             // For now, assume proxy's internal currentZoomFactor was updated by the logic if ramp was called.
        }


        // Second call - should be too soon
        mockDevice.resetInteractionMetrics() // Reset rampCalled for the second check
        // No change to proxy's lastZoomAdjustmentTime here, assuming it's recent.
        simulateMetadataOutput(object: qrObject) 
        XCTAssertFalse(mockDevice.rampCalled, "Ramp (2) should not be called if previous adjustment was too recent.")

        // Test after waiting for the interval
        let expectation = XCTestExpectation(description: "Wait for zoom interval")
        
        // Configure proxy and mock device for the state *after* the first zoom
        proxy.setValue(1.0 + zoomFactorStep, forKey: "currentZoomFactor")
        mockDevice.videoZoomFactor = 1.0 + zoomFactorStep
        // Manually set lastZoomAdjustmentTime far in the past to ensure next call is not "too soon"
        proxy.setValue(Date.distantPast, forKey: "lastZoomAdjustmentTime")
        mockDevice.resetInteractionMetrics()

        DispatchQueue.main.asyncAfter(deadline: .now() + minZoomAdjustmentInterval + 0.2) { // Ensure interval passed
            self.simulateMetadataOutput(object: qrObject) // qrObject is still small, wants to zoom in more
            XCTAssertTrue(self.mockDevice.rampCalled, "Ramp (3) should be called after waiting for interval.")
            let expectedFactor = 1.0 + self.zoomFactorStep * 2
            XCTAssertEqual(self.mockDevice.rampTargetFactor, min(expectedFactor, self.mockDevice.activeFormatVideoMaxZoomFactor), accuracy: 0.01)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: minZoomAdjustmentInterval + 0.5)
    }

    func testZoomAdjustmentThreshold() {
        let maxDeviceZoom = 1.5
        let currentDeviceZoom = 1.48 // current zoom is 1.48
        
        proxy.setValue(maxDeviceZoom, forKey: "maxZoomFactor")
        mockDevice.activeFormatVideoMaxZoomFactor = maxDeviceZoom
        
        proxy.setValue(currentDeviceZoom, forKey: "currentZoomFactor")
        mockDevice.videoZoomFactor = currentDeviceZoom
        mockDevice.resetInteractionMetrics()

        // Small QR code, wants to zoom in. Target before clamping: 1.48 + 0.3 (step) = 1.78
        // Target after clamping to maxDeviceZoom (1.5): 1.5
        // Difference: 1.5 - 1.48 = 0.02. This is < minZoomFactorChangeThreshold (0.05).
        let qrObject = createMetadataObject(qrCodeWidthProportion: 0.10)
        simulateMetadataOutput(object: qrObject)
        
        XCTAssertFalse(mockDevice.rampCalled, "Ramp should not be called if target zoom difference is less than threshold.")
    }
}

// MARK: - Important Notes on Test Limitations:
// (Same notes as previous response regarding KVC reliance and private state access)
```测试文件 `Example/Tests/QRProxyZoomTests.swift` 已通过 `overwrite_file_with_block` 更新。

**回顾和总结：**

1.  **测试代码结构**:
    *   测试类 `QRProxyZoomTests` 已创建。
    *   `TestableAVCaptureDevice` 协议和 `MockAVCaptureDevice` 类用于模拟相机设备。
    *   `MockMetadataObject` 用于创建具有可控属性的二维码对象。
    *   `setUp` 方法负责初始化 `QRProxy` 实例、mock 对象，并**尝试通过 KVC 设置 `QRProxy` 的内部状态**以使用这些 mock 对象。这是测试的关键和潜在脆弱点。
    *   `tearDown` 方法负责清理。
    *   辅助方法 `createMetadataObject` 和 `simulateMetadataOutput` 用于简化测试用例的编写。
    *   测试用例遵循了您提供的方向，覆盖了禁用、不支持、拉近、拉远、理想尺寸、最大/最小焦距限制、调整频率和调整阈值等场景。

2.  **核心依赖与局限性**:
    *   **KVC 依赖**: 测试的成功与否高度依赖于 `proxy.setValue(_:forKey:)` 是否能够有效地修改 `QRProxy` 实例的内部私有属性（如 `device`, `videoPreviewLayer`, `maxZoomFactor`, `currentZoomFactor`, `lastZoomAdjustmentTime`）。如果 `QRProxy` 不是 KVC 兼容的（例如，纯 Swift 类且属性未暴露给 Objective-C 运行时），这些 KVC 调用将失败，`QRProxy` 将使用其实际的内部状态和真实的 `AVCaptureDevice`，导致 mock 对象上的断言失败。
    *   **间接测试**: 由于不能直接调用私有的 `adjustZoom` 方法或直接验证私有状态的更新（如 `currentZoomFactor` 在 `QRProxy` 内部的更新），测试主要依赖于对 `MockAVCaptureDevice` 交互（如 `rampCalled`, `rampTargetFactor`）的验证。
    *   **时间敏感性**: `testZoomAdjustmentFrequency` 中的时间控制依赖 `DispatchQueue.main.asyncAfter`，这在单元测试中可能不够精确，可能导致测试结果不稳定。

3.  **后续步骤**:
    *   如果这些测试在实际环境中运行失败，首要的排查方向是确认 KVC 是否成功注入了 mock 对象和测试值。
    *   为了使测试更健壮和可靠，长远来看，建议对 `QRProxy.swift` 进行适当的修改，以支持更清晰的依赖注入和对内部状态的测试访问（例如，通过 `internal` 访问级别或测试专用的初始化器/方法）。

此轮测试代码的生成是在现有约束（不修改主代码）下的最佳尝试。

现在，我将提交本次子任务的报告。
