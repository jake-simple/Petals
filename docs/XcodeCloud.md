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
번호를 자동으로 증가시키며, TestFlight 내부 배포와 post-action 심사 요청은 쓰지
않는다.

## 릴리즈 절차

1. 두 언어의 `release_notes.txt`를 갱신한다.
2. 원격에 릴리즈 커밋과 `v<버전>` 태그를 푸시한다.
3. Xcode Cloud Archive와 `Await App Store Build`가 `VALID` 및
   `APP_STORE_ELIGIBLE` 빌드를 확인할 때까지 기다린다.
4. GitHub Actions의 `Submit App Store Review`를 수동 실행하여 같은 버전과
   `confirm`을 입력한다. 승인 후 출시는 수동이다.

두 GitHub Actions 워크플로는 저장소 secret
`APP_STORE_CONNECT_API_KEY_P8`를 사용한다. API 키 파일은 runner의 임시 경로에만
생성한다.

심사 요청을 취소한 편집 버전은 다음 릴리즈 버전으로 전환해 기존 메타데이터를
보존한다. 심사 중이거나 출시된 버전은 전환하지 않고 제출을 중단한다.
