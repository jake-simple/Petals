# 캘린더 상단 영역 접기/펼치기 토글

## 목적
캘린더 위쪽의 꾸밈(화이트보드) 여백 영역을 토글 버튼으로 접고 펼칠 수 있게 한다.
접으면 캘린더가 위로 확장되어 더 넓게 보인다.

> 참고: 처음엔 펼침↔접힘에 `easeInOut` 애니메이션을 넣었으나, 캘린더가 명령형 `Canvas`
> 레이어(그리드+이벤트바)로 그려져 프레임마다 크기가 바뀌면 재그리기가 SwiftUI 컨테이너
> 애니메이션과 desync되어 격자가 "출렁이는" 현상이 발생. 이를 피하기 위해 **크기 애니메이션은
> 제거하고 즉시 전환**한다.

## 동작
- 우측 상단 툴바, `Calendars`(캘린더 피커) 버튼 **왼쪽**에 토글 버튼 추가
- 누르면 캘린더 상단 여백(`geo.size.height * 0.18`)이 `16pt`로 접혀 캘린더가 위로 확장
- 다시 누르면 원래대로 펼쳐짐
- `easeInOut(duration: 0.3)` 애니메이션

## 상태
- `@AppStorage("collapseTopArea")` 불리언 (기존 `showTodayLine` 등과 동일 패턴, 앱 재시작 후 유지)
- 기본값: `false` (펼침 = 상단 영역 보임)

## 구현 (변경 지점) — `ContentView.swift`
1. `@AppStorage("collapseTopArea") private var collapseTopArea = false` 추가
2. `calendarBody`의 `.padding(.top, geo.size.height * 0.18)`
   → `.padding(.top, collapseTopArea ? 16 : geo.size.height * 0.18)`
3. 해당 영역에 `.animation(.easeInOut(duration: 0.3), value: collapseTopArea)` 적용
4. `toolbarContent`의 `.primaryAction` HStack 맨 앞에 토글 버튼 추가
   - 아이콘: `collapseTopArea ? "rectangle.tophalf.inset.filled" : "rectangle.topthird.inset.filled"`
   - `.help(...)` 툴팁

## 건드리지 않는 것
- 캔버스 아이템 좌표/표시 로직 (그대로 둠 — 접으면 일부가 캘린더에 가려질 수 있으나 사용자가 위치로 해결)
- 비전보드(화이트보드) 모드 — 버튼은 캘린더 모드 툴바에만 추가

## 검증
- 빌드 성공
- 버튼 클릭 시 상단 여백이 애니메이션으로 접힘/펼침
- 앱 재시작 후 상태 유지
