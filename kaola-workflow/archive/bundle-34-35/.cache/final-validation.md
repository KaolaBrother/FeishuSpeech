verdict: pass
validation_command: swiftlint lint --quiet; /tmp/bound-dns-validate; xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Release -destination generic/platform=macOS -derivedDataPath /tmp/feishuspeech-bundle-34-36-release14 CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=D5KY7PZC5N CODE_SIGN_IDENTITY='Apple Development: Yanlei Chen (C2D65N458L)' CURRENT_PROJECT_VERSION=14 build
validated_candidate_hash: 3c47d294d3eb48646e559913253975524d81c9e1d548fe961f7e468d3d4a9226
