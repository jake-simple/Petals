import StoreKit
import SwiftUI

/// 무료 사용자가 프리미엄 기능 진입을 시도할 때 표시되는 페이월.
struct PaywallView: View {
    @Environment(PremiumStore.self) private var premium
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false

    var body: some View {
        VStack(spacing: 20) {
            // 미리보기 이미지 (에셋 카탈로그에 추가, 후속 Task)
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
                Text("Couldn't reach the App Store. Please try again later.")
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
