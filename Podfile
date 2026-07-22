# CocoaPods path (optional / not used by default)

Default integration is **SPM** via `Project.yml` → [tylerjonesio/vlckit-spm](https://github.com/tylerjonesio/vlckit-spm)
(official MobileVLCKit / TVVLCKit binaries).

Use this Podfile only if you deliberately switch back to CocoaPods:

```ruby
# See git history for full Podfile
pod 'MobileVLCKit', '~> 3.6'
```

If you do:
1. Remove the VLCKitSPM package from Project.yml
2. `xcodegen generate && pod install`
3. Open `.xcworkspace`
4. Set **User Script Sandboxing = No** on the app target
5. Prefer: `install! 'cocoapods', :disable_input_output_paths => true`
