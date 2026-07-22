platform :ios, '17.0'
use_frameworks!
inhibit_all_warnings!

# Official VideoLAN VLCKit (LGPL) — original binaries, not third-party SPM wrappers.
#   xcodegen generate
#   pod install
#   open SportsDash.xcworkspace   # required — do not open .xcodeproj alone

target 'SportsDash' do
  pod 'MobileVLCKit', '~> 3.6'
end

target 'SportsDashTV' do
  platform :tvos, '17.0'
  pod 'TVVLCKit', '~> 3.6'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['TVOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      # Avoid sandboxing issues on some Xcode versions when linking large binary pods
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    end
  end
end
