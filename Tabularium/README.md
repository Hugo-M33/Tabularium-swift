# Tabularium — tri de photos par swipe (SwiftUI)

Trie ta pellicule façon Tinder : swipe à **gauche pour supprimer**, à **droite pour garder**.
Modèle : **100 swipes/jour** · une **pub** redonne **+100** · abonnement **3 €/mois** pour l'**illimité**.

## Fichiers

| Fichier | Rôle |
|---|---|
| `TabulariumApp.swift` | Point d'entrée, injection des stores |
| `RootView.swift` / `SwipeScreen.swift` | UI principale |
| `SwipeCardView.swift` | Carte photo swipable (geste + animations) |
| `PaywallView.swift` | Écran d'abonnement |
| `PhotoLibrary.swift` | Accès PhotoKit, fetch, suppression par lot |
| `SwipeCreditsStore.swift` | Quota quotidien + reset minuit + reward |
| `SubscriptionStore.swift` | Abonnement StoreKit 2 |
| `RewardedAdManager.swift` | Pub récompensée (stub AdMob) |

## Mise en place dans Xcode

1. **Crée un projet** App > Interface SwiftUI, puis remplace/ajoute ces fichiers.
2. **Info.plist** — ajoute :
   - `NSPhotoLibraryUsageDescription` : « L'app a besoin d'accéder à tes photos pour les trier. »
   - `NSPhotoLibraryAddUsageDescription` (utile pour read-write).
3. **Capabilities** : active *In-App Purchase*.

## StoreKit (abonnement 3 €/mois)

1. App Store Connect → crée un **abonnement auto-renouvelable** à 3 €/mois.
2. Reporte son ID dans `SubscriptionStore.productID`.
3. Test local : Xcode → *File > New > StoreKit Configuration File*, ajoute le produit,
   puis sélectionne-le dans *Edit Scheme > Run > Options > StoreKit Configuration*.

## AdMob (pub récompensée)

1. SPM : `https://github.com/googleads/swift-package-manager-google-mobile-ads.git`
2. Info.plist : `GADApplicationIdentifier`, `SKAdNetworkItems`, `NSUserTrackingUsageDescription`.
3. Dans `TabulariumApp` : `MobileAds.shared.start(completionHandler: nil)`.
4. Dans `RewardedAdManager.swift` : décommente les blocs `// ADMOB`, supprime `simulateReward`,
   remplace l'ID de test par ton vrai *ad unit ID*.

## Localisation (anglais par défaut + français)

Les textes sont externalisés dans des **String Catalogs** (Xcode 15+) :
- `Localizable.xcstrings` — textes de l'interface.
- `InfoPlist.xcstrings` — textes des pop-ups système (accès photos, ATT).

Pour activer les langues dans Xcode :
1. Sélectionne le **projet** (pas la cible) → onglet *Info* → *Localizations*.
2. Ajoute le **Français** (l'anglais est la langue de développement par défaut).
3. Les deux `.xcstrings` se remplissent automatiquement ; les traductions FR sont déjà fournies.

Pour ajouter une langue (ex. espagnol) : ajoute-la dans *Localizations*, Xcode crée
les entrées vides dans les catalogues, puis traduis chaque clé. Le code n'a pas à changer.

Le prix de l'abonnement s'affiche déjà dans la devise locale via `Product.displayPrice`
(StoreKit), et Apple gère les conversions par région.

## Mise en place du fichier `.xcstrings` dans l'app

Glisse `Localizable.xcstrings` et `InfoPlist.xcstrings` dans la cible de l'app
(coche *Target Membership*). C'est tout — `Text("clé")` résout automatiquement.

## ⚠️ Conformité App Store (important)



- La suppression de photos passe **toujours** par l'alerte système de PhotoKit
  (les photos vont dans « Supprimées récemment », réversible) — ne la contourne pas.
- Les pubs récompensées sont **autorisées** comme moyen de regagner des swipes,
  mais ne présente jamais la pub comme obligatoire pour récupérer des données déjà existantes.
- Affiche les **mentions d'abonnement** (renouvellement auto, prix, résiliation) sur le paywall —
  déjà présent dans `PaywallView`. Ajoute aussi des liens vers tes CGU et politique de confidentialité.
- Respecte l'**App Tracking Transparency** (prompt ATT avant tout tracking publicitaire).
