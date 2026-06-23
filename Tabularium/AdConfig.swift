import Foundation

/// Source unique des identifiants publicitaires AdMob.
///
/// - En **DEBUG** : les ID de TEST officiels Google (jamais de vraies pubs en dev).
/// - En **release** (TestFlight + App Store) : les vrais ID AdMob.
///
/// ⚠️ L'**App ID** (`GADApplicationIdentifier`) ne vit PAS ici : c'est une clé
/// Info.plist, alimentée par le build setting `GAD_APP_ID` (test en Debug, réel
/// en Release). Voir `Info.plist` et les build settings du target.
///
/// ⚠️ En **release**, les pubs sont RÉELLES, y compris en **TestFlight**. Déclare
/// ton appareil comme appareil de test AdMob (console → Paramètres → Appareils de
/// test, ou via `requestConfiguration.testDeviceIdentifiers`) pour éviter une
/// suspension « invalid traffic » si tu cliques tes propres pubs.
enum AdConfig {

    /// Bloc « Native advanced ».
    static let nativeAdUnitID: String = {
        #if DEBUG
        return "ca-app-pub-3940256099942544/3986624511"   // test Google
        #else
        return "ca-app-pub-2907281852868427/2653560983"   // réel
        #endif
    }()

    /// Bloc « Rewarded ».
    static let rewardedAdUnitID: String = {
        #if DEBUG
        return "ca-app-pub-3940256099942544/1712485313"   // test Google
        #else
        return "ca-app-pub-2907281852868427/7135731470"   // réel
        #endif
    }()
}
