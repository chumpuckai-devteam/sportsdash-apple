# SportsDash — VLCKit (LGPL) hard engine
# Open SportsDash.xcworkspace after `pod install` (not the bare xcodeproj).
platform :ios, '17.0'
inhibit_all_warnings!
use_frameworks!

workspace 'SportsDash.xcworkspace'

# iOS app
target 'SportsDash' do
  project 'SportsDash.xcodeproj'
  pod 'MobileVLCKit', '~> 3.6'

  target 'SportsDashTests' do
    inherit! :search_paths
  end
end

# tvOS app — separate platform block
target 'SportsDashTV' do
  platform :tvos, '17.0'
  project 'SportsDash.xcodeproj'
  pod 'TVVLCKit', '~> 3.6'

  target 'SportsDashTVTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |config|
      # Xcode 15+ sandbox blocks CocoaPods rsync of large VLC frameworks.
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0' if t.platform_name == :ios
      config.build_settings['TVOS_DEPLOYMENT_TARGET'] = '17.0' if t.platform_name == :tvos
    end
  end
  # Also force user project settings when CocoaPods touches them
  installer.aggregate_targets.each do |aggregate|
    aggregate.user_project.native_targets.each do |nt|
      nt.build_configurations.each do |config|
        config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      end
    end
    aggregate.user_project.save
  end
end
