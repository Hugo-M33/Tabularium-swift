import Combine
import GoogleMobileAds
import SwiftUI

/// Gère les pubs récompensées (rewarded ads) via le SDK Google Mobile Ads.
///
/// L'identifiant du bloc d'annonces est centralisé dans `AdConfig` (ID de test
/// en Debug, ID réel en release).
@MainActor
final class RewardedAdManager: NSObject, ObservableObject {

    static let adUnitID = AdConfig.rewardedAdUnitID

    @Published private(set) var isLoading = false
    @Published private(set) var isReady = false

    private var rewardedAd: RewardedAd?

    func load() {
        guard !isLoading else { return }
        isLoading = true

        // `async` overload : tout s'exécute sur le MainActor (la classe
        // est @MainActor), donc pas de capture de `self` dans une closure
        // @Sendable non isolée — évite les erreurs de concurrence Swift 6.
        Task { @MainActor in
            defer { isLoading = false }
            do {
                rewardedAd = try await RewardedAd.load(with: Self.adUnitID, request: Request())
                isReady = true
            } catch {
                rewardedAd = nil
                isReady = false
            }
        }
    }

    /// Présente la pub. `onReward` est appelé seulement si l'utilisateur
    /// a regardé jusqu'au bout.
    func show(from root: UIViewController?, onReward: @escaping () -> Void) {
        guard let rewardedAd, let root else { return }
        rewardedAd.present(from: root) {
            onReward()
        }
        self.rewardedAd = nil
        self.isReady = false
        load() // précharge la suivante
    }
}
