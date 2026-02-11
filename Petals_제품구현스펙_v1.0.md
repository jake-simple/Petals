# Petals — 제품 구현 스펙 v1.0

## 1. 제품 개요

### 1.1 기본 정보

| 항목 | 내용 |
|------|------|
| 앱 이름 | Petals |
| 플랫폼 | macOS (네이티브 SwiftUI) |
| 최소 OS | macOS 15 Sequoia |
| 배포 | Mac App Store |
| 가격 | 유료 (일회성 구매) |
| 언어 | 한국어 / 영어 |

### 1.2 핵심 컨셉

Petals는 **1년 전체를 한 화면에 보여주는 연간 캘린더 앱**이다. EventKit 캘린더 연동 위에 **자유 배치 캔버스**를 결합하여, 사용자가 이미지·텍스트·스티커·도형을 자유롭게 올려 나만의 비주얼 연간 달력을 만들 수 있다.

### 1.3 설계 원칙

- **한 화면, 1년 전체**: 스크롤 없음. 줌 없음. 윈도우 크기 = 1년 전체.
- **캘린더 + 캔버스**: EventKit 데이터가 토대, 그 위에 자유 꾸미기 레이어.
- **네이티브**: SwiftUI 기반. macOS 시스템 통합. 빠른 반응.
- **심플한 데이터**: 모델 2개. EventKit 데이터는 복제하지 않음.

### 1.4 타겟 사용자

- 여러 프로젝트를 관리하며 연간 조감이 필요한 전문가
- 다이어리 꾸미기를 좋아하는 비주얼 플래너 사용자
- 마감과 일정을 한눈에 보고 싶은 프리랜서/크리에이터
- 기능적이면서 예쁜 연간 달력을 원하는 모든 사람

---

## 2. 기능 명세

### 2.1 연간 그리드 뷰

#### 레이아웃

- 전체 화면 적응형 그리드: 세로 12행(월) × 가로 31열(일)
- 윈도우 리사이즈 시 셀 크기 동적 재계산
- 왼쪽 축에 월 라벨, 각 셀에 날짜 숫자 표시
- 각 날짜에 요일 표시 (월, 화, 수 등)
- 존재하지 않는 날짜(2월 30일, 4월 31일 등)는 비활성 셀로 처리
- 주말 셀은 테마에 따라 배경색 강조 (선택적)

#### 셀 크기 계산

```swift
let cellWidth  = availableWidth  / 31.0   // 가로: 31열
let cellHeight = availableHeight / 12.0   // 세로: 12행
```

GeometryReader로 사용 가능 영역을 잡고, 모든 하위 뷰가 계산된 셀 크기를 참조한다.

#### 오늘 라인

- 오늘 날짜 위치에 세로선 표시 (전체 월에 걸쳐)
- 색상은 활성 테마에서 정의
- 항상 표시 (비활성화 불가, 핵심 기능)

#### 연도 네비게이션

- 툴바 또는 키보드 단축키로 이전/다음 연도 이동
- 현재 표시 연도를 앱 상단에 표시

### 2.2 EventKit 연동

#### 캘린더 접근

- 첫 실행 시 EventKit 권한 요청
- 사용자의 모든 캘린더 로드 (iCloud, Google, Exchange 등)
- 캘린더 필터 패널: 캘린더별 표시/숨김 토글
- EventKit에서 제공하는 캘린더 색상 그대로 사용

#### 이벤트 표시

- 여러 날에 걸친 이벤트는 날짜 범위에 걸치는 가로 컬러 바로 표시
- 하루짜리 이벤트는 숨김 옵션 제공 (사용자 설정)
- 이벤트 텍스트 크기 조절 가능 (사용자 설정)
- 셀당 최대 이벤트 행 수 조절 가능 (초과 시 "+N" 배지로 표시)
- 이벤트 텍스트 난독화 옵션 (스크린샷/발표용)

#### 이벤트 CRUD

- **생성**: 날짜 셀을 드래그하여 기간 지정 → 이벤트 편집 시트 열림
- **조회**: 이벤트 바 클릭 → 팝오버로 상세 정보 표시
- **수정**: 팝오버에서 제목, 날짜, 캘린더, 메모 편집
- **삭제**: 팝오버에서 삭제 버튼. 확인 필수.
- **반복 이벤트**: "이 이벤트만 / 이후 모든 이벤트 / 전체" 수정 범위 지원

### 2.3 캔버스 꾸미기 시스템

#### 개요

캔버스는 캘린더 그리드 위에 놓이는 투명 레이어다. 사용자는 캘린더 위 아무 곳에나 장식 요소를 배치하고, 이동하고, 크기를 조절하고, 회전시킬 수 있다.

#### 캔버스 아이템 타입

| 타입 | 설명 | 속성 |
|------|------|------|
| 이미지 (image) | 파일 시스템에서 가져온 사진, 로고, 일러스트 | 이미지 데이터, 썸네일 |
| 텍스트 (text) | 자유 배치 라벨, 메모, 목표, 인용구 | 내용, 폰트, 크기, 색상, 정렬, 볼드/이탤릭 |
| 스티커 (sticker) | 앱 내장 장식 요소, SF Symbol, 이모지 | 스티커 식별자 (에셋명 또는 SF Symbol) |
| 도형 (shape) | 원, 사각형, 선 등 하이라이트용 | 도형 타입, 채우기 색상, 테두리 색상/두께 |

#### 캔버스 인터랙션

- **추가**: 툴바 버튼 또는 우클릭 컨텍스트 메뉴. 이미지는 파일 선택기 또는 Finder에서 드래그 앤 드롭.
- **선택**: 아이템 클릭 → 선택 핸들 표시
- **이동**: 선택된 아이템 드래그
- **크기 조절**: 모서리/변 핸들 드래그. Shift 키로 비율 고정.
- **회전**: 회전 핸들 또는 인스펙터 패널에서 정밀 입력
- **삭제**: Delete/Backspace 키 또는 컨텍스트 메뉴
- **Z 순서**: 우클릭 → 맨 앞으로 / 맨 뒤로
- **불투명도**: 인스펙터에서 아이템별 조절

#### 좌표 시스템

모든 캔버스 아이템 위치는 **비율 좌표(0.0~1.0)**로 저장한다. 캘린더 콘텐츠 영역 기준 상대 좌표이므로, 윈도우 리사이즈 시에도 아이템이 동일한 시각적 위치를 유지한다.

### 2.4 테마 시스템

#### 내장 테마

앱에 여러 프리셋 테마를 내장하여 캘린더 그리드, 라벨, 강조색의 시각적 외관을 제어한다.

| 테마 요소 | 설명 |
|-----------|------|
| 배경색 | 캘린더 전체 배경 |
| 그리드 선 색상 | 셀 경계선 |
| 오늘 라인 색상 | 세로 오늘 표시선 |
| 월/일 라벨 색상 | 축 텍스트 색상 |
| 주말 강조색 | 주말 셀 배경 틴트 (선택적) |
| 폰트 | 라벨용 커스텀 폰트 (선택적) |

#### 테마 예시

- **Minimal Light** — 흰 배경, 얇은 회색 선, 오렌지 오늘 라인
- **Dark Mode** — 어두운 배경, 은은한 그리드, 밝은 강조색
- **Pastel** — 부드러운 파스텔 배경, 둥근 느낌
- **Classic** — 종이 질감, 세리프 폰트
- **Monochrome** — 순수 흑백, 높은 대비

#### 향후 고려

커스텀 테마 생성 (사용자 정의 색상/폰트)은 향후 버전에서 프리미엄 기능 또는 인앱 구매로 추가할 수 있다.

### 2.5 설정

| 설정 | 타입 | 기본값 | 저장소 |
|------|------|--------|--------|
| 선택된 캘린더 | 다중 선택 | 전체 | UserDefaults |
| 오늘 라인 표시 | 토글 | 켜짐 | UserDefaults |
| 이벤트 텍스트 크기 | 슬라이더 (8-14pt) | 10pt | UserDefaults |
| 최대 이벤트 행 수 | 스테퍼 (1-10) | 7 | UserDefaults |
| 하루짜리 이벤트 숨김 | 토글 | 꺼짐 | UserDefaults |
| 이벤트 텍스트 난독화 | 토글 | 꺼짐 | UserDefaults |
| 활성 테마 | 선택 | Minimal Light | YearDocument |

### 2.6 키보드 단축키

| 단축키 | 동작 |
|--------|------|
| ⌘ + N | 새 이벤트 (편집기 열기) |
| ⌘ + T | 오늘로 이동 |
| ⌘ + ← / ⌘ + → | 이전 / 다음 연도 |
| Delete / Backspace | 선택된 캔버스 아이템 삭제 |
| ⌘ + C / ⌘ + V | 캔버스 아이템 복사 / 붙여넣기 |
| ⌘ + Z / ⌘ + ⇧ + Z | 실행 취소 / 다시 실행 (캔버스 작업) |
| ⌘ + ] / ⌘ + [ | 앞으로 보내기 / 뒤로 보내기 |
| ⌘ + , | 설정 열기 |

---

## 3. 데이터 아키텍처

### 3.1 설계 원칙

- **EventKit 데이터는 절대 복제하지 않는다.** EventKit에서 읽고, EventKit API로 쓴다.
- **앱이 소유하는 데이터는 캔버스 꾸미기 정보뿐이다.**
- **CloudKit 동기화는 SwiftData를 통해 자동 처리한다.**
- **이미지는 파일로 분리 저장한다.** SwiftData에는 썸네일만, 원본은 iCloud 컨테이너 디렉토리에 저장.

### 3.2 데이터 모델 (SwiftData)

#### YearDocument

```swift
@Model
final class YearDocument {
    var year: Int
    var theme: String                        // 테마 프리셋 ID
    @Relationship(deleteRule: .cascade)
    var canvasItems: [CanvasItem]
    var createdAt: Date
    var modifiedAt: Date
}
```

#### CanvasItem

```swift
@Model
final class CanvasItem {
    // 공통
    var type: String                         // CanvasItemType rawValue
    var relativeX: Double                    // 0.0 ~ 1.0
    var relativeY: Double                    // 0.0 ~ 1.0
    var relativeWidth: Double
    var relativeHeight: Double
    var rotation: Double
    var zIndex: Int
    var opacity: Double
    var createdAt: Date

    // 이미지
    var imageFileName: String?               // UUID.jpg 파일 참조
    var thumbnailData: Data?                 // < 100KB (CloudKit 제한 대응)

    // 텍스트
    var text: String?
    var fontSize: Double?
    var fontName: String?
    var textColor: String?                   // hex
    var textAlignment: String?
    var isBold: Bool?
    var isItalic: Bool?

    // 스티커
    var stickerName: String?                 // 번들 에셋 또는 SF Symbol

    // 도형
    var shapeType: String?                   // "circle", "rectangle", "line"
    var fillColor: String?                   // hex
    var strokeColor: String?                 // hex
    var strokeWidth: Double?

    var yearDocument: YearDocument?
}
```

#### CanvasItemType

```swift
enum CanvasItemType: String, Codable {
    case image
    case text
    case sticker
    case shape
}
```

### 3.3 테마 정의 (앱 번들 프리셋)

```swift
struct Theme: Codable, Identifiable {
    var id: String
    var name: String
    var backgroundColor: String              // hex
    var gridLineColor: String
    var todayLineColor: String
    var monthLabelColor: String
    var dayLabelColor: String
    var weekendColor: String?                // hex, 선택적
    var fontName: String?                    // 선택적
}
```

테마는 SwiftData에 저장하지 않는다. 앱 번들에 JSON 프리셋으로 내장하고, 사용자가 선택한 테마 ID만 `YearDocument.theme`에 저장한다.

### 3.4 사용자 설정 (UserDefaults)

```swift
@AppStorage("selectedCalendarIDs") var selectedCalendarIDs: String  // 쉼표 구분
@AppStorage("showTodayLine") var showTodayLine: Bool = true
@AppStorage("eventTextSize") var eventTextSize: Double = 10
@AppStorage("maxEventRows") var maxEventRows: Int = 7
@AppStorage("hideSingleDayEvents") var hideSingleDayEvents: Bool = false
@AppStorage("obfuscateEventText") var obfuscateEventText: Bool = false
```

### 3.5 이미지 저장 전략

이미지를 SwiftData 모델에 직접 넣으면 CloudKit 레코드당 1MB 제한에 걸린다. 이를 피하기 위해 이미지를 파일로 분리한다.

| 계층 | 저장소 | 동기화 방식 | 크기 제한 |
|------|--------|-------------|-----------|
| 썸네일 | SwiftData (thumbnailData) | CloudKit 자동 | < 100KB |
| 원본 이미지 | 앱 iCloud 컨테이너 디렉토리 | iCloud Drive 자동 | 실용적: < 5MB |
| 메타데이터 | SwiftData (imageFileName) | CloudKit 자동 | 문자열만 |

#### 이미지 저장 흐름

1. 사용자가 Finder 또는 파일 선택기에서 이미지 추가
2. 앱이 이미지를 최대 2048px (긴 변 기준)로 리사이즈
3. 썸네일 생성 (최대 200px, JPEG 품질 0.6)
4. 원본 이미지 저장: `~/Library/Containers/[앱]/Data/Documents/Images/[uuid].jpg`
5. 썸네일은 `CanvasItem.thumbnailData`에 저장
6. 파일명은 `CanvasItem.imageFileName`에 저장

#### 이미지 로드 흐름 (다른 기기에서)

1. SwiftData가 `CanvasItem`을 `imageFileName`, `thumbnailData`와 함께 동기화
2. 앱이 iCloud 컨테이너에서 원본 이미지 로드 시도
3. 아직 다운로드되지 않은 경우: 썸네일 먼저 표시, 다운로드 요청
4. 다운로드 완료 후: 원본으로 교체

### 3.6 데이터 흐름도

```
UserDefaults                EventKit (외부)
  - 필터 설정                  - EKEvent[]
  - 표시 옵션                  - EKCalendar[]
       │                          │
       ▼                          ▼
  ┌──────────── 화면 렌더링 ────────────┐
  │  YearDocument (SwiftData + CloudKit) │
  │   ├── theme ──→ Theme 프리셋 참조    │
  │   └── canvasItems[] ──→ 꾸미기 요소  │
  └──────────────────────────────────────┘
                    │
         CloudKit 동기화 (자동)
         iCloud Drive (이미지 파일)
```

---

## 4. UI 아키텍처

### 4.1 윈도우 구조

```
+-----------------------------------------------------------+
| 툴바: [< 2026 >]  [오늘]  [+이벤트]  [+꾸미기]  [설정]      |
+-------+---------------------------------------------------+
|       |  1   2   3   4   5   6  ...  28  29  30  31       |
|  1월  | [  ][  ][  ][  ][  ][  ]...  [  ][  ][  ][  ]     |
|  2월  | [  ][이벤트 바          ][  ]...  [  ][  ]         |
|  3월  | [  ][  ][  ][  ][  ][  ]...  [  ][  ][  ][  ]     |
|  ...  |  ... 캘린더 그리드 + 이벤트 + 캔버스 아이템 ...      |
| 11월  | [  ][  ][  ][  ][  ][  ]...  [  ][  ][  ][  ]     |
| 12월  | [  ][  ][  ][  ][  ][  ]...  [  ][  ][  ][  ]     |
+-------+---------------------------------------------------+
```

### 4.2 뷰 레이어 (ZStack 순서)

| Z 순서 | 레이어 | 설명 |
|--------|--------|------|
| 0 (맨 아래) | 배경 | 테마 배경색/패턴 |
| 1 | 그리드 | 월/일 라벨, 셀 경계선, 주말 강조 |
| 2 | 오늘 라인 | 오늘 날짜의 세로선 |
| 3 | 이벤트 바 | EventKit 이벤트를 컬러 가로 바로 렌더링 |
| 4 | 캔버스 아이템 | 사용자가 배치한 이미지, 텍스트, 스티커, 도형 |
| 5 (맨 위) | 인터랙션 레이어 | 드래그 핸들, 선택 표시, 드래그 프리뷰 |

### 4.3 주요 UI 컴포넌트

| 컴포넌트 | 구현 방식 | 비고 |
|----------|-----------|------|
| CalendarGridView | Canvas (SwiftUI) 또는 커스텀 NSView | 성능 핵심. 그리드 선과 라벨 그리기 |
| EventBarView | 그리드 위 포지셔닝된 오버레이 | EKCalendar 색상 사용. 텍스트 바 너비에 맞춰 클리핑 |
| CanvasItemView | 드래그/리사이즈 가능한 오버레이 | CanvasItemType에 따라 다른 렌더링 |
| SelectionHandles | 모서리/변 드래그 핸들 | 선택된 캔버스 아이템에 표시 |
| InspectorPanel | 사이드바 또는 팝오버 | 선택된 캔버스 아이템 속성 편집 |
| EventEditorSheet | 모달 시트 | EventKit으로 EKEvent 생성/편집 |
| CalendarFilterView | 툴바에서 팝오버 | 색상 표시와 함께 캘린더별 토글 |
| ThemePickerView | 설정 또는 팝오버 | 사용 가능한 테마 프리뷰 그리드 |

---

## 5. 기술 요구사항

### 5.1 기술 스택

| 기술 | 용도 |
|------|------|
| Swift 5.9+ | 주 언어 |
| SwiftUI | UI 프레임워크 (주 사용) |
| AppKit (NSView) | 성능 핵심 그리드 렌더링에 필요 시 사용 |
| SwiftData | 캔버스 데이터 영속 저장 |
| CloudKit | 기기 간 동기화 (SwiftData 연동) |
| EventKit | 캘린더 이벤트 접근 및 조작 |
| Core Image / vImage | 이미지 리사이즈 및 썸네일 생성 |
| UniformTypeIdentifiers | 드래그 앤 드롭 파일 타입 처리 |

### 5.2 성능 요구사항

- 앱 실행 → 전체 캘린더 렌더링: 1초 이내
- 윈도우 리사이즈: 60fps로 그리드 재그리기, 눈에 띄는 랙 없음
- EventKit 연간 쿼리: 초기 로드 후 캐싱, 알림 시 갱신
- 캔버스 아이템 50개 이상: 부드러운 드래그 및 렌더링
- 이미지 썸네일: 백그라운드 생성, UI 블로킹 없음
- 메모리 사용량: 일반적인 캘린더 + 이미지 20장 기준 200MB 이하

### 5.3 성능 최적화 전략

- **지연 렌더링**: 화면에 보이는 이벤트 바와 캔버스 아이템만 렌더링
- **그리드 드로잉**: 수백 개의 개별 SwiftUI 뷰 대신 Canvas(SwiftUI 2D 드로잉) 또는 NSView.draw() 사용
- **이미지 관리**: 기본적으로 썸네일 표시. 내보내기 시에만 원본 해상도 로드
- **EventKit 캐싱**: 메모리에 캐시. EKEventStoreChangedNotification 수신 시 갱신

### 5.4 샌드박스 및 Entitlements

| Entitlement | 사유 |
|-------------|------|
| com.apple.security.personal-information.calendars | EventKit 접근 |
| com.apple.security.files.user-selected.read-write | Finder에서 이미지 가져오기 |
| com.apple.developer.icloud-container-identifiers | CloudKit 동기화 |
| com.apple.developer.icloud-services | CloudKit + iCloud Drive |

---

## 6. 개발 로드맵

### Phase 1: 기반 구축 (1~2주차)

- 프로젝트 셋업: SwiftUI 앱, SwiftData 모델, CloudKit 컨테이너
- 캘린더 그리드 렌더링 (적응형 레이아웃, 월/일 라벨)
- 오늘 라인
- 연도 네비게이션 (이전/다음 연도)
- 기본 테마 시스템 (2~3개 내장 테마)

### Phase 2: EventKit 연동 (3~4주차)

- EventKit 권한 요청 및 캘린더 로딩
- 이벤트 바 그리드 위 렌더링
- 캘린더 필터 패널
- 이벤트 상세 팝오버 (조회)
- 드래그로 이벤트 생성
- 이벤트 수정 및 삭제

### Phase 3: 캔버스 시스템 (5~7주차)

- 캔버스 아이템 모델 및 렌더링
- 이미지 배치 (파일 선택기 + Finder 드래그 앤 드롭)
- 텍스트 아이템 생성 및 편집
- 스티커/도형 아이템 지원
- 선택, 이동, 크기 조절, 회전 인터랙션
- Z 순서 및 불투명도 제어
- 실행 취소/다시 실행 지원

### Phase 4: 마무리 및 출시 (8~10주차)

- CloudKit 동기화 테스트 (여러 기기)
- 이미지 동기화 흐름 (썸네일 폴백)
- 테마 세트 완성 (5개 이상)
- 키보드 단축키
- 설정 패널
- 앱 아이콘 및 마케팅 에셋
- Mac App Store 제출

### 향후 버전 고려

- 커스텀 테마 생성기
- 캘린더를 이미지/PDF로 내보내기
- macOS 위젯 (현재 월 미니 뷰)
- 스티커 팩 인앱 구매
- 프린트 지원

---

## 7. 리스크 및 대응

| 리스크 | 영향도 | 대응 방안 |
|--------|--------|-----------|
| 많은 이벤트로 인한 그리드 성능 저하 | 높음 | 개별 SwiftUI 뷰 대신 Canvas/NSView 드로잉 사용. 보이는 이벤트 행 수 제한. |
| CloudKit 이미지 동기화 지연 | 중간 | 썸네일 우선 표시. 백그라운드 다운로드. 진행 표시. |
| EventKit 권한 거부 | 높음 | 그레이스풀 디그레이데이션: 캔버스만 사용 가능한 빈 그리드 표시. 명확한 권한 요청 UI. |
| 큰 이미지 파일로 인한 저장 공간 증가 | 중간 | 최대 2048px로 자동 리사이즈. 매우 큰 파일에 경고. 저장 사용량 표시. |
| 드래그 인터랙션 충돌 (이벤트 vs 캔버스) | 중간 | 캔버스 편집 모드 토글, 또는 문맥 인식: 그리드에서 드래그 = 이벤트, 아이템에서 드래그 = 이동. |
| SwiftData + CloudKit 스키마 마이그레이션 | 낮음 | 경량 마이그레이션. v1.0 출시 전 스키마를 신중하게 설계. |

---

## 8. 부록

### 8.1 경쟁 환경

| 앱 | 플랫폼 | 강점 | Petals가 채우는 빈 틈 |
|----|--------|------|---------------------|
| Linear Calendar | Mac | 깔끔한 연간 뷰 | 꾸미기/캔버스 기능 없음 |
| Fantastical | Mac/iOS | 강력한 캘린더 기능 | 연간 리니어 뷰 없음 |
| Apple Calendar | Mac/iOS | 시스템 통합 | 연간 조감 뷰 없음 |
| Notion Calendar | Web/Mac | 프로젝트 연동 | 비주얼 꾸미기 없음 |
| Miro / FigJam | Web | 캔버스 자유도 | 캘린더가 아님 |

### 8.2 App Store 포지셔닝

- **주 카테고리**: 생산성
- **보조 카테고리**: 라이프스타일
- **키워드**: annual calendar, year planner, year view, calendar decoration, visual planner, timeline, yearly overview, macOS calendar, petals planner, 연간 달력, 연간 플래너

### 8.3 용어 정리

| 용어 | 정의 |
|------|------|
| 캔버스 아이템 | 사용자가 배치한 모든 장식 요소 (이미지, 텍스트, 스티커, 도형) |
| YearDocument | 한 해의 캔버스 상태를 나타내는 루트 데이터 객체 |
| 비율 좌표 | 캘린더 콘텐츠 영역 기준 0.0~1.0 위치값 |
| 이벤트 바 | EventKit 이벤트의 날짜 범위를 나타내는 가로 컬러 바 |
| 오늘 라인 | 오늘 날짜를 전체 월에 걸쳐 표시하는 세로 표시선 |
| 테마 | 캘린더의 시각적 스타일을 정의하는 색상·폰트 프리셋 |
