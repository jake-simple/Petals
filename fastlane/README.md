fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac build

```sh
[bundle exec] fastlane mac build
```

빌드만 (.pkg 생성, 업로드 없음) — 서명/내보내기 검증용

### mac release

```sh
[bundle exec] fastlane mac release
```

macOS 바이너리를 빌드해 App Store Connect에 업로드

### mac submit_review

```sh
[bundle exec] fastlane mac submit_review
```

업로드된 최신 빌드를 App Store 심사에 제출 (수동 출시)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
