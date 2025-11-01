Pod::Spec.new do |spec|
  spec.name         = "GPBonusSDK"
  spec.version      = ENV['LIB_VERSION'] || "2.2.0"
  spec.summary      = "GazpromBonus widget integration lib"
  spec.homepage     = "https://github.com/SetPartnerstv/ios-sdk"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = "SetPartnerstv"
  spec.platform     = :ios, "15.6"
  spec.source       = { :git => "https://github.com/SetPartnerstv/ios-sdk.git", :tag => "#{spec.version}" }
  spec.source_files = "sdk/**/*.{swift,h,m}"
  spec.requires_arc = true
  spec.swift_version = "5.0"
  spec.dependency "SwiftProtobuf", "~> 1.14.0"
  spec.frameworks = ["UIKit", "WebKit"]
end
