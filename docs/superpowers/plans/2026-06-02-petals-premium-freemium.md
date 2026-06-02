# Petals 프리미엄 Freemium 전환 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Petals를 Freemium으로 전환 — 무료는 연간 캘린더 뷰어, 프리미엄(1회 결제)은 캔버스 꾸미기 + 화이트보드 모드. 무료 사용자가 두 기능 진입 버튼을 누르면 페이월을 띄운다.

**Architecture:** `@Observable PremiumStore`(StoreKit 2)를 앱 루트에 `.environment()`로 주입(기존 `ClipboardManager` 패턴 동일). `ContentView`의 캔버스 토글·화이트보드 토글 두 진입점에서 `premium.isPremium`을 확인해, 미보유 시 상태를 원복하고 `PaywallView` 시트를 띄운다. 권한은 `Transaction.currentEntitlements`로 복원하고 `Transaction.updates`로 실시간 반영.

**Tech Stack:** Swift, SwiftUI, StoreKit 2, `@Observable`, String Catalog(`Localizable.xcstrings`). 비소모성 IAP `com.onessa.petals.premium` (App Store Connect 생성 완료).

---

## 검증 방식에 대한 주의 (TDD 예외)

이 코드베이스에는 **테스트 타깃이 없고 기존 테스트가 0개**다. 또한 StoreKit 구매·복원 플로우는 단위 테스트가 아니라 **StoreKit 구성 파일(`.storekit`) 기반 런타임 테스트**로 검증하는 것이 표준이다. 따라서 본 계획은 XCTest 단위 TDD 대신 다음으로 검증한다:

1. **빌드 성공** — `xcodebuild ... build` 가 통과
2. **StoreKit 로컬 런타임 테스트** — `.storekit` 구성으로 Xcode에서 구매/복원/취소 시뮬레이션
3. **수동 검증 체크리스트** — 스펙 §7 시나리오

각 코드 Task는 "빌드 통과"를 1차 게이트로, 마지막 Task에서 런타임 시나리오를 검증한다. 새 테스트 타깃은 만들지 않는다(기존 패턴 준수 · 범위 최소화).

**빌드 명령(공통):**
```bash
xcodebuild -project Petals/Petals.xcodeproj -scheme Petals -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`

---

## 파일 구조

| 파일 | 책임 | 신규/수정 |
|------|------|-----------|
| `Petals/Petals/Premium/PremiumStore.swift` | StoreKit 2 권한 상태 단일 소스. 상품 로드·구매·복원·entitlement 감시. | 신규 |
| `Petals/Petals/Premium/PaywallView.swift` | 페이월 UI(미리보기·기능요약·구매·복원·닫기). | 신규 |
| `Petals/Petals/PetalsApp.swift` | `PremiumStore` 생성·`.environment()` 주입. | 수정 |
| `Petals/Petals/ContentView.swift` | 두 게이트 분기, `showPaywall` 상태, `.sheet`. | 수정 |
| `Petals.storekit` | 로컬 StoreKit 런타임 테스트 구성. | 신규 |
| `Petals/Petals/Localizable.xcstrings` | 페이월 문자열 한국어 번역. | 수정(Xcode GUI) |

---

## Task 1: PremiumStore (StoreKit 2)

권한 상태의 단일 소스. 다른 어떤 Task도 이 객체의 `isPremium`만 참조한다.

**Files:**
- Create: `Petals/Petals/Premium/PremiumStore.swift`

- [ ] **Step 1: PremiumStore 구현**

`Petals/Petals/Premium/PremiumStore.swift` 생성:

```swift
import Foundation
import StoreKit

/// 프리미엄 권한의 단일 소스. StoreKit 2 비소모성 IAP 기반.
@Observable
final class PremiumStore {
    /// App Store Connect에 생성된 비소모성 상품 ID.
    static let productID = "com.onessa.petals.premium"

    /// 현재 프리미엄 권한 보유 여부. 앱 전역에서 이 값만 참조한다.
    private(set) var isPremium = false

    /// 로드된 프리미엄 상품. 페이월에서 가격 표시·구매에 사용.
    private(set) var product: Product?

    /// 상품 로드 실패 등으로 구매 버튼을 비활성화해야 하는지.
    var isStoreAvailable: Bool { product != nil }

    private var updatesTask: Task<Void, Never>?

    init() {
        // 백그라운드에서 결제 상태 변화를 지속 감시.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(verificationResult: update)
            }
        }
        Task { await refresh() }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// 상품 로드 + 현재 권한 복원. 앱 시작 시 1회.
    func refresh() async {
        await loadProduct()
        await updateEntitlement()
    }

    /// 구매 플로우. 성공 시 isPremium 반영.
    func purchase() async {
        guard let product else { return }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verificationResult: verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            // 네트워크 등 실패: 조용히 무시(무료 기능은 정상). 페이월은 유지.
            print("Purchase failed: \(error)")
        }
    }

    /// 구매 복원(App Store 필수 요건).
    func restore() async {
        try? await AppStore.sync()
        await updateEntitlement()
    }

    // MARK: - Private

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            print("Product load failed: \(error)")
            product = nil
        }
    }

    /// 현재 활성 entitlement를 스캔해 isPremium 갱신.
    private func updateEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                isPremium = true
                return
            }
        }
        isPremium = false
    }

    /// 검증된 트랜잭션만 권한 부여하고 finish.
    private func handle(verificationResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verificationResult else {
            return  // unverified → 권한 부여 안 함
        }
        if transaction.productID == Self.productID, transaction.revocationDate == nil {
            isPremium = true
        }
        await transaction.finish()
    }
}
```

- [ ] **Step 2: 빌드 검증**

`PremiumStore.swift`는 아직 어디서도 참조되지 않으므로 컴파일만 확인.

Run:
```bash
xcodebuild -project Petals/Petals.xcodeproj -scheme Petals -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add Petals/Petals/Premium/PremiumStore.swift
git commit -m "feat: StoreKit 2 PremiumStore (프리미엄 권한 단일 소스)"
```

---

## Task 2: 앱 루트에 PremiumStore 주입

`ClipboardManager`와 동일한 패턴으로 전역 주입.

**Files:**
- Modify: `Petals/Petals/PetalsApp.swift:6`, `:43`

- [ ] **Step 1: PremiumStore 인스턴스 추가**

`Petals/Petals/PetalsApp.swift:6` 의 `clipboardManager` 선언 바로 아래에 추가:

```swift
    @State private var clipboardManager = ClipboardManager()
    @State private var premiumStore = PremiumStore()
```

- [ ] **Step 2: environment 주입**

`Petals/Petals/PetalsApp.swift:43` 의 `.environment(clipboardManager)` 바로 아래에 추가:

```swift
                .environment(clipboardManager)
                .environment(premiumStore)
```

- [ ] **Step 3: 빌드 검증**

Run:
```bash
xcodebuild -project Petals/Petals.xcodeproj -scheme Petals -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 커밋**

```bash
git add Petals/Petals/PetalsApp.swift
git commit -m "feat: PremiumStore를 앱 루트 environment에 주입"
```

---

## Task 3: PaywallView

무료 사용자가 보게 될 페이월 시트. 영어 소스 문자열(자동 현지화), 가격은 StoreKit `displayPrice`.

**Files:**
- Create: `Petals/Petals/Premium/PaywallView.swift`

- [ ] **Step 1: PaywallView 구현**

`Petals/Petals/Premium/PaywallView.swift` 생성:

```swift
import SwiftUI

/// 무료 사용자가 프리미엄 기능 진입을 시도할 때 표시되는 페이월.
struct PaywallView: View {
    @Environment(PremiumStore.self) private var premium
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false

    var body: some View {
        VStack(spacing: 20) {
            // 미리보기 이미지 (에셋 카탈로그에 추가, Task 6 참고)
            Image("PaywallPreview")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Make the year your own")
                .font(.title).bold()

            Text("Turn on the canvas and design your own visual calendar.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Label("Decorate your calendar with images, text, stickers, and shapes", systemImage: "paintbrush")
                Label("Whiteboard mode — an infinite canvas with multiple boards", systemImage: "sparkles.rectangle.stack")
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task {
                    isPurchasing = true
                    await premium.purchase()
                    isPurchasing = false
                    if premium.isPremium { dismiss() }
                }
            } label: {
                Text(buyButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!premium.isStoreAvailable || isPurchasing)

            Button("Restore Purchase") {
                Task {
                    await premium.restore()
                    if premium.isPremium { dismiss() }
                }
            }
            .buttonStyle(.plain)
            .font(.callout)

            if !premium.isStoreAvailable {
                Text("Couldn’t reach the App Store. Please try again later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 420)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .onChange(of: premium.isPremium) { _, isPremium in
            if isPremium { dismiss() }
        }
    }

    private var buyButtonTitle: String {
        if let price = premium.product?.displayPrice {
            return String(localized: "Unlock Premium — \(price)")
        }
        return String(localized: "Unlock Premium")
    }
}
```

- [ ] **Step 2: 빌드 검증**

`PaywallPreview` 이미지는 Task 6에서 추가하지만, 누락 시에도 컴파일은 통과한다(런타임에 빈 이미지). 컴파일 확인:

Run:
```bash
xcodebuild -project Petals/Petals.xcodeproj -scheme Petals -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add Petals/Petals/Premium/PaywallView.swift
git commit -m "feat: 프리미엄 페이월 화면(PaywallView)"
```

---

## Task 4: 캔버스 편집 진입 게이트

무료 사용자가 캔버스 토글을 켜면 → 토글 원복 + 페이월. 프리미엄은 기존 동작.

**Files:**
- Modify: `Petals/Petals/ContentView.swift` (상태 추가, `:451` 토글 교체, `body`에 `.sheet`)

- [ ] **Step 1: premium 환경값 + showPaywall 상태 추가**

`Petals/Petals/ContentView.swift:40` 의 `@State private var isCanvasEditMode = false` 바로 위(또는 인접)에 추가:

```swift
    // Premium gating
    @Environment(PremiumStore.self) private var premium
    @State private var showPaywall = false

    // Canvas state
    @State private var isCanvasEditMode = false
```

- [ ] **Step 2: 캔버스 토글을 게이트 바인딩으로 교체**

`Petals/Petals/ContentView.swift:451-454` 의 현재 토글:

```swift
                // Canvas edit mode toggle
                Toggle(isOn: $isCanvasEditMode) {
                    Label("Canvas", systemImage: "paintbrush")
                }
                .toggleStyle(.button)
```

을 다음으로 교체:

```swift
                // Canvas edit mode toggle (premium gated)
                Toggle(isOn: Binding(
                    get: { isCanvasEditMode },
                    set: { newValue in
                        if newValue && !premium.isPremium {
                            showPaywall = true          // 진입 차단 + 페이월
                        } else {
                            isCanvasEditMode = newValue
                        }
                    }
                )) {
                    Label("Canvas", systemImage: "paintbrush")
                }
                .toggleStyle(.button)
```

- [ ] **Step 3: body에 페이월 시트 부착**

`Petals/Petals/ContentView.swift:112` 의 `.navigationTitle(...)` 줄 바로 아래에 추가:

```swift
        .navigationTitle(showVisionBoard ? "화이트보드" : "캘린더")
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
```

- [ ] **Step 4: 빌드 검증**

Run:
```bash
xcodebuild -project Petals/Petals.xcodeproj -scheme Petals -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add Petals/Petals/ContentView.swift
git commit -m "feat: 캔버스 편집 진입을 프리미엄 게이트로 보호"
```

---

## Task 5: 화이트보드 진입 게이트

무료 사용자가 화이트보드 버튼을 누르면 → 모드 전환 차단 + 페이월. 화이트보드→캘린더 복귀는 항상 허용.

**Files:**
- Modify: `Petals/Petals/ContentView.swift:148-155` (`modeToggleToolbar`)

- [ ] **Step 1: 모드 토글 버튼에 게이트 추가**

`Petals/Petals/ContentView.swift:149-150` 의 현재 액션:

```swift
        ToolbarItem(placement: .navigation) {
            Button {
                showVisionBoard.toggle()
            } label: {
```

을 다음으로 교체:

```swift
        ToolbarItem(placement: .navigation) {
            Button {
                if !showVisionBoard && !premium.isPremium {
                    showPaywall = true              // 화이트보드 진입 차단 + 페이월
                } else {
                    showVisionBoard.toggle()        // 진입 또는 캘린더 복귀
                }
            } label: {
```

- [ ] **Step 2: 빌드 검증**

Run:
```bash
xcodebuild -project Petals/Petals.xcodeproj -scheme Petals -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add Petals/Petals/ContentView.swift
git commit -m "feat: 화이트보드 진입을 프리미엄 게이트로 보호"
```

---

## Task 6: 페이월 미리보기 이미지 에셋

`PaywallView`의 `Image("PaywallPreview")`가 참조하는 에셋. 기존 App Store 스크린샷(꾸민 달력)을 재활용한다.

**Files:**
- Create: `Petals/Petals/Assets.xcassets/PaywallPreview.imageset/` (Xcode GUI)

- [ ] **Step 1: 후보 이미지 확인**

기존 마케팅/스크린샷 에셋에서 "캔버스로 꾸민 달력"이 보이는 이미지를 찾는다:

```bash
ls AppStore/ 2>/dev/null; find . -path ./build -prune -o \( -name "*.png" -name "*.jpg" \) -print 2>/dev/null | grep -iv build | head -20
```

- [ ] **Step 2: 에셋 추가 (Xcode)**

Xcode에서 `Assets.xcassets` 열기 → New Image Set → 이름 `PaywallPreview` → 위 이미지를 드래그. (코드의 `Image("PaywallPreview")`와 정확히 일치)

- [ ] **Step 3: 빌드 검증**

Run:
```bash
xcodebuild -project Petals/Petals.xcodeproj -scheme Petals -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 커밋**

```bash
git add Petals/Petals/Assets.xcassets/PaywallPreview.imageset
git commit -m "assets: 페이월 미리보기 이미지 추가"
```

---

## Task 7: 페이월 한국어 번역 (String Catalog)

`PaywallView`의 영어 소스 문자열은 빌드 시 `Localizable.xcstrings`에 자동 추출된다. 한국어 번역을 채운다.

**Files:**
- Modify: `Petals/Petals/Localizable.xcstrings` (Xcode String Catalog 에디터)

- [ ] **Step 1: 빌드로 문자열 추출**

먼저 한 번 빌드해 새 문자열이 카탈로그에 등록되게 한다:

```bash
xcodebuild -project Petals/Petals.xcodeproj -scheme Petals -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: 한국어 번역 입력 (Xcode)**

Xcode에서 `Localizable.xcstrings` 열기 → Korean 열에 다음 번역 입력:

| English (key) | 한국어 |
|------|------|
| `Make the year your own` | 나만의 한 해를 만드세요 |
| `Turn on the canvas and design your own visual calendar.` | 캔버스를 켜고 나만의 비주얼 캘린더를 만들어 보세요. |
| `Decorate your calendar with images, text, stickers, and shapes` | 이미지·텍스트·스티커·도형으로 달력을 꾸미세요 |
| `Whiteboard mode — an infinite canvas with multiple boards` | 화이트보드 모드 — 여러 보드를 갖춘 무한 캔버스 |
| `Unlock Premium — %@` | 프리미엄 잠금해제 — %@ |
| `Unlock Premium` | 프리미엄 잠금해제 |
| `Restore Purchase` | 구매 복원 |
| `Couldn’t reach the App Store. Please try again later.` | App Store에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요. |

각 항목의 상태를 "translated"로 표시(체크)한다.

- [ ] **Step 3: 빌드 검증**

```bash
xcodebuild -project Petals/Petals.xcodeproj -scheme Petals -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 커밋**

```bash
git add Petals/Petals/Localizable.xcstrings
git commit -m "i18n: 페이월 한국어 번역 추가"
```

---

## Task 8: StoreKit 로컬 테스트 구성 + 런타임 검증

`.storekit` 구성으로 실제 App Store 없이 구매/복원/취소를 검증한다.

**Files:**
- Create: `Petals.storekit`

- [ ] **Step 1: StoreKit 구성 파일 생성 (Xcode)**

Xcode: File ▸ New ▸ File ▸ StoreKit Configuration File → 이름 `Petals` → 프로젝트 루트에 저장.
Non-Consumable 추가:
- Reference Name: `Petals Premium`
- Product ID: `com.onessa.petals.premium`
- Price: 임의(예: 4.99)
- Localizations: Display Name / Description (en, ko) 입력

- [ ] **Step 2: 스킴에 구성 연결 (Xcode)**

Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Options ▸ StoreKit Configuration → `Petals.storekit` 선택.

- [ ] **Step 3: 런타임 검증 (스펙 §7 시나리오)**

앱 실행 후 다음을 순서대로 확인:

1. **무료 상태 + 캔버스 토글** → 캔버스 편집 진입 안 됨, 페이월 표시. (`isCanvasEditMode` false 유지)
2. **무료 상태 + 화이트보드 버튼** → 모드 전환 안 됨, 페이월 표시. (`showVisionBoard` false 유지)
3. **페이월에서 구매** → 시트 닫힘, 캔버스 토글·화이트보드 즉시 동작.
4. **앱 재시작** → 프리미엄 유지(`currentEntitlements` 복원), 페이월 안 뜸.
5. **구매 복원 버튼**(Xcode Transaction Manager에서 구매 삭제 후 재시작 → 무료 상태에서 복원) → 권한 복원.
6. **프리미엄 상태** → 두 기능 모두 페이월 없이 기존과 동일.
7. **캔버스 표시 레이어(읽기 전용)** → 무료 상태에서도 기존 장식이 정상 렌더(편집만 차단).

각 항목을 통과시킨다. 실패 시 superpowers:systematic-debugging로 디버깅.

- [ ] **Step 4: 커밋**

```bash
git add Petals.storekit Petals/Petals.xcodeproj
git commit -m "test: StoreKit 로컬 테스트 구성 추가"
```

---

## Self-Review 결과 (작성자 확인)

- **스펙 커버리지:** §2 무료/프리미엄 경계(Task 4·5 게이트), §3 게이트 UX·지점(Task 4·5), §3.3 읽기전용 표시(Task 8 시나리오 7 — 코드 변경 없음, 기존 표시 레이어 유지), §3.4 페이월(Task 3·6·7), §4 PremiumStore·주입(Task 1·2), §5 엣지케이스(Task 1: userCancelled/unverified/네트워크 실패 처리, restore), §7 테스트(Task 8). §5 grandfathering=불필요(코드 없음, 의도된 누락). 모두 매핑됨.
- **플레이스홀더:** 없음. 모든 코드/명령/번역 실값 기재.
- **타입 일관성:** `premium`(환경값), `premium.isPremium`/`.product`/`.isStoreAvailable`/`.purchase()`/`.restore()` — Task 1 정의와 Task 3·4·5 사용처 일치. `showPaywall`·`PaywallView`·`PaywallPreview`·`com.onessa.petals.premium` 전 Task 일관.
