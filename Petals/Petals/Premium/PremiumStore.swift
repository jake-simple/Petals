import Foundation
import StoreKit

/// 프리미엄 권한의 단일 소스. StoreKit 2 비소모성 IAP 기반.
@Observable
@MainActor
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
    private var refreshTask: Task<Void, Never>?

    init() {
        // 백그라운드에서 결제 상태 변화를 지속 감시.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(verificationResult: update)
            }
        }
        refreshTask = Task { [weak self] in
            await self?.refresh()
        }
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

    /// 검증된 트랜잭션을 finish하고 현재 entitlement를 재스캔.
    /// 구매·환불·취소를 모두 일관되게 isPremium에 반영한다.
    private func handle(verificationResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verificationResult else {
            return  // unverified → 권한 부여 안 함
        }
        await transaction.finish()
        await updateEntitlement()
    }
}
