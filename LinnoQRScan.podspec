#
# Be sure to run `pod lib lint QRScan.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'LinnoQRScan'
  s.version          = '0.2.7'
  s.summary          = '基于 AVCaptureSession 的二维码 / 条码 / 人体识别组件，支持扫描区域裁剪、多帧择优、自动变焦与手电控制。'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
LinnoQRScan 是一个轻量的 iOS 扫描组件，对 AVCaptureSession / AVMetadataOutput 做了开箱即用的封装：

- 支持二维码、一维条码，以及人体 / 猫狗识别（Bodies 需要 iOS 13 及以上）
- scanState 可用于组合识别类型，supportCodeTypes 可完全自定义
- 支持指定预览 bounds 与扫描区域 scanFrame
- 支持多帧择优（fpsNum >= 2 时在预览上绘制识别框，点击框回调结果）
- 支持手动变焦与自动变焦（按码在预览中的占比自动推近 / 拉远）
- 支持手电控制、暂停 / 恢复识别
- 同时提供 Swift 与 Objective-C 两套初始化入口
                       DESC

  s.homepage         =  'https://github.com/linnoIt/LinnoQRScan'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'linnoIt' => 'it@linno.cn' }
  s.source           = { :git => 'https://github.com/linnoIt/LinnoQRScan.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '12.0'
  
  s.swift_version = '5.0'

  s.source_files = 'QRScan/Classes/**/*'
  
#  s.resource_bundles = {
#    'QRScan' => ['QRScan/Assets/*.wav']
#  }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
