verdict: pass
validation_command: xcodebuild build-for-testing; xcrun xctest FeishuSpeechTests.xctest; swiftlint lint --strict; xcodebuild Debug build; xcodebuild Release build; codesign --verify --deep --strict
validated_candidate_hash: 5a63394083edf321e626429e3f2a74dd1423ed154d4fbcfb057c0dab9ca24fa4
