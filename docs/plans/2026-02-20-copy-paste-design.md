# Copy/Paste 기능 설계

## 목표
보드와 캘린더의 아이템(그림, 텍스트, SF 심볼, 도형)을 복사/붙여넣기 가능하게 한다. 크로스 모드(캘린더↔보드) 지원.

## 접근법
공유 ClipboardManager(@Observable)를 Environment로 주입. 기존 CanvasItemSnapshot을 확장하여 VisionBoardItem도 지원.

## 변경 사항

### 새 파일
- `ClipboardManager.swift` - @Observable 클래스, snapshot 프로퍼티 하나

### 수정 파일
- `CanvasItemSnapshot.swift` - VisionBoardItem 이니셜라이저 추가, toVisionBoardItem() 메서드 추가
- `PetalsApp.swift` - ClipboardManager 환경 주입
- `CanvasLayer.swift` - 로컬 clipboard → ClipboardManager 사용
- `DraggableCanvasItem.swift` - 컨텍스트 메뉴에 "복사하기" 추가
- `VisionBoardView.swift` - Cmd+C/V 지원, 붙여넣기 로직
- `DraggableVisionBoardItem.swift` - 컨텍스트 메뉴에 "복사하기" 추가

### 붙여넣기 위치
- 캘린더: 현재 페이지 중앙 (relativeX=0.5, relativeY=0.5)
- 비전보드: 현재 뷰포트 중앙

### UX
- Cmd+C: 선택된 아이템 복사
- Cmd+V: 붙여넣기
- 우클릭 컨텍스트 메뉴: "복사하기" 항목 추가
