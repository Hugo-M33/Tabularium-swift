import Combine
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

/// Gère le consentement publicitaire RGPD via le SDK Google UMP (User Messaging
/// Platform) et le démarrage **conditionnel** du SDK Google Mobile Ads.
///
/// Flux au lancement (piloté par `TabulariumApp`) : **UMP → ATT → démarrage pub**.
/// Aucune pub n'est demandée tant que `canRequestAds` est faux.
///
/// Garde-fou anti-bypass : `canRequestAds` pilote **toutes** les pubs (natives et
/// récompensées). Comme la pub récompensée est le seul moyen d'étendre le quota
/// quotidien, un refus rend l'utilisateur *plus* limité (pas moins) — la seule
/// sortie reste l'abonnement. Le quota lui-même (`SwipeCreditsStore`) est
/// indépendant de l'affichage des pubs.
@MainActor
final class ConsentManager: ObservableObject {

    /// Seul signal autorisant le chargement/affichage de toute pub et le
    /// démarrage du SDK.
    @Published private(set) var canRequestAds = false

    /// Vrai si Google impose de pouvoir rouvrir le formulaire (≈ utilisateurs UE)
    /// → pilote le bouton « Gérer le consentement » des Réglages.
    @Published private(set) var isPrivacyOptionsRequired = false

    /// Évite de démarrer le SDK pub plus d'une fois.
    private var didStartAds = false

    /// UMP : met à jour les infos de consentement puis présente le formulaire si
    /// nécessaire. Ne propage aucune erreur — un échec réseau ne doit pas bloquer
    /// le lancement (on retombe simplement sur `canRequestAds`).
    func gatherConsent() async {
        let parameters = RequestParameters()
        #if DEBUG
        // Force le formulaire de consentement en test, même hors UE.
        let debug = DebugSettings()
        debug.geography = .EEA
        // debug.testDeviceIdentifiers = ["<TON_ID_APPAREIL_DE_TEST>"]
        parameters.debugSettings = debug
        #endif

        await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { _ in
                continuation.resume()
            }
        }
        await withCheckedContinuation { continuation in
            ConsentForm.loadAndPresentIfRequired(from: nil) { _ in
                continuation.resume()
            }
        }
        refreshState()
    }

    /// Rouvre le formulaire de consentement (depuis les Réglages).
    func presentPrivacyOptionsForm() async {
        await withCheckedContinuation { continuation in
            ConsentForm.presentPrivacyOptionsForm(from: nil) { _ in
                continuation.resume()
            }
        }
        refreshState()
    }

    /// Démarre le SDK Google Mobile Ads si le consentement l'autorise (idempotent).
    /// Appelé après l'ATT au lancement, et après une modification du consentement.
    func startAdsIfAllowed() {
        guard canRequestAds, !didStartAds else { return }
        didStartAds = true
        MobileAds.shared.start(completionHandler: nil)
    }

    private func refreshState() {
        canRequestAds = ConsentInformation.shared.canRequestAds
        isPrivacyOptionsRequired =
            ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    #if DEBUG
    /// Réinitialise le consentement pour rejouer le flux en test.
    func resetForTesting() {
        ConsentInformation.shared.reset()
        canRequestAds = false
        isPrivacyOptionsRequired = false
        didStartAds = false
    }
    #endif
}
