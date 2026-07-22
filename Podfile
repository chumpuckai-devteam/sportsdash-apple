platform :ios, '17.0'
use_frameworks!
inhibit_all_warnings!

# Official VideoLAN VLCKit (LGPL) — original binaries.
#   xcodegen generate
#   pod install
#   open SportsDash.xcworkspace   # required

target 'SportsDash' do
  pod 'MobileVLCKit', '~> 3.6'
end

target 'SportsDashTV' do
  platform :tvos, '17.0'
  pod 'TVVLCKit', '~> 3.6'
end

post_install do |installer|
  # Xcode 15+ User Script Sandbox blocks CocoaPods' rsync of MobileVLCKit.framework
  # ("Sandbox: rsync deny …"). Disable sandbox on every Pods + user target.
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['TVOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    end
  end

  installer.aggregate_targets.each do |aggregate|
    aggregate.user_project.native_targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      end
    end
    aggregate.user_project.build_configurations.each do |config|
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    end
    aggregate.user_project.save
  end
end
