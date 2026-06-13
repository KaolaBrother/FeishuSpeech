# Final Validation - issue-15

Working directory: /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
Started: 2026-06-13T14:30:06+0800

## xcodebuild test

```text
$ xcodebuild -scheme FeishuSpeech -destination platform=macOS test
Command line invocation:
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -scheme FeishuSpeech -destination platform=macOS test

2026-06-13 14:30:07.197 xcodebuild[63468:261394769] [MT] IDERunDestination: Supported platforms for the buildables in the current scheme is empty.
--- xcodebuild: WARNING: Using the first of multiple matching destinations:
{ platform:macOS, arch:arm64, id:00006050-001B10912131401C, name:My Mac }
{ platform:macOS, arch:x86_64, id:00006050-001B10912131401C, name:My Mac }
ComputePackagePrebuildTargetDependencyGraph

Prepare packages

CreateBuildRequest

SendProjectDescription

CreateBuildOperation

ComputeTargetDependencyGraph
note: Building targets in dependency order
note: Target dependency graph (2 targets)
    Target 'FeishuSpeechTests' in project 'FeishuSpeech'
        ➜ Explicit dependency on target 'FeishuSpeech' in project 'FeishuSpeech'
    Target 'FeishuSpeech' in project 'FeishuSpeech' (no dependencies)

GatherProvisioningInputs

CreateBuildDescription

ExecuteExternalTool /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc --version

ExecuteExternalTool /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -v -E -dM -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk -x c -c /dev/null

ExecuteExternalTool /Applications/Xcode.app/Contents/Developer/usr/bin/actool --version --output-format xml1

ExecuteExternalTool /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/ld -version_details

Build description signature: e9f09e9031d4da8584b2cd8a817e6274
Build description path: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/XCBuildData/e9f09e9031d4da8584b2cd8a817e6274.xcbuilddata
ClangStatCache /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-stat-cache /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk /Users/ylpromax5/Library/Developer/Xcode/DerivedData/SDKStatCaches.noindex/macosx26.5-25F70-e082c4a02f00227109f4ed75e425c832.sdkstatcache
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech.xcodeproj
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-stat-cache /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/SDKStatCaches.noindex/macosx26.5-25F70-e082c4a02f00227109f4ed75e425c832.sdkstatcache

MkDir /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest (in target 'FeishuSpeechTests' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /bin/mkdir -p /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest

MkDir /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents (in target 'FeishuSpeechTests' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /bin/mkdir -p /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents

MkDir /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/MacOS (in target 'FeishuSpeechTests' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /bin/mkdir -p /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/MacOS

MkDir /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /bin/mkdir -p /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns

MkDir /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /bin/mkdir -p /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks

ProcessProductPackaging /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/FeishuSpeech.entitlements /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/FeishuSpeech.app.xcent (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Entitlements:
    
    {
    "com.apple.security.automation.apple-events" = 1;
    "com.apple.security.device.audio-input" = 1;
    "com.apple.security.get-task-allow" = 1;
}
    
    builtin-productPackagingUtility /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/FeishuSpeech.entitlements -entitlements -format xml -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/FeishuSpeech.app.xcent

ProcessProductPackagingDER /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/FeishuSpeech.app.xcent /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/FeishuSpeech.app.xcent.der (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /usr/bin/derq query -f xml -i /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/FeishuSpeech.app.xcent -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/FeishuSpeech.app.xcent.der --raw

Copy /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTest.framework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -exclude Headers -exclude PrivateHeaders -exclude Modules -exclude \*.tbd -resolve-src-symlinks /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks

Copy /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTestCore.framework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks/XCTestCore.framework (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -exclude Headers -exclude PrivateHeaders -exclude Modules -exclude \*.tbd -resolve-src-symlinks /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks/XCTestCore.framework /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks

Copy /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTAutomationSupport.framework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks/XCTAutomationSupport.framework (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -exclude Headers -exclude PrivateHeaders -exclude Modules -exclude \*.tbd -resolve-src-symlinks /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks/XCTAutomationSupport.framework /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks

Copy /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTestSupport.framework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks/XCTestSupport.framework (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -exclude Headers -exclude PrivateHeaders -exclude Modules -exclude \*.tbd -resolve-src-symlinks /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks/XCTestSupport.framework /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks

Copy /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/libXCTestSwiftSupport.dylib /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/libXCTestSwiftSupport.dylib (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -exclude Headers -exclude PrivateHeaders -exclude Modules -exclude \*.tbd -resolve-src-symlinks /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/libXCTestSwiftSupport.dylib /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks

Copy /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCUnit.framework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks/XCUnit.framework (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -exclude Headers -exclude PrivateHeaders -exclude Modules -exclude \*.tbd -resolve-src-symlinks /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks/XCUnit.framework /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks

Copy /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/libXCTestBundleInject.dylib /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/libXCTestBundleInject.dylib (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -exclude Headers -exclude PrivateHeaders -exclude Modules -exclude \*.tbd -resolve-src-symlinks /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/libXCTestBundleInject.dylib /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks

Copy /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/Testing.framework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/Testing.framework (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -exclude Headers -exclude PrivateHeaders -exclude Modules -exclude \*.tbd -resolve-src-symlinks /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/Testing.framework /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks

Copy /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCUIAutomation.framework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCUIAutomation.framework (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -exclude Headers -exclude PrivateHeaders -exclude Modules -exclude \*.tbd -resolve-src-symlinks /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCUIAutomation.framework /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks

ProcessInfoPlistFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Info.plist /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Info.plist (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-infoPlistUtility /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Info.plist -producttype com.apple.product-type.application -genpkginfo /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PkgInfo -expandbuildsettings -platform macosx -additionalcontentfile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/assetcatalog_generated_info.plist -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Info.plist

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/libXCTestBundleInject.dylib (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --preserve-metadata\=identifier,entitlements,flags --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/libXCTestBundleInject.dylib
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/libXCTestBundleInject.dylib: replacing existing signature

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/libXCTestSwiftSupport.dylib (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --preserve-metadata\=identifier,entitlements,flags --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/libXCTestSwiftSupport.dylib
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/libXCTestSwiftSupport.dylib: replacing existing signature

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTest.framework (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --preserve-metadata\=identifier,entitlements,flags --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTest.framework
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTest.framework: replacing existing signature

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTestSupport.framework (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --preserve-metadata\=identifier,entitlements,flags --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTestSupport.framework
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTestSupport.framework: replacing existing signature

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCUnit.framework (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --preserve-metadata\=identifier,entitlements,flags --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCUnit.framework
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCUnit.framework: replacing existing signature

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTAutomationSupport.framework (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --preserve-metadata\=identifier,entitlements,flags --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTAutomationSupport.framework
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTAutomationSupport.framework: replacing existing signature

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTestCore.framework (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --preserve-metadata\=identifier,entitlements,flags --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTestCore.framework
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCTestCore.framework: replacing existing signature

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCUIAutomation.framework (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --preserve-metadata\=identifier,entitlements,flags --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCUIAutomation.framework
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/XCUIAutomation.framework: replacing existing signature

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/Testing.framework (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --preserve-metadata\=identifier,entitlements,flags --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/Testing.framework
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks/Testing.framework: replacing existing signature

ProcessInfoPlistFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/Info.plist /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeechTests.build/empty-FeishuSpeechTests.plist (in target 'FeishuSpeechTests' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-infoPlistUtility /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeechTests.build/empty-FeishuSpeechTests.plist -producttype com.apple.product-type.bundle.unit-test -expandbuildsettings -platform macosx -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/Info.plist

Ld /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/MacOS/FeishuSpeechTests normal (in target 'FeishuSpeechTests' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -Xlinker -reproducible -target arm64-apple-macos26.2 -bundle -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk -O0 -L/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/EagerLinkingTBDs/Debug -L/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug -L/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib -F/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/EagerLinkingTBDs/Debug -F/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks -filelist /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeechTests.build/Objects-normal/arm64/FeishuSpeechTests.LinkFileList -Xlinker -rpath -Xlinker @loader_path/../Frameworks -Xlinker -rpath -Xlinker @executable_path/../Frameworks -bundle_loader /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/FeishuSpeech -Xlinker -object_path_lto -Xlinker /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeechTests.build/Objects-normal/arm64/FeishuSpeechTests_lto.o -rdynamic -Xlinker -no_deduplicate -Xlinker -debug_variant -Xlinker -dependency_info -Xlinker /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeechTests.build/Objects-normal/arm64/FeishuSpeechTests_dependency_info.dat -fobjc-link-runtime -fprofile-instr-generate -L/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx -L/usr/lib/swift -Xlinker -add_ast_path -Xlinker /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeechTests.build/Objects-normal/arm64/FeishuSpeechTests.swiftmodule @/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeechTests.build/Objects-normal/arm64/FeishuSpeechTests-linker-args.resp -Xlinker -needed_framework -Xlinker XCTest -framework XCTest -Xlinker -needed-lXCTestSwiftSupport -lXCTestSwiftSupport /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/FeishuSpeech.debug.dylib -Xlinker -no_adhoc_codesign -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/MacOS/FeishuSpeechTests

CopySwiftLibs /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest (in target 'FeishuSpeechTests' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-swiftStdLibTool --copy --verbose --sign - --scan-executable /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/MacOS/FeishuSpeechTests --scan-folder /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/Frameworks --scan-folder /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/PlugIns --scan-folder /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/Library/SystemExtensions --scan-folder /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/Extensions --platform macosx --toolchain /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain --destination /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/Frameworks --strip-bitcode --scan-executable /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/libXCTestSwiftSupport.dylib --strip-bitcode-tool /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/bitcode_strip --emit-dependency-info /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeechTests.build/SwiftStdLibToolInputDependencies.dep --filter-for-swift-os

ExtractAppIntentsMetadata (in target 'FeishuSpeechTests' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsmetadataprocessor --toolchain-dir /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain --module-name FeishuSpeechTests --sdk-root /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk --xcode-version 17F42 --platform-family macOS --deployment-target 26.2 --bundle-identifier Siji.FeishuSpeechTests --output /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/Resources --target-triple arm64-apple-macos26.2 --binary-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest/Contents/MacOS/FeishuSpeechTests --dependency-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeechTests.build/Objects-normal/arm64/FeishuSpeechTests_dependency_info.dat --stringsdata-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeechTests.build/Objects-normal/arm64/ExtractedAppShortcutsMetadata.stringsdata --source-file-list /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeechTests.build/Objects-normal/arm64/FeishuSpeechTests.SwiftFileList --metadata-file-list /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeechTests.build/FeishuSpeechTests.DependencyMetadataFileList --static-metadata-file-list /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeechTests.build/FeishuSpeechTests.DependencyStaticMetadataFileList --swift-const-vals-list /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeechTests.build/Objects-normal/arm64/FeishuSpeechTests.SwiftConstValuesFileList --compile-time-extraction --deployment-aware-processing --validate-assistant-intents --no-app-shortcuts-localization
2026-06-13 14:30:08.565 appintentsmetadataprocessor[63734:261395497] Starting appintentsmetadataprocessor export
2026-06-13 14:30:08.566 appintentsmetadataprocessor[63734:261395497] warning: Metadata extraction skipped. No AppIntents.framework dependency found.

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest (in target 'FeishuSpeechTests' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --entitlements /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeechTests.build/FeishuSpeechTests.xctest.xcent --timestamp\=none --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest

RegisterExecutionPolicyException /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest (in target 'FeishuSpeechTests' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-RegisterExecutionPolicyException /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest

Touch /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest (in target 'FeishuSpeechTests' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /usr/bin/touch -c /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/FeishuSpeech.debug.dylib (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/FeishuSpeech.debug.dylib
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/FeishuSpeech.debug.dylib: replacing existing signature

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/__preview.dylib (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/__preview.dylib
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/__preview.dylib: replacing existing signature

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --entitlements /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/FeishuSpeech.app.xcent --timestamp\=none --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app: replacing existing signature

Validate /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-validationUtility /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app -no-validate-extension -infoplist-subpath Contents/Info.plist

RegisterWithLaunchServices /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app

Testing started
Test suite 'HotKeyServiceTests' started on 'My Mac - FeishuSpeech (63774)'
Test case 'HotKeyServiceTests.test_cancelled_isNotActive()' passed on 'My Mac - FeishuSpeech (63774)' (0.007 seconds)
Test case 'HotKeyServiceTests.test_error_isNotActive()' passed on 'My Mac - FeishuSpeech (63774)' (0.001 seconds)
Test case 'HotKeyServiceTests.test_fnReleasedDuringTranscribing_stateRemainsTranscribing()' passed on 'My Mac - FeishuSpeech (63774)' (0.001 seconds)
Test case 'HotKeyServiceTests.test_forceTranscribing_fromRecording_transitionsToTranscribing()' passed on 'My Mac - FeishuSpeech (63774)' (0.001 seconds)
Test case 'HotKeyServiceTests.test_forceTranscribing_whenAlreadyTranscribing_isNoOp()' passed on 'My Mac - FeishuSpeech (63774)' (0.007 seconds)
Test case 'HotKeyServiceTests.test_idle_isNotActive()' passed on 'My Mac - FeishuSpeech (63774)' (0.004 seconds)
Test case 'HotKeyServiceTests.test_idle_shouldNotShowOverlay()' passed on 'My Mac - FeishuSpeech (63774)' (0.004 seconds)
Test case 'HotKeyServiceTests.test_initialState_isIdle()' passed on 'My Mac - FeishuSpeech (63774)' (0.007 seconds)
Test case 'HotKeyServiceTests.test_monitoringState_publishesFailedOnEachRetryAttempt()' passed on 'My Mac - FeishuSpeech (63774)' (0.006 seconds)
Test case 'HotKeyServiceTests.test_pending_isActive()' passed on 'My Mac - FeishuSpeech (63774)' (0.055 seconds)
Test case 'HotKeyServiceTests.test_pending_shouldNotShowOverlay()' passed on 'My Mac - FeishuSpeech (63774)' (0.014 seconds)
Test case 'HotKeyServiceTests.test_postTimeoutResync_fnStillHeld_doesNotTriggerRelease()' passed on 'My Mac - FeishuSpeech (63774)' (0.102 seconds)
Test suite 'PermissionManagerTests' started on 'My Mac - FeishuSpeech (63866)'
Test suite 'MainViewModelTests' started on 'My Mac - FeishuSpeech (63871)'
Test case 'MainViewModelTests.test_cleanup_releasesStateCancellable()' passed on 'My Mac - FeishuSpeech (63871)' (0.001 seconds)
Test case 'MainViewModelTests.test_stateCancellable_isNil_afterStopHotKeyMonitoring()' passed on 'My Mac - FeishuSpeech (63871)' (0.002 seconds)
Test suite 'AudioRecorderFailureTests' started on 'My Mac - FeishuSpeech (63886)'
Test case 'MainViewModelTests.test_stateCancellable_replacedNotAccumulated_onRestart()' passed on 'My Mac - FeishuSpeech (63871)' (0.002 seconds)
Test case 'PermissionManagerTests.test_refreshMicrophoneStatus_updatesAllPermissionsGrantedWhenMicrophoneChanges()' passed on 'My Mac - FeishuSpeech (63866)' (0.009 seconds)
Test case 'AudioRecorderFailureTests.test_backgroundRuntimeError_cleansUpRecorderOnMainThread()' passed on 'My Mac - FeishuSpeech (63886)' (0.004 seconds)
Test case 'PermissionManagerTests.test_refreshMicrophoneStatus_usesInjectedAuthorizedProvider()' passed on 'My Mac - FeishuSpeech (63866)' (0.003 seconds)
Test suite 'EmptyResultFeedbackTests' started on 'My Mac - FeishuSpeech (63871)'
Test case 'AudioRecorderFailureTests.test_conversionExhaustion_publishesFormatConversionFailure()' passed on 'My Mac - FeishuSpeech (63886)' (0.001 seconds)
Test case 'EmptyResultFeedbackTests.test_emptyRecognitionResult_setsOverlayMessage()' passed on 'My Mac - FeishuSpeech (63871)' (0.001 seconds)
Test case 'AudioRecorderFailureTests.test_runtimeError_publishesRuntimeFailure()' passed on 'My Mac - FeishuSpeech (63886)' (0.002 seconds)
Test case 'PermissionManagerTests.test_refreshSecureInputStatus_existsAndIsCallable()' passed on 'My Mac - FeishuSpeech (63866)' (0.004 seconds)
Test case 'HotKeyServiceTests.test_postTimeoutResync_missedFnRelease_triggersHandleFnReleased()' passed on 'My Mac - FeishuSpeech (63774)' (0.102 seconds)
Test suite 'FeishuAPIServiceTests' started on 'My Mac - FeishuSpeech (63895)'
Test case 'FeishuAPIServiceTests.test_authResponse_decodesExpireFromFeishuPayload()' passed on 'My Mac - FeishuSpeech (63895)' (0.001 seconds)
Test case 'EmptyResultFeedbackTests.test_nonEmptyRecognitionResult_doesNotSetOverlayMessage()' passed on 'My Mac - FeishuSpeech (63871)' (0.009 seconds)
Test case 'AudioRecorderFailureTests.test_viewModelRecorderFailure_cleansUpAndShowsSpecificError()' passed on 'My Mac - FeishuSpeech (63886)' (0.008 seconds)
Test case 'EmptyResultFeedbackTests.test_whitespaceOnlyRecognitionResult_setsOverlayMessage()' passed on 'My Mac - FeishuSpeech (63871)' (0.000 seconds)
Test case 'FeishuAPIServiceTests.test_directHTTPParser_whenChunkedBodyLacksTerminalChunk_waitsForMoreData()' passed on 'My Mac - FeishuSpeech (63895)' (0.001 seconds)
Test case 'PermissionManagerTests.test_refreshSecureInputStatus_publishesNewValueWhenChanged()' passed on 'My Mac - FeishuSpeech (63866)' (0.007 seconds)
Test case 'FeishuAPIServiceTests.test_directHTTPParser_whenCloseDelimited_waitsUntilConnectionClose()' passed on 'My Mac - FeishuSpeech (63895)' (0.001 seconds)
Test case 'FeishuAPIServiceTests.test_directHTTPParser_whenContentLengthBodyComplete_returnsResponse()' passed on 'My Mac - FeishuSpeech (63895)' (0.000 seconds)
Test case 'FeishuAPIServiceTests.test_directHTTPParser_whenContentLengthBodyIncomplete_waitsForMoreData()' passed on 'My Mac - FeishuSpeech (63895)' (0.001 seconds)
Test case 'PermissionManagerTests.test_refreshSecureInputStatus_updatesSecureInputEnabled()' passed on 'My Mac - FeishuSpeech (63866)' (0.007 seconds)
Test suite 'MonitoringStateBindingTests' started on 'My Mac - FeishuSpeech (63871)'
Test suite 'HotKeyStateTests' started on 'My Mac - FeishuSpeech (63886)'
Test case 'HotKeyStateTests.test_cancelReason_eventTapDisabled_description()' passed on 'My Mac - FeishuSpeech (63886)' (0.001 seconds)
Test case 'HotKeyStateTests.test_cancelReason_modifierCombo_description()' passed on 'My Mac - FeishuSpeech (63886)' (0.000 seconds)
Test case 'HotKeyStateTests.test_cancelReason_otherKeyPressed_description()' passed on 'My Mac - FeishuSpeech (63886)' (0.001 seconds)
Test case 'FeishuAPIServiceTests.test_directHTTPParser_whenTerminalChunkedBodyComplete_returnsDecodedBody()' passed on 'My Mac - FeishuSpeech (63895)' (0.001 seconds)
Test case 'MonitoringStateBindingTests.test_accessibilityNotTrustedFailure_setsStatusError()' passed on 'My Mac - FeishuSpeech (63871)' (0.001 seconds)
Test case 'HotKeyStateTests.test_cancelReason_releasedTooSoon_description()' passed on 'My Mac - FeishuSpeech (63886)' (0.000 seconds)
Test case 'MonitoringStateBindingTests.test_activeAfterTapFailure_clearsStaleTapFailureError()' passed on 'My Mac - FeishuSpeech (63871)' (0.008 seconds)
Test case 'PermissionManagerTests.test_secureInputEnabled_initialValueIsFalse()' passed on 'My Mac - FeishuSpeech (63866)' (0.007 seconds)
Test case 'MonitoringStateBindingTests.test_activeDoesNotClearUnrelatedError()' passed on 'My Mac - FeishuSpeech (63871)' (0.001 seconds)
Test case 'PermissionManagerTests.test_secureInputEnabled_isPublishedBool()' passed on 'My Mac - FeishuSpeech (63866)' (0.007 seconds)
Test case 'FeishuAPIServiceTests.test_sendDirectRequest_whenDirectSenderCancels_doesNotTryLaterIPsOrFallback()' passed on 'My Mac - FeishuSpeech (63895)' (0.013 seconds)
Test case 'FeishuAPIServiceTests.test_timeoutFallback_parsesCompleteBufferedContentLengthResponse()' passed on 'My Mac - FeishuSpeech (63895)' (0.000 seconds)
Test case 'FeishuAPIServiceTests.test_timeoutFallback_rejectsIncompleteBufferedContentLengthBody()' passed on 'My Mac - FeishuSpeech (63895)' (0.000 seconds)
Test case 'MonitoringStateBindingTests.test_tapCreationFailure_setsStatusError()' passed on 'My Mac - FeishuSpeech (63871)' (0.013 seconds)
Test case 'FeishuAPIServiceTests.test_tokenLifetimeForMissingOrInvalidExpire_fallsBackToDefault()' passed on 'My Mac - FeishuSpeech (63895)' (0.001 seconds)
Test case 'FeishuAPIServiceTests.test_tokenLifetimeForShortPositiveExpire_expiresImmediatelyInsteadOfDefaultFallback()' passed on 'My Mac - FeishuSpeech (63895)' (0.010 seconds)
Test case 'FeishuAPIServiceTests.test_tokenLifetimeForValidExpire_usesExpireMinusSafetyMargin()' passed on 'My Mac - FeishuSpeech (63895)' (0.001 seconds)
Test case 'FeishuAPIServiceTests.test_withRetry_whenOperationThrowsCancellation_attemptsOnceAndRethrows()' passed on 'My Mac - FeishuSpeech (63895)' (0.004 seconds)
Test case 'HotKeyServiceTests.test_recording_isActive()' passed on 2026-06-13 14:30:14.224 xcodebuild[63468:261394769] [MT] IDETestOperationsObserverDebug: 5.580 elapsed -- Testing started completed.
2026-06-13 14:30:14.224 xcodebuild[63468:261394769] [MT] IDETestOperationsObserverDebug: 0.000 sec, +0.000 sec -- start
2026-06-13 14:30:14.224 xcodebuild[63468:261394769] [MT] IDETestOperationsObserverDebug: 5.580 sec, +5.580 sec -- end

Test session results, code coverage, and logs:
	/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Logs/Test/Test-FeishuSpeech-2026.06.13_14-30-07-+0800.xcresult

** TEST SUCCEEDED **

'My Mac - FeishuSpeech (63774)' (0.101 seconds)
Test case 'HotKeyServiceTests.test_recording_shouldShowOverlay()' passed on 'My Mac - FeishuSpeech (63774)' (0.093 seconds)
Test case 'HotKeyServiceTests.test_resetToIdle_setsStateToIdle()' passed on 'My Mac - FeishuSpeech (63774)' (0.102 seconds)
Test case 'HotKeyServiceTests.test_retryBackoff_isExponentialWithCap()' passed on 'My Mac - FeishuSpeech (63774)' (0.202 seconds)
Test case 'HotKeyServiceTests.test_setError_setsErrorState()' passed on 'My Mac - FeishuSpeech (63774)' (0.203 seconds)
Test case 'HotKeyServiceTests.test_startMonitoring_whenNotTrusted_setsMonitoringStateToFailed()' passed on 'My Mac - FeishuSpeech (63774)' (0.203 seconds)
Test case 'HotKeyServiceTests.test_startMonitoring_whenTapCreationFails_setsMonitoringStateToFailed()' passed on 'My Mac - FeishuSpeech (63774)' (0.203 seconds)
Test case 'HotKeyServiceTests.test_startMonitoring_whenTapCreationSucceeds_setsMonitoringStateToActive()' passed on 'My Mac - FeishuSpeech (63774)' (0.203 seconds)
Test case 'HotKeyServiceTests.test_stopMonitoring_resetsPreviousFlags()' passed on 'My Mac - FeishuSpeech (63774)' (0.203 seconds)
Test case 'HotKeyServiceTests.test_stopMonitoring_setsMonitoringStateToStopped()' passed on 'My Mac - FeishuSpeech (63774)' (0.203 seconds)
Test case 'HotKeyServiceTests.test_tapRunLoop_isNotMainRunLoop()' passed on 'My Mac - FeishuSpeech (63774)' (2.235 seconds)
```

exit_code: 0

## xcodebuild Debug build

```text
$ xcodebuild -scheme FeishuSpeech -configuration Debug build
Command line invocation:
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -scheme FeishuSpeech -configuration Debug build

2026-06-13 14:30:14.745 xcodebuild[64674:261398242] [MT] IDERunDestination: Supported platforms for the buildables in the current scheme is empty.
--- xcodebuild: WARNING: Using the first of multiple matching destinations:
{ platform:macOS, arch:arm64, id:00006050-001B10912131401C, name:My Mac }
{ platform:macOS, arch:x86_64, id:00006050-001B10912131401C, name:My Mac }
{ platform:macOS, name:Any Mac }
ComputePackagePrebuildTargetDependencyGraph

Prepare packages

CreateBuildRequest

SendProjectDescription

CreateBuildOperation

ComputeTargetDependencyGraph
note: Building targets in dependency order
note: Target dependency graph (1 target)
    Target 'FeishuSpeech' in project 'FeishuSpeech' (no dependencies)

GatherProvisioningInputs

CreateBuildDescription

ExecuteExternalTool /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -v -E -dM -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk -x c -c /dev/null

ExecuteExternalTool /Applications/Xcode.app/Contents/Developer/usr/bin/actool --version --output-format xml1

ExecuteExternalTool /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc --version

ExecuteExternalTool /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/ld -version_details

Build description signature: 884f240993aed4b53eaa7b48c0f7d517
Build description path: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/XCBuildData/884f240993aed4b53eaa7b48c0f7d517.xcbuilddata
ClangStatCache /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-stat-cache /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk /Users/ylpromax5/Library/Developer/Xcode/DerivedData/SDKStatCaches.noindex/macosx26.5-25F70-e082c4a02f00227109f4ed75e425c832.sdkstatcache
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech.xcodeproj
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-stat-cache /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/SDKStatCaches.noindex/macosx26.5-25F70-e082c4a02f00227109f4ed75e425c832.sdkstatcache

ProcessProductPackaging /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/FeishuSpeech.entitlements /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/FeishuSpeech.app.xcent (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Entitlements:
    
    {
    "com.apple.security.automation.apple-events" = 1;
    "com.apple.security.device.audio-input" = 1;
    "com.apple.security.get-task-allow" = 1;
}
    
    builtin-productPackagingUtility /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/FeishuSpeech.entitlements -entitlements -format xml -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/FeishuSpeech.app.xcent

ProcessProductPackagingDER /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/FeishuSpeech.app.xcent /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/FeishuSpeech.app.xcent.der (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /usr/bin/derq query -f xml -i /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/FeishuSpeech.app.xcent -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/FeishuSpeech.app.xcent.der --raw

ProcessInfoPlistFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Info.plist /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Info.plist (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-infoPlistUtility /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Info.plist -producttype com.apple.product-type.application -genpkginfo /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PkgInfo -expandbuildsettings -platform macosx -additionalcontentfile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/assetcatalog_generated_info.plist -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Info.plist

CopySwiftLibs /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-swiftStdLibTool --copy --verbose --sign - --scan-executable /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/FeishuSpeech.debug.dylib --scan-folder /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks --scan-folder /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns --scan-folder /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Library/SystemExtensions --scan-folder /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Extensions --platform macosx --toolchain /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain --destination /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks --strip-bitcode --strip-bitcode-tool /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/bitcode_strip --emit-dependency-info /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/SwiftStdLibToolInputDependencies.dep --filter-for-swift-os

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/FeishuSpeech.debug.dylib (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/FeishuSpeech.debug.dylib
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/FeishuSpeech.debug.dylib: replacing existing signature

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/__preview.dylib (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --timestamp\=none --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/__preview.dylib
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/MacOS/__preview.dylib: replacing existing signature

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --entitlements /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Debug/FeishuSpeech.build/FeishuSpeech.app.xcent --timestamp\=none --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app: replacing existing signature

Validate /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-validationUtility /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app -no-validate-extension -infoplist-subpath Contents/Info.plist

RegisterWithLaunchServices /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app

note: Removed stale file '/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/Frameworks'

note: Removed stale file '/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns'

** BUILD SUCCEEDED **

```

exit_code: 0

## xcodebuild Release build

```text
$ xcodebuild -scheme FeishuSpeech -configuration Release build
Command line invocation:
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -scheme FeishuSpeech -configuration Release build

2026-06-13 14:30:15.696 xcodebuild[64828:261398708] [MT] IDERunDestination: Supported platforms for the buildables in the current scheme is empty.
--- xcodebuild: WARNING: Using the first of multiple matching destinations:
{ platform:macOS, arch:arm64, id:00006050-001B10912131401C, name:My Mac }
{ platform:macOS, arch:x86_64, id:00006050-001B10912131401C, name:My Mac }
{ platform:macOS, name:Any Mac }
ComputePackagePrebuildTargetDependencyGraph

Prepare packages

CreateBuildRequest

SendProjectDescription

CreateBuildOperation

ComputeTargetDependencyGraph
note: Building targets in dependency order
note: Target dependency graph (1 target)
    Target 'FeishuSpeech' in project 'FeishuSpeech' (no dependencies)

GatherProvisioningInputs

CreateBuildDescription

ExecuteExternalTool /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -v -E -dM -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk -x c -c /dev/null

ExecuteExternalTool /Applications/Xcode.app/Contents/Developer/usr/bin/actool --version --output-format xml1

ExecuteExternalTool /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc --version

ExecuteExternalTool /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/ld -version_details

Build description signature: eb4ec26076472c15c62a2c133d88cbff
Build description path: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/XCBuildData/eb4ec26076472c15c62a2c133d88cbff.xcbuilddata
CreateBuildDirectory /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech.xcodeproj
    builtin-create-build-directory /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release

CreateBuildDirectory /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/EagerLinkingTBDs/Release
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech.xcodeproj
    builtin-create-build-directory /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/EagerLinkingTBDs/Release

ClangStatCache /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-stat-cache /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk /Users/ylpromax5/Library/Developer/Xcode/DerivedData/SDKStatCaches.noindex/macosx26.5-25F70-e082c4a02f00227109f4ed75e425c832.sdkstatcache
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech.xcodeproj
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-stat-cache /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/SDKStatCaches.noindex/macosx26.5-25F70-e082c4a02f00227109f4ed75e425c832.sdkstatcache

WriteAuxiliaryFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech-04c71e9ea23dc65ea1809f50a7340b8d-VFS/all-product-headers.yaml
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech.xcodeproj
    write-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech-04c71e9ea23dc65ea1809f50a7340b8d-VFS/all-product-headers.yaml

WriteAuxiliaryFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-all-non-framework-target-headers.hmap (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    write-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-all-non-framework-target-headers.hmap

WriteAuxiliaryFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech.DependencyStaticMetadataFileList (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    write-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech.DependencyStaticMetadataFileList

WriteAuxiliaryFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-generated-files.hmap (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    write-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-generated-files.hmap

WriteAuxiliaryFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech.hmap (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    write-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech.hmap

WriteAuxiliaryFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-project-headers.hmap (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    write-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-project-headers.hmap

WriteAuxiliaryFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech.DependencyMetadataFileList (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    write-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech.DependencyMetadataFileList

WriteAuxiliaryFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-all-target-headers.hmap (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    write-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-all-target-headers.hmap

WriteAuxiliaryFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-own-target-headers.hmap (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    write-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-own-target-headers.hmap

WriteAuxiliaryFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources/Entitlements.plist (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    write-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources/Entitlements.plist

MkDir /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /bin/mkdir -p /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents

WriteAuxiliaryFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.SwiftConstValuesFileList (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    write-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.SwiftConstValuesFileList

WriteAuxiliaryFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.SwiftFileList (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    write-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.SwiftFileList

WriteAuxiliaryFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech_const_extract_protocols.json (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    write-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech_const_extract_protocols.json

WriteAuxiliaryFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech-OutputFileMap.json (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    write-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech-OutputFileMap.json

WriteAuxiliaryFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.LinkFileList (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    write-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.LinkFileList

MkDir /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/Resources (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /bin/mkdir -p /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/Resources

MkDir /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/MacOS (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /bin/mkdir -p /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/MacOS

MkDir /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /bin/mkdir -p /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app

ProcessProductPackaging /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/FeishuSpeech.entitlements /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech.app.xcent (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Entitlements:
    
    {
    "com.apple.security.automation.apple-events" = 1;
    "com.apple.security.device.audio-input" = 1;
    "com.apple.security.get-task-allow" = 1;
}
    
    builtin-productPackagingUtility /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/FeishuSpeech.entitlements -entitlements -format xml -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech.app.xcent

ProcessProductPackagingDER /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech.app.xcent /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech.app.xcent.der (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /usr/bin/derq query -f xml -i /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech.app.xcent -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech.app.xcent.der --raw

GenerateAssetSymbols /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Resources/Assets.xcassets (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /Applications/Xcode.app/Contents/Developer/usr/bin/actool /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Resources/Assets.xcassets --compile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/Resources --output-format human-readable-text --notices --warnings --export-dependency-info /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_dependencies --output-partial-info-plist /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_generated_info.plist --app-icon AppIcon --accent-color AccentColor --enable-on-demand-resources NO --development-region en --target-device mac --minimum-deployment-target 26.2 --platform macosx --bundle-identifier Siji.FeishuSpeech --generate-swift-asset-symbols /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources/GeneratedAssetSymbols.swift --generate-objc-asset-symbols /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources/GeneratedAssetSymbols.h --generate-asset-symbol-index /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources/GeneratedAssetSymbols-Index.plist
/* com.apple.actool.compilation-results */
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources/GeneratedAssetSymbols-Index.plist
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources/GeneratedAssetSymbols.h
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources/GeneratedAssetSymbols.swift


MkDir /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_output/unthinned (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /bin/mkdir -p /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_output/unthinned

MkDir /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_output/thinned (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /bin/mkdir -p /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_output/thinned

CompileAssetCatalogVariant thinned /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/Resources /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Resources/Assets.xcassets (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /Applications/Xcode.app/Contents/Developer/usr/bin/actool /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Resources/Assets.xcassets --compile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_output/thinned --output-format human-readable-text --notices --warnings --export-dependency-info /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_dependencies_thinned --output-partial-info-plist /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_generated_info.plist_thinned --app-icon AppIcon --accent-color AccentColor --enable-on-demand-resources NO --development-region en --target-device mac --minimum-deployment-target 26.2 --platform macosx
/* com.apple.actool.compilation-results */
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_generated_info.plist_thinned
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_output/thinned/AppIcon.icns
/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_output/thinned/Assets.car


SwiftDriver FeishuSpeech normal arm64 com.apple.xcode.tools.swift.compiler (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-SwiftDriver -- /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -module-name FeishuSpeech -O -whole-module-optimization @/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.SwiftFileList -default-isolation\=MainActor -enable-bare-slash-regex -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature GlobalActorIsolatedTypesUsability -enable-upcoming-feature MemberImportVisibility -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-experimental-feature DebugDescriptionMacro -sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk -target arm64-apple-macos26.2 -g -module-cache-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex -Xfrontend -serialize-debugging-options -profile-coverage-mapping -profile-generate -swift-version 5 -I /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release -F /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release -emit-localized-strings -emit-localized-strings-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64 -c -num-threads 18 -Xcc -ivfsstatcache -Xcc /Users/ylpromax5/Library/Developer/Xcode/DerivedData/SDKStatCaches.noindex/macosx26.5-25F70-e082c4a02f00227109f4ed75e425c832.sdkstatcache -output-file-map /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech-OutputFileMap.json -use-frontend-parseable-output -save-temps -no-color-diagnostics -explicit-module-build -module-cache-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules -clang-scanner-module-cache-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex -sdk-module-cache-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex -serialize-diagnostics -emit-dependencies -emit-module -emit-module-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.swiftmodule -validate-clang-modules-once -clang-build-session-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/Session.modulevalidation -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/swift-overrides.hmap -emit-const-values -Xfrontend -const-gather-protocols-file -Xfrontend /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech_const_extract_protocols.json -Xcc -iquote -Xcc /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-generated-files.hmap -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-own-target-headers.hmap -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-all-target-headers.hmap -Xcc -iquote -Xcc /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-project-headers.hmap -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/include -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources-normal/arm64 -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources/arm64 -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources -emit-objc-header -emit-objc-header-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech-Swift.h -working-directory /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15 -no-emit-module-separately-wmo

SwiftCompile normal arm64 Compiling\ AppDelegate.swift,\ FeishuSpeechApp.swift,\ OverlayWindowController.swift,\ AppSettings.swift,\ RecordingState.swift,\ SpeechResult.swift,\ AudioRecorder.swift,\ FeishuAPIService.swift,\ HotKeyService.swift,\ HotKeyState.swift,\ LoginItemService.swift,\ PermissionManager.swift,\ TextInputSimulator.swift,\ MainViewModel.swift,\ MenuBarView.swift,\ PermissionView.swift,\ RecordingOverlayView.swift,\ SettingsView.swift,\ GeneratedAssetSymbols.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/App/AppDelegate.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/App/FeishuSpeechApp.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Controllers/OverlayWindowController.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Models/AppSettings.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Models/RecordingState.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Models/SpeechResult.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/AudioRecorder.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/FeishuAPIService.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/HotKeyService.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/HotKeyState.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/LoginItemService.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/PermissionManager.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/TextInputSimulator.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/ViewModels/MainViewModel.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Views/MenuBarView.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Views/PermissionView.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Views/RecordingOverlayView.swift /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Views/SettingsView.swift /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources/GeneratedAssetSymbols.swift /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/Darwin.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/Distributed.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/CoreFoundation.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/Symbols.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/SwiftUI.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/ObjectiveC.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/simd.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/CoreVideo.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/Foundation.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/CoreMedia.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/Spatial.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/AppKit.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/AVFoundation.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/CoreMIDI.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/_Concurrency.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/CoreImage.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/Network.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/Swift.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/AVFAudio.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/CoreText.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/_StringProcessing.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/Dispatch.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/DeveloperToolsSupport.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/CoreGraphics.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/QuartzCore.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/Accessibility.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/os.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/UniformTypeIdentifiers.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/Metal.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/Observation.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/Synchronization.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/DataDetection.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/Combine.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/CoreTransferable.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/XPC.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/System.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/AudioToolbox.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/IOKit.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/_DarwinFoundation3.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/CoreAudio.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/CoreData.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/_DarwinFoundation2.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/_Builtin_float.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/_DarwinFoundation1.swiftmodule/arm64e-apple-macos.swiftmodule /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/prebuilt-modules/26.5/OSLog.swiftmodule/arm64e-apple-macos.swiftmodule /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/Carbon-APZUCSWG4A2ZI34E7U1ONKAFV.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/CoreData-7BO0JP95W5E01NUB9L8QC9YQ3.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/Metal-DN95XFFJT1MZIFXRNQK8WQH6L.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/AVFoundation-2LVMZFHAEOFCEMN0LYKFQRWLA.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/ServiceManagement-B2AQIIYW5BRB15LW8EH3K7QCB.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/MediaToolbox-EIW7B59NVMU7A5BRF3LGZ8DWG.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/Dispatch-HA77BGBS5CWWFOJBJD0M8ZLG.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/DataDetection-1Y6NQ7Y4N94HY6O7Z2X2MCG3K.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/Symbols-7Z51YR3AK8VJ8J7U0SYHBEWA0.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/QuartzCore-4TRUT272EU3CWE6A0GHEKHYOR.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/_Builtin_stddef-DHVMZ8MJY1O5L0Q3T1KT5GI4D.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/CoreText-WGNKA9OJ5WOT5TBG28LUHT1H.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/SwiftUICore-2J2J03NUI9DXHLT70U8DA4Y3I.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/_DarwinFoundation3-77HOIEEMOBCT3XNCHENVTKGER.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/AppKit-1RME970PHIWVACPM0LQH6WOCD.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/launch-8L11C7RBMYXS3IVE5WWR6G61M.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/_DarwinFoundation2-5482SWMB4LTAZZKW74X42XRRD.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/sys_types-87WK6QD48F2O9IG2FPVS4U1TF.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/Accessibility-BRB6SD0VDU105LANKUIULLWHF.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/SwiftShims-37Q5PXINL2856AUPL618JFNIW.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/_Builtin_stdint-78PH9AD6W3X9KZ89ROOLPRHMW.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/CFNetwork-9VNAPRLWUHSW2VMI15LP041V8.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/Foundation-1ADXJ39DGDD42H3M4DRU63T26.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/ObjectiveC-WVPW9BVOO2N73H6JE89UDR64.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/AVFAudio-45HLRPJ0SAXA7426ZTEFZS0ZJ.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/CoreImage-DJU9AO05ZOWK9T5O7DWURBJAG.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/os-DCW94QJVF1VJX49RC835OMV7X.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/DiskArbitration-AWLTQJFGV1GBCMO5FBGM7941F.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/Security-DX5X3LYEFZ3RFQT44ZMMLSCJE.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/os_object-26YK1LQZL8L2SHA0U2M2VLEN2.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/libDER-6DTAUTLH7V0EO2ZUQ8EOKDV9I.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/OSLog-D3FDZ6TCYZAARG92I84ZXPFFW.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/Darwin-EKVXUFC9JRS1PQO4EM8ORV6TG.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/CoreAudio-5EG6F7N0Y724Q759EMA8QDSZU.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/AudioToolbox-53JJX7Y9BVQGPGDRD0DY239IS.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/Network-A7LBTI4K10Q0EMT4ET7005AJO.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/DeveloperToolsSupport-EP7HKMZZVIEZEBX8UAW399KV1.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/CoreAudioTypes-CEX587CZE7POIZ0I0NTL1C61J.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/ImageIO-EZMDY9U7UXANV5A4GBCKKAPLP.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/_SwiftConcurrencyShims-9OFCNN0QDOL71AOEI85NI8E4G.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/IOKit-4UMCBAWMNQ7HFJLY7QG4HF9Y1.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/ptrcheck-7YI46LT77DI1LAP9SC2JBEMIO.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/dnssd-8Y3X8XWUMFDVCSKGTFIK246AZ.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/_Builtin_stdatomic-2Q9EW2PVULX77UR103LGOS7Z4.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/libkern-DGUYSOJG260E5YCZU61M9YRG6.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/UserNotifications-C52ROUQK3C6RJ1AS4ZQLX1OM1.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/MachO-2CWQOI3QEDEDFZDCHBPDVNTB5.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/_Builtin_intrinsics-2G00L3FEEIB7H5VIQDNX4SLUN.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/ColorSync-7FBCK37E3EQ7XYHKPRMIKGG6Y.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/UniformTypeIdentifiers-96U38PCVH8PU17KRJDMNCE7SE.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/_Builtin_stdarg-7EM5VJJ3384CS4E9YLIIIM0HZ.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/CoreVideo-CR17GV03LE535440K7AJYIPQT.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/Spatial-3GFBO57695LL8LAB8F8T7GCG4.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/_DarwinFoundation1-F4K15TU3KC70QVIN9NHIV2AO2.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/CoreMedia-2HC7RP9JCH3TS7JH96BV6T77C.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/XPC-E37OJA9C444C2K7EUYK6WPKUY.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/_Builtin_float-DMMMZG17XTZZFSPYJHX981UL2.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/IOSurface-BV11ZY4M6ZC73PEPQCZKRHBEC.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/_Builtin_tgmath-2PG7M2Z20IBFST3N44ZDJ4TSL.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/CoreFoundation-29J0TXXAKHB04YYLC4K7BJRYB.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/_Builtin_inttypes-1YXIGV5U3R5O7M4EOA7FV87W8.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/_Builtin_stdbool-4KKT3C3Q8KGXC8L3LHC6SF503.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/ApplicationServices-AWHVX75L97CKXZWDJNFXWLO5D.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/_AvailabilityInternal-DZPMWPQTG7Y8HUKYIAYD2JDUQ.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/CoreMIDI-7XCKWW59UBSOHPAP0FPWAQCQ2.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/_Builtin_limits-D4KTKH4TGXKKREAD9OUEP7CLH.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/CoreServices-D60D0HPJVBAFZSAE1V4V02D02.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/OpenGL-5S8RCEW31BH9A6349DFM0DGAU.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/simd-9ELTUM3OTPTDBO16Y1NXHII6E.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/CoreTransferable-BOF4RNO15K95RPG82XN17JNA.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/ptrauth-78PZF8GDAK5EDY5FXJWGMAS0A.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/os_workgroup-AAVNV0BT9J25RONTZDTOPF5XX.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/CoreGraphics-BIY475904BR4BPNCZ4VR5XF37.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/SwiftUI-7HCIPIREO4V4OU5WM6XYJ3J9Q.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/CUPS-219XCV91B53UYVDLI1Z2MHUNW.pcm /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech-dependencies-1.json (in target 'FeishuSpeech' from project 'FeishuSpeech')
CompileSwift normal arm64 (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/ViewModels/MainViewModel.swift:43:41: warning: call to main actor-isolated initializer 'init()' in a synchronous nonisolated context
    init(audioRecorder: AudioRecorder = AudioRecorder()) {
                                        ^
/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/AudioRecorder.swift:53:14: note: calls to initializer 'init()' from outside of its actor context are implicitly asynchronous
    override init() {
             ^
/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/FeishuAPIService.swift:6:9: warning: 'nonisolated(unsafe)' is unnecessary for a constant with 'Sendable' type 'Logger', consider removing it
private nonisolated(unsafe) let logger = Logger(subsystem: "com.feishuspeech.app", category: "API")
        ^~~~~~~~~~~~~~~~~~~~
        
/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/FeishuAPIService.swift:205:23: warning: call to main actor-isolated instance method 'store(connection:abort:)' in a synchronous nonisolated context
            cancelBox.store(connection: connection) {
                      ^
/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/FeishuAPIService.swift:56:10: note: calls to instance method 'store(connection:abort:)' from outside of its actor context are implicitly asynchronous
    func store(connection: NWConnection, abort: @escaping () -> Void) {
         ^
/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/FeishuAPIService.swift:210:23: warning: call to main actor-isolated instance method 'cancel()' in a synchronous nonisolated context
            cancelBox.cancel()
                      ^
/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/FeishuAPIService.swift:69:10: note: calls to instance method 'cancel()' from outside of its actor context are implicitly asynchronous
    func cancel() {
         ^
/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/FeishuAPIService.swift:101:25: warning: main actor-isolated initializer 'init()' cannot be called from outside of the actor; this is an error in the Swift 6 language mode
        let cancelBox = CancelBox()
                        ^~~~~~~~~~~
                        await 
/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/FeishuAPIService.swift:348:9: warning: actor-isolated instance method 'startNetworkMonitoring()' can not be referenced from a nonisolated context; this is an error in the Swift 6 language mode
        startNetworkMonitoring()
        ^
/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/FeishuAPIService.swift:351:18: note: calls to instance method 'startNetworkMonitoring()' from outside of its actor context are implicitly asynchronous
    private func startNetworkMonitoring() {
                 ^
/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Services/LoginItemService.swift:4:9: warning: 'nonisolated(unsafe)' is unnecessary for a constant with 'Sendable' type 'Logger', consider removing it
private nonisolated(unsafe) let logger = Logger(subsystem: "com.feishuspeech.app", category: "LoginItem")
        ^~~~~~~~~~~~~~~~~~~~
        
/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/ViewModels/MainViewModel.swift:330:17: warning: reference to captured var 'self' in concurrently-executing code; this is an error in the Swift 6 language mode
                self?.handleMaxDurationReached()
                ^

SwiftDriver\ Compilation FeishuSpeech normal arm64 com.apple.xcode.tools.swift.compiler (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-Swift-Compilation -- /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -module-name FeishuSpeech -O -whole-module-optimization @/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.SwiftFileList -default-isolation\=MainActor -enable-bare-slash-regex -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature GlobalActorIsolatedTypesUsability -enable-upcoming-feature MemberImportVisibility -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-experimental-feature DebugDescriptionMacro -sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk -target arm64-apple-macos26.2 -g -module-cache-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex -Xfrontend -serialize-debugging-options -profile-coverage-mapping -profile-generate -swift-version 5 -I /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release -F /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release -emit-localized-strings -emit-localized-strings-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64 -c -num-threads 18 -Xcc -ivfsstatcache -Xcc /Users/ylpromax5/Library/Developer/Xcode/DerivedData/SDKStatCaches.noindex/macosx26.5-25F70-e082c4a02f00227109f4ed75e425c832.sdkstatcache -output-file-map /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech-OutputFileMap.json -use-frontend-parseable-output -save-temps -no-color-diagnostics -explicit-module-build -module-cache-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules -clang-scanner-module-cache-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex -sdk-module-cache-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex -serialize-diagnostics -emit-dependencies -emit-module -emit-module-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.swiftmodule -validate-clang-modules-once -clang-build-session-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/Session.modulevalidation -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/swift-overrides.hmap -emit-const-values -Xfrontend -const-gather-protocols-file -Xfrontend /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech_const_extract_protocols.json -Xcc -iquote -Xcc /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-generated-files.hmap -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-own-target-headers.hmap -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-all-target-headers.hmap -Xcc -iquote -Xcc /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-project-headers.hmap -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/include -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources-normal/arm64 -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources/arm64 -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources -emit-objc-header -emit-objc-header-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech-Swift.h -working-directory /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15 -no-emit-module-separately-wmo

LinkAssetCatalog /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Resources/Assets.xcassets (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-linkAssetCatalog --thinned /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_output/thinned --thinned-dependencies /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_dependencies_thinned --thinned-info-plist-content /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_generated_info.plist_thinned --unthinned /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_output/unthinned --unthinned-dependencies /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_dependencies_unthinned --unthinned-info-plist-content /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_generated_info.plist_unthinned --output /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/Resources --plist-output /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_generated_info.plist
note: Emplaced /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/Resources/AppIcon.icns (in target 'FeishuSpeech' from project 'FeishuSpeech')
note: Emplaced /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/Resources/Assets.car (in target 'FeishuSpeech' from project 'FeishuSpeech')

ProcessInfoPlistFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/Info.plist /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Info.plist (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-infoPlistUtility /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15/FeishuSpeech/Info.plist -producttype com.apple.product-type.application -genpkginfo /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/PkgInfo -expandbuildsettings -platform macosx -additionalcontentfile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/assetcatalog_generated_info.plist -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/Info.plist

SwiftDriverJobDiscovery normal arm64 Compiling AppDelegate.swift, FeishuSpeechApp.swift, OverlayWindowController.swift, AppSettings.swift, RecordingState.swift, SpeechResult.swift, AudioRecorder.swift, FeishuAPIService.swift, HotKeyService.swift, HotKeyState.swift, LoginItemService.swift, PermissionManager.swift, TextInputSimulator.swift, MainViewModel.swift, MenuBarView.swift, PermissionView.swift, RecordingOverlayView.swift, SettingsView.swift, GeneratedAssetSymbols.swift (in target 'FeishuSpeech' from project 'FeishuSpeech')

SwiftDriver\ Compilation\ Requirements FeishuSpeech normal arm64 com.apple.xcode.tools.swift.compiler (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-Swift-Compilation-Requirements -- /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -module-name FeishuSpeech -O -whole-module-optimization @/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.SwiftFileList -default-isolation\=MainActor -enable-bare-slash-regex -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature GlobalActorIsolatedTypesUsability -enable-upcoming-feature MemberImportVisibility -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-experimental-feature DebugDescriptionMacro -sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk -target arm64-apple-macos26.2 -g -module-cache-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex -Xfrontend -serialize-debugging-options -profile-coverage-mapping -profile-generate -swift-version 5 -I /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release -F /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release -emit-localized-strings -emit-localized-strings-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64 -c -num-threads 18 -Xcc -ivfsstatcache -Xcc /Users/ylpromax5/Library/Developer/Xcode/DerivedData/SDKStatCaches.noindex/macosx26.5-25F70-e082c4a02f00227109f4ed75e425c832.sdkstatcache -output-file-map /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech-OutputFileMap.json -use-frontend-parseable-output -save-temps -no-color-diagnostics -explicit-module-build -module-cache-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules -clang-scanner-module-cache-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex -sdk-module-cache-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex -serialize-diagnostics -emit-dependencies -emit-module -emit-module-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.swiftmodule -validate-clang-modules-once -clang-build-session-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/Session.modulevalidation -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/swift-overrides.hmap -emit-const-values -Xfrontend -const-gather-protocols-file -Xfrontend /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech_const_extract_protocols.json -Xcc -iquote -Xcc /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-generated-files.hmap -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-own-target-headers.hmap -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-all-target-headers.hmap -Xcc -iquote -Xcc /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech-project-headers.hmap -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/include -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources-normal/arm64 -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources/arm64 -Xcc -I/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources -emit-objc-header -emit-objc-header-path /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech-Swift.h -working-directory /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15 -no-emit-module-separately-wmo

SwiftMergeGeneratedHeaders /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources/FeishuSpeech-Swift.h /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech-Swift.h (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-swiftHeaderTool -arch arm64 /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech-Swift.h -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/DerivedSources/FeishuSpeech-Swift.h

Copy /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.swiftmodule/arm64-apple-macos.abi.json /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.abi.json (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -resolve-src-symlinks -rename /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.abi.json /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.swiftmodule/arm64-apple-macos.abi.json

Copy /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.swiftmodule/arm64-apple-macos.swiftdoc /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.swiftdoc (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -resolve-src-symlinks -rename /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.swiftdoc /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.swiftmodule/arm64-apple-macos.swiftdoc

Copy /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.swiftmodule/arm64-apple-macos.swiftmodule /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.swiftmodule (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -resolve-src-symlinks -rename /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.swiftmodule /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.swiftmodule/arm64-apple-macos.swiftmodule

Copy /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.swiftmodule/Project/arm64-apple-macos.swiftsourceinfo /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.swiftsourceinfo (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -resolve-src-symlinks -rename /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.swiftsourceinfo /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.swiftmodule/Project/arm64-apple-macos.swiftsourceinfo

Ld /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/MacOS/FeishuSpeech normal (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -Xlinker -reproducible -target arm64-apple-macos26.2 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk -Os -L/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/EagerLinkingTBDs/Release -L/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release -F/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/EagerLinkingTBDs/Release -F/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release -filelist /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.LinkFileList -Xlinker -rpath -Xlinker @executable_path/../Frameworks -Xlinker -object_path_lto -Xlinker /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech_lto.o -Xlinker -debug_variant -Xlinker -dependency_info -Xlinker /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech_dependency_info.dat -fobjc-link-runtime -fprofile-instr-generate -L/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx -L/usr/lib/swift -Xlinker -add_ast_path -Xlinker /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.swiftmodule @/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech-linker-args.resp -Xlinker -no_adhoc_codesign -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/MacOS/FeishuSpeech

ExtractAppIntentsMetadata (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsmetadataprocessor --toolchain-dir /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain --module-name FeishuSpeech --sdk-root /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk --xcode-version 17F42 --platform-family macOS --deployment-target 26.2 --bundle-identifier Siji.FeishuSpeech --output /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/Resources --target-triple arm64-apple-macos26.2 --binary-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/MacOS/FeishuSpeech --dependency-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech_dependency_info.dat --stringsdata-file /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/ExtractedAppShortcutsMetadata.stringsdata --source-file-list /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.SwiftFileList --metadata-file-list /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech.DependencyMetadataFileList --static-metadata-file-list /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech.DependencyStaticMetadataFileList --swift-const-vals-list /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/Objects-normal/arm64/FeishuSpeech.SwiftConstValuesFileList --compile-time-extraction --deployment-aware-processing --validate-assistant-intents --no-app-shortcuts-localization
2026-06-13 14:30:19.935 appintentsmetadataprocessor[65385:261400292] Starting appintentsmetadataprocessor export
2026-06-13 14:30:19.936 appintentsmetadataprocessor[65385:261400292] warning: Metadata extraction skipped. No AppIntents.framework dependency found.

CopySwiftLibs /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-swiftStdLibTool --copy --verbose --sign - --scan-executable /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/MacOS/FeishuSpeech --scan-folder /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/Frameworks --scan-folder /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/PlugIns --scan-folder /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/Library/SystemExtensions --scan-folder /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/Extensions --platform macosx --toolchain /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain --destination /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/Frameworks --strip-bitcode --strip-bitcode-tool /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/bitcode_strip --emit-dependency-info /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/SwiftStdLibToolInputDependencies.dep --filter-for-swift-os

GenerateDSYMFile /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app.dSYM /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/MacOS/FeishuSpeech (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/dsymutil /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app/Contents/MacOS/FeishuSpeech -o /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app.dSYM

CodeSign /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    
    Signing Identity:     "Sign to Run Locally"
    
    /usr/bin/codesign --force --sign - --entitlements /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Intermediates.noindex/FeishuSpeech.build/Release/FeishuSpeech.build/FeishuSpeech.app.xcent --timestamp\=none --generate-entitlement-der /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app

RegisterExecutionPolicyException /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-RegisterExecutionPolicyException /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app

Validate /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    builtin-validationUtility /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app -no-validate-extension -infoplist-subpath Contents/Info.plist

Touch /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /usr/bin/touch -c /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app

RegisterWithLaunchServices /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app (in target 'FeishuSpeech' from project 'FeishuSpeech')
    cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-15
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-czigaeqvlayvcybjkwtmiyihblje/Build/Products/Release/FeishuSpeech.app

** BUILD SUCCEEDED **

```

exit_code: 0

## git diff --check

```text
$ git diff --check
```

exit_code: 0

## swiftlint

```text
$ swiftlint
swiftlint: command not found
```

status: unavailable
exit_code: 127

## Summary

xcodebuild test: exit=0
xcodebuild Debug build: exit=0
xcodebuild Release build: exit=0
git diff --check: exit=0
swiftlint: unavailable exit=127
Completed: 2026-06-13T14:30:20+0800
