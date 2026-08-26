# 릴리즈 기록

각 App Store 배포는 `v<마케팅 버전>` 태그를 원격에 푸시하기 전에 이 디렉터리에
`<버전>.md` 기록 파일을 추가한다. 예: `1.1.0.md`.

릴리즈 노트 원본은 `fastlane/metadata/<언어>/release_notes.txt`다. 기록 파일에는
태그 커밋의 릴리즈 노트 내용을 함께 보존한다. GitHub Actions는 이 태그를
checkout하여 같은 원본을 App Store Connect에 올리고 원격 값을 다시 확인한다.

## 템플릿

```md
# 1.1.0

## 배포 정보

| 항목 | 값 |
| --- | --- |
| 배포 대상 | macOS App Store |
| 기준일 | YYYY-MM-DD |
| 릴리즈 소스 | `<commit SHA>` |
| 릴리즈 태그 | `v1.1.0` |
| Xcode Cloud 워크플로 | `App Store Distribution` |
| 바이너리 배포 방식 | Xcode Cloud Archive → App Store Connect |

## 릴리즈 노트

| 언어 | 내용 |
| --- | --- |
| 한국어 | ... |
| English | ... |

## 검증과 배포

- [ ] 릴리즈 커밋을 `main`에 푸시
- [ ] 주석 태그를 원격에 푸시
- [ ] Xcode Cloud Archive 성공
- [ ] App Store Connect 빌드 `VALID` 및 `APP_STORE_ELIGIBLE` 확인
- [ ] 내부 TestFlight 그룹 배포 확인
- [ ] 릴리즈 노트 원격 검증
- [ ] 심사 제출 승인 및 결과 확인 (별도 승인 시)
```

태그 푸시와 심사 제출은 별도 승인 절차다.
