verdict: pass
validation_command: xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue26-integrated-validation.oSxHSK build-for-testing; direct xcrun xctest (249/249); swiftlint --strict (27/27); git diff --check; xcodebuild Release CURRENT_PROJECT_VERSION=4; codesign --verify --deep --strict; reuse boundary: later changes were documentation count and workflow archive bookkeeping only
validated_candidate_hash: bbe694ad45157e6a798fe7c0869059f6926dea428923d0a8255a047d661cdcc4
