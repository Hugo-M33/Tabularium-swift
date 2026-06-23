import SwiftUI
import GoogleMobileAds
import AppTrackingTransparency

@main
struct TabulariumApp: App {
    @StateObject private var swipeCredits = SwipeCreditsStore()
    @StateObject private var subscription = SubscriptionStore()
    @StateObject private var library = PhotoLibrary()
    @StateObject private var session = SortingSession()
    @StateObject private var gestures = GestureSettings()
    @StateObject private var nativeAds = NativeAdStore()
    @StateObject private var consent = ConsentManager()
    // Local aujourd'hui ; passer à `MirroredReclaimedStatsStorage()` une fois
    // l'entitlement iCloud/CloudKit en place (voir CloudKitReclaimedStatsStorage).
    @StateObject private var reclaimed = ReclaimedSpaceStore()

    init() {
        // Applique l'habillage « Organic Order » aux barres UIKit (police + couleurs).
        AppAppearance.configure()
        // Le SDK Google Mobile Ads n'est PAS démarré ici : il l'est seulement
        // après résolution du consentement (UMP → ATT), via ConsentManager.
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(swipeCredits)
                .environmentObject(subscription)
                .environmentObject(library)
                .environmentObject(session)
                .environmentObject(gestures)
                .environmentObject(nativeAds)
                .environmentObject(consent)
                .environmentObject(reclaimed)
                .task { await startupConsentAndAds() }
                .task { await subscription.loadProducts() }
                .task { await subscription.refreshEntitlements() }
                .task { await reclaimed.load() }
        }
    }

    /// Séquence de lancement liée aux pubs, dans l'ordre recommandé par Google :
    /// 1. consentement RGPD (UMP), 2. App Tracking Transparency (Apple),
    /// 3. démarrage du SDK pub — uniquement si le consentement l'autorise.
    private func startupConsentAndAds() async {
        await consent.gatherConsent()
        await requestTrackingAuthorization()
        consent.startAdsIfAllowed()
    }

    /// Demande l'autorisation App Tracking Transparency (ATT) pour
    /// les pubs personnalisées. La string d'usage est déjà déclarée
    /// dans les build settings (NSUserTrackingUsageDescription).
    private func requestTrackingAuthorization() async {
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }
}
