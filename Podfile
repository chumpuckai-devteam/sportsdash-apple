platform :ios, '17.0'
use_frameworks!
inhibit_all_warnings!

# Official VideoLAN binaries (LGPL). After `xcodegen generate`:
#   pod install
#   open SportsDash.xcworkspace

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
      # Silence bitcode leftovers on older pod specs
      config.build_settings['ENABLE_BITCODE'] = 'NO'
    end
  end
end
