# QRScan

[![Swift](https://img.shields.io/badge/Swift-5-orange?style=flat-square)](https://img.shields.io/badge/Swift-5-Orange?style=flat-square)
[![Version](https://img.shields.io/cocoapods/v/LinnoQRScan.svg?style=flat)](https://cocoapods.org/pods/LinnoQRScan)
[![License](https://img.shields.io/cocoapods/l/LinnoQRScan.svg?style=flat)](https://cocoapods.org/pods/LinnoQRScan)
[![Platform:iOS 10.0](https://img.shields.io/cocoapods/p/LinnoQRScan.svg?style=flat)](https://cocoapods.org/pods/LinnoQRScan)


## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

1.support object-c
2.support quickly build
3.scan success -> "di" 
4.update -[AVCaptureSession startRunning] should be called from background thread. Calling it on the main thread can lead to UI unresponsiveness question
5.Manually adjust the focal length

## Installation

QRScan is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'LinnoQRScan'
```

## Author

linnoIt, it@linno.cn

## License

QRScan is available under the MIT license. See the LICENSE file for more info.
