# Petals 코드 점검 — 2026-11-03

대상: `/Users/jmlee/ones/Petals`. 시작 시 작업 트리는 깨끗했다.
앱의 SwiftUI 화면, EventKit 연동, SwiftData 모델, 이미지·클립보드 처리, Xcode 설정을 검토했다.

## 수정

- EventKit 변경 알림을 화면 재조회에 연결하고, 생성·수정·삭제 성공 시 캐시를 무효화했다. 취소되거나 더 오래된 비동기 조회가 최신 결과를 덮어쓰지 않도록 요청 세대를 확인한다.
- 날짜 조회와 ‘이날의 기록’에서 빈 캘린더 선택을 전체 조회로 해석하지 않는다. 윤년이 아닌 해의 2월 29일이 3월 1일로 정규화되는 조회도 제외했다.
- 종일 일정 편집은 사용자에게 마지막 포함 날짜를 보여주고 다음 날 0시를 종료 경계로 저장한다. 일정 배치는 종료 시각을 제외하며, 자정·월말·연말에 하루가 더 표시되지 않는다. 역전된 기간은 저장 전에 검증한다.
- 실제 날짜가 없는 연간 셀, 표시 범위 밖의 셀, 크기가 0인 레이아웃을 클릭 대상으로 삼지 않는다.
- 배치에서 생략한 일정의 전체 날짜에 숨김 개수를 표시하고, 높이 부족으로 그리지 않은 일정은 클릭 대상으로 삼지 않는다. 반복 일정의 세그먼트 식별자에 시작 시각을 포함한다.
- 복사·붙여넣기·삭제·스크롤을 해당 창으로 제한하고 텍스트 편집 중 복사·붙여넣기는 AppKit responder chain으로 전달한다.
- 복사한 아이템의 고정 비율과 실제 표시 크기, 캘린더에서 보드로 복사할 때 그룹 위치를 유지한다. 이미지 파일 복제 실패 시 원본 파일을 공동 참조하는 복제본을 만들지 않는다.
- 취소된 이미지 로딩 결과가 새 이미지 표시를 덮어쓰지 않는다. 썸네일 생성 후 원본을 atomic write하며, 이미지 가져오기 중 연도·페이지를 이동해도 처음 선택한 위치에 추가한다.

## 재실행

```sh
./scripts/test-regressions.sh
xcodebuild -project Petals/Petals.xcodeproj -scheme Petals -configuration Debug -derivedDataPath /tmp/petals-review-build CODE_SIGNING_ALLOWED=NO SDK_STAT_CACHE_ENABLE=NO build
xcodebuild -project Petals/Petals.xcodeproj -scheme Petals -configuration Release -derivedDataPath /tmp/petals-review-build CODE_SIGNING_ALLOWED=NO SDK_STAT_CACHE_ENABLE=NO build
```

회귀 실행기는 실제 소스 파일을 컴파일한다. EventKit 테스트 객체는 저장하지 않으며 SwiftData는 메모리 저장소만 사용한다. AppKit 입력 범위 검증은 표시하지 않은 두 윈도우와 합성 이벤트로 수행한다.

## 결과

- 최종 Debug / Release 빌드 모두 성공(Xcode 27.0, 코드 서명 제외).
- 서울·LA·UTC에서 각각 514개 회귀 assertion 통과. 서머타임 전환일 포함.
- 별도 앱 식별자 `com.onessa.Petals.ReviewSmoke`와 메모리 저장소로 캘린더·화이트보드 데모 모드를 각각 8초 실행해 조기 종료가 없음을 확인. 화면 시각 검사 또는 전체 UI 조작 검증은 아니다.
- `git diff --check`, 프로젝트 plist, 번역 JSON, 테스트 셸 문법 검사 통과.
- 남은 빌드 경고는 AppIntents 의존성이 없어 메타데이터 추출을 생략한다는 도구 안내 1건이다.
- 최초 제한 환경 빌드의 Swift 매크로 플러그인 실패는 제한 밖 실행으로 해소했고, SDK stat 캐시 생성 정지는 검증 명령에 `SDK_STAT_CACHE_ENABLE=NO`를 지정해 우회했다. 프로젝트 설정은 변경하지 않았다.

## 검증 한계

- 빌드는 코드 서명 없이 수행한다. App Store 업로드·배포 검증을 의미하지 않는다.
- 실제 캘린더 계정에서의 권한 변경·수정 알림·동기화 및 CloudKit/iCloud Drive의 기기 간 동기화는 검증하지 않았다.
- AppKit 입력 라우팅 검증과 실제 사람이 여러 창·시트·텍스트 필드를 조작하는 UI 검증은 다르다. 전체 UI 자동화 테스트는 추가하지 않았다.
- 이미지 원본 파일이 이미 없거나 iCloud에서 아직 다운로드되지 않은 경우 복제는 생략된다. 새 복제본이 원본 파일 삭제에 종속되는 문제는 방지했으나 자동 다운로드 재시도와 사용자 오류 표시는 별도 개선 여지가 있다.
- 실행 취소/다시 실행의 전체 지원이나 저장 계층 구조 변경은 포함하지 않았다.

## 확인한 공식 문서

- [EKEventStoreChangedNotification](https://developer.apple.com/documentation/eventkit/ekeventstorechangednotification): 변경 시 기존 이벤트 객체를 다시 조회해야 한다.
- [predicateForEvents](https://developer.apple.com/documentation/eventkit/ekeventstore/predicateforevents(withstart:end:calendars:)): calendars에 nil을 넘기면 전체 캘린더를 조회한다.
- [NSEvent.locationInWindow](https://developer.apple.com/documentation/appkit/nsevent/locationinwindow): 윈도우 좌표를 뷰 좌표로 변환해 입력 범위를 판단한다.
