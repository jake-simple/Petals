# Petals 프리미엄 기능 차별화 (Freemium 전환) — 설계

> 작성일: 2026-06-02 · 상태: 설계 확정(MVP) · 후속: 구현 계획(writing-plans)

## 1. 목표 / 한 줄 요약

Petals를 **일회성 유료 구매**에서 **Freemium**으로 전환한다.
무료 = "1년 전체를 한 화면에 보는 연간 캘린더 뷰어", 프리미엄 = "그 위에 나만의 비주얼 플래너를 만드는 권한".
프리미엄은 **1회 결제(비소모성 IAP)로 영구 잠금해제**한다.

- **수익화 모델:** Freemium + Lifetime Unlock (구독 아님)
- **결제 상품:** 비소모성(Non-Consumable) IAP, Product ID `com.onessa.petals.premium` (App Store Connect에 생성 완료)

## 2. 무료 vs 프리미엄 경계 (A안)

### 🆓 무료 — 연간 캘린더 뷰어
결제 없이 완결적으로 사용 가능한 범위.

- 연간 그리드 뷰 (12개월 한 화면) — 앱의 정체성
- 줌 레벨 (12 / 3 / 1개월)
- EventKit 연동 (모든 캘린더 로드)
- 이벤트 CRUD (드래그 생성, 팝오버 조회·수정·삭제, 반복 일정)
- 캘린더 필터 / 오늘 라인
- 기본 테마 프리셋 9종 (선택만, 제작 불가)
- 이벤트 표시 설정 (폰트 크기, 최대 행 수)
- 캘린더 키보드 단축키
- CloudKit 동기화 (본인 기기 간)

### 💎 프리미엄 — 비주얼 플래너 (1회 결제)

| # | 기능 | 1차(MVP) | 상태 |
|---|------|:---:|------|
| 1 | **캔버스 꾸미기 레이어** — 캘린더 위에 이미지·텍스트·스티커·도형 배치/이동/크기·회전·Z순서·불투명도 | ✅ 포함 | 이미 구현됨 (게이트만) |
| 2 | **화이트보드 모드** — 무한 캔버스, 다중 보드 | ✅ 포함 | 이미 구현됨 (게이트만) |
| 3 | 내보내기 (PDF / 이미지) | ❌ 후속(2차) | 신규 개발 |
| 4 | 커스텀 테마 제작 | ❌ 후속(3차) | 신규 개발 |

**MVP 프리미엄 정의:** 이미 구현된 **캔버스 편집**과 **화이트보드 모드** 두 가지에 결제 게이트만 적용한다. 내보내기·커스텀 테마는 출시 후 프리미엄 가치를 키우는 추가 카드로 점진 도입(별도 스펙).

## 3. 게이트 UX (무료 사용자 동작)

원칙: **자물쇠 아이콘 없음.** 진입 버튼은 평범하게 보이고, 누르는 순간 페이월을 띄운다.

### 3.1 게이트 지점 (정확한 코드 위치)

| 게이트 | 위치 | 제어 상태 |
|--------|------|-----------|
| 캔버스 편집 진입 | `ContentView.swift:451` 캔버스 토글 (`isCanvasEditMode`) | `@State isCanvasEditMode` |
| 화이트보드 진입 | `ContentView.swift:147-156` 모드 토글 버튼 (`showVisionBoard.toggle()`) | `@State showVisionBoard` |

### 3.2 동작 규칙

- **무료 사용자가 캔버스 토글을 누르면:** 토글이 켜지지 않고(원복) **페이월 시트**가 뜬다. `isCanvasEditMode`는 `false` 유지.
- **무료 사용자가 화이트보드 버튼을 누르면:** 모드 전환하지 않고 **페이월 시트**가 뜬다. `showVisionBoard`는 `false` 유지.
- **프리미엄 사용자:** 기존과 100% 동일하게 즉시 진입.

### 3.3 캔버스 표시(읽기 전용) 처리

캘린더 모드의 캔버스 **표시 레이어**(`ContentView.swift:233-235`, read-only)는 무료 사용자에게도 그대로 보인다 — CloudKit으로 동기화된 기존 장식이 있으면 읽기 전용으로 노출되어 자연스러운 업셀이 된다. **편집 진입만** 게이트한다. (별도 한도/숨김 로직 없음 = MVP 단순성)

### 3.4 페이월 시트

- 캔버스로 꾸민 달력 **미리보기 이미지**(에셋) 1장
- 헤드라인: "캔버스를 켜고 나만의 달력을 만드세요" (ko) / 영어 대응
- 프리미엄에 포함되는 것 요약(캔버스 꾸미기 + 화이트보드)
- **[구매] 버튼** — 가격은 StoreKit `Product.displayPrice`로 표시(하드코딩 금지)
- **[구매 복원] 버튼** — App Store 필수 요건
- 닫기(X) 가능 → 무료 기능으로 복귀
- ko/en 현지화

## 4. 아키텍처

### 4.1 PremiumStore (신규)

`@Observable` 클래스. 앱 전역 단일 인스턴스, `PetalsApp` 루트에서 `.environment()` 주입(기존 `ClipboardManager` 패턴과 동일).

책임:
- StoreKit 2로 `com.onessa.petals.premium` Product 로드
- `var isPremium: Bool` — 현재 권한 상태(전역 참조 지점)
- `func purchase() async throws` — 구매 플로우
- `func restore() async throws` — 복원
- 앱 시작 시 `Transaction.currentEntitlements`로 권한 복원
- `Transaction.updates` 리스너로 결제 상태 변화 실시간 반영

소비처:
```swift
@Environment(PremiumStore.self) private var premium
```

### 4.2 게이트 적용 방식

`ContentView`에 페이월 표시용 `@State private var showPaywall = false` 추가.
두 진입점에서 `premium.isPremium` 확인 → 미보유면 상태 원복 + `showPaywall = true`.
`.sheet(isPresented: $showPaywall) { PaywallView() }`.

### 4.3 데이터 흐름

```
앱 시작
  └─ PremiumStore.init → currentEntitlements 조회 → isPremium 설정
       └─ Transaction.updates 리스너 가동(백그라운드)

사용자가 캔버스/화이트보드 진입 시도
  └─ premium.isPremium ?
        ├─ true  → 기존 동작(편집/모드 전환)
        └─ false → 상태 원복 + 페이월 표시
              └─ 구매 성공 → Transaction.finish → isPremium=true → 시트 닫고 진입
              └─ 복원 성공 → isPremium=true
              └─ 취소/실패 → 무료 유지
```

## 5. 에러 처리 / 엣지 케이스

- **네트워크 실패(상품 로드 실패):** 페이월에서 구매 버튼 비활성 + 재시도 안내. 앱의 무료 기능은 정상 동작.
- **구매 취소(`Product.PurchaseResult.userCancelled`):** 조용히 페이월 유지, 에러 표시 없음.
- **검증 실패(`VerificationResult.unverified`):** 권한 부여하지 않음.
- **복원했지만 구매 이력 없음:** "복원할 구매가 없습니다" 안내.
- **이미 프리미엄인데 페이월 도달(이론상 없음):** 방어적으로 즉시 진입 허용.
- **기존 유료 구매자 구제(Grandfathering):** **불필요.** 본 전환은 앱의 **최초 정식 출시**에 적용되며 기존 유료 구매자가 없음(2026-06-02 확인). 영수증 기반 무상 부여 로직 없음.

## 6. 미해결/확인 필요 항목

1. ~~기존 유료 출시 여부~~ — **해결:** 최초 출시, 기존 구매자 없음 → grandfathering 불필요.
2. **무료 사용자에게 보일 페이월 미리보기 에셋** — 캔버스로 꾸민 달력 샘플 이미지 1장 준비 필요(기존 App Store 스크린샷 재활용 가능).

## 7. 테스트 전략

- **StoreKit 구성 파일(`.storekit`)** 추가 → Xcode 로컬에서 구매/복원/취소 시뮬레이션.
- 검증 시나리오:
  1. 무료 상태에서 캔버스 토글 → 진입 안 됨 + 페이월 표시, `isCanvasEditMode == false` 유지
  2. 무료 상태에서 화이트보드 버튼 → 모드 전환 안 됨 + 페이월, `showVisionBoard == false` 유지
  3. 페이월에서 구매 성공 → `isPremium == true`, 시트 닫힘, 두 기능 즉시 사용 가능
  4. 앱 재시작 → `currentEntitlements`로 프리미엄 유지
  5. 복원 버튼 → 권한 복원
  6. 프리미엄 사용자 → 페이월 절대 안 뜸, 기존과 동일
  7. 캔버스 표시 레이어(읽기 전용)는 무료에서도 정상 렌더

## 8. 범위 밖 (Non-Goals)

- 구독 결제, 가격 티어, 평생/구독 혼합
- 캔버스 아이템/보드 **개수 한도** (C안 요소 — 도입 안 함)
- 내보내기(PDF/이미지), 커스텀 테마 에디터 (후속 별도 스펙)
- 자물쇠 아이콘/업셀 배너
- 협업·실시간 공유

## 9. 영향 받는 파일(예상)

| 파일 | 변경 |
|------|------|
| `Petals/Petals/PetalsApp.swift` | `PremiumStore` 생성·`.environment()` 주입 |
| `Petals/Petals/ContentView.swift` | 두 게이트 지점 분기, `showPaywall` 상태, `.sheet` |
| `Petals/Petals/Premium/PremiumStore.swift` (신규) | StoreKit 2 로직 |
| `Petals/Petals/Premium/PaywallView.swift` (신규) | 페이월 UI |
| `Petals.storekit` (신규) | 로컬 테스트 구성 |
| 현지화(ko/en) 문자열 | 페이월 카피 |
