import SwiftUI

/// Écran d'abonnement « illimité », présenté en feuille.
struct PaywallView: View {
    @EnvironmentObject private var subscription: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.stackLg) {
                    ZStack {
                        Circle()
                            .fill(Palette.primaryGradient)
                            .frame(width: 84, height: 84)
                            .shadow(color: Palette.primary.opacity(0.3), radius: 16, y: 6)
                        Image(systemName: "infinity")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(Palette.onPrimary)
                    }
                    .padding(.top, Spacing.stackMd)

                    VStack(spacing: Spacing.base) {
                        Text("paywall.title")
                            .textStyle(.headlineLG)
                            .foregroundStyle(Palette.onSurface)
                        Text("paywall.subtitle")
                            .textStyle(.bodyLG)
                            .foregroundStyle(Palette.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, Spacing.marginMain)

                    VStack(alignment: .leading, spacing: Spacing.stackMd) {
                        benefit("infinity", "paywall.benefit.nolimit")
                        benefit("hand.raised.slash", "paywall.benefit.noads")
                        benefit("bolt.fill", "paywall.benefit.continuous")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard(padding: Spacing.stackLg)
                    .padding(.horizontal, Spacing.marginMain)

                    VStack(spacing: Spacing.gutter) {
                        Button {
                            Task {
                                await subscription.purchase()
                                if subscription.isUnlimited { dismiss() }
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text("paywall.subscribe")
                                Text("paywall.pricepermonth.\(subscription.displayPrice)")
                                    .textStyle(.bodySM)
                                    .foregroundStyle(Palette.onPrimary.opacity(0.85))
                            }
                        }
                        .buttonStyle(.primaryCTA)
                        .disabled(subscription.purchaseInProgress)

                        Button("paywall.restore") {
                            Task {
                                await subscription.restore()
                                if subscription.isUnlimited { dismiss() }
                            }
                        }
                        .font(.app(.bodyEmph))
                        .foregroundStyle(Palette.primary)
                    }
                    .padding(.horizontal, Spacing.marginMain)

                    Text("paywall.legal")
                        .textStyle(.labelCaps)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.marginMain)

                    if subscription.purchaseInProgress {
                        ProgressView().padding(.bottom)
                    }
                }
                .padding(.bottom, Spacing.stackLg)
            }
            .background(Palette.surface)
            .navigationTitle("premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
            }
        }
    }

    private func benefit(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.stackMd) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.primary)
                .frame(width: 40, height: 40)
                .background(Palette.halo, in: Circle())
            Text(text)
                .textStyle(.bodyLG)
                .foregroundStyle(Palette.onSurface)
            Spacer(minLength: 0)
        }
    }
}
