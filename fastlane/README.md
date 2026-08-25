# Fastlane

Xcode Cloud가 macOS 바이너리를 App Store Connect에 업로드한다. 이 디렉터리의
Fastlane lane은 GitHub Actions에서 릴리즈 노트를 반영하고 검증된 빌드를 심사에
제출할 때만 사용한다.

```sh
bundle exec fastlane mac prepare_review version:1.1.0 build_number:10
bundle exec fastlane mac submit_review version:1.1.0 build_number:10 confirm:true
```

로컬에서 앱을 빌드·서명·업로드하는 lane은 제공하지 않는다.
