# Xcode Cloud 배포 구성

Petals의 바이너리 배포는 Xcode Cloud가 담당한다. Fastlane은 GitHub Actions에서
릴리즈 노트와 심사 요청에만 사용하며, 로컬에서 빌드·서명·업로드하지 않는다.

## Xcode Cloud 설정

- 저장소: `jake-simple/Petals`
- 프로젝트: `Petals/Petals.xcodeproj`
- 스킴: `Petals`
- 배포 대상: macOS, App Store Connect
- 시작 조건: `v<마케팅 버전>` 태그 푸시 (예: `v1.1.0`)

Archive는 Release 구성으로 App Store Connect에만 업로드한다. Xcode Cloud가 빌드
번호를 자동으로 증가시키므로 저장소에서 `CFBundleVersion`을 계산하거나 수정하지
않는다. Xcode Cloud의 post-action은 사용하지 않으며, TestFlight 테스터 그룹
배포는 GitHub Actions가 담당한다.

## 태그 기반 릴리즈 절차

`v<마케팅 버전>` 태그를 원격에 푸시하면 그 태그가 가리키는 커밋으로 Xcode Cloud가
자동 빌드를 시작한다. `main` 푸시만으로는 이 워크플로가 시작되지 않는다.

1. 마케팅 버전과 릴리즈 노트를 확정하고 `docs/deployments/<version>.md`를 만든다.
2. 릴리즈 커밋을 `main`에 푸시한다.
3. 해당 커밋에 주석 태그를 붙여 원격에 푸시한다. 예를 들어 `1.1.0` 릴리즈는 다음과
   같이 시작한다.

   ```sh
   git push origin main
   git tag -a v1.1.0 -m "Release 1.1.0"
   git push origin v1.1.0
   ```

4. Xcode Cloud Archive가 성공하고 `Await App Store Build`가 `VALID` 및
   `APP_STORE_ELIGIBLE` 빌드를 확인할 때까지 기다린다.
5. 같은 워크플로가 그 빌드를 TestFlight 내부 테스터 그룹에 배포한다.
6. 별도 승인 시에만 GitHub Actions의 `Submit App Store Review`를 실행하여 같은
   버전과 `confirm`을 입력한다. 태그 푸시는 심사 제출이나 자동 출시를 수행하지
   않는다.

## 운영 기준

- Xcode Cloud가 macOS 바이너리 생성 및 App Store Connect 업로드를 담당한다.
- Fastlane은 GitHub Actions에서 릴리즈 노트와 심사 제출에만 사용한다. 로컬에서는
  실행하지 않으며, 바이너리를 빌드·서명·업로드하지 않는다.
- TestFlight 내부 테스터 배포는 `Await App Store Build`가 자동으로 수행한다.
  외부 그룹은 Apple 베타 앱 심사를 거쳐야 하므로 자동 배포하지 않는다.
- 릴리즈 태그 형식은 `v<마케팅 버전>`으로 고정한다. 예: `v1.1.0`.
  이 저장소에는 릴리즈 목적이 아닌 태그를 푸시하지 않는다.
- 버전별 준비 상태와 배포 결과는 `docs/deployments/<version>.md`에 기록한다.
  기록 항목과 템플릿은 [`deployments/README.md`](deployments/README.md)를 따른다.

## 릴리즈 노트와 심사 제출

릴리즈 노트 원본은 `fastlane/metadata/<언어>/release_notes.txt`다. 2개 언어
(`en-US`, `ko`)를 태그 생성 전에 갱신한다. `Submit App Store Review`는 해당
태그를 checkout하므로 릴리즈 노트는 배포 소스와 항상 일치한다.

두 GitHub Actions 워크플로는 저장소 secret `APP_STORE_CONNECT_API_KEY_P8`를
사용한다. API 키 파일은 runner의 임시 경로에만 생성하며, `match`, 인증서 저장소,
로컬 Fastlane 실행은 사용하지 않는다. 승인 후 출시는 계속 수동이다.

심사 요청을 취소한 편집 버전은 다음 릴리즈 버전으로 전환해 기존 메타데이터를
보존한다. 심사 중이거나 출시된 버전은 전환하지 않고 제출을 중단한다.
