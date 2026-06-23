# Tester le Premium & codes promo

Ce document explique comment débloquer le mode Premium (« illimité ») pour le
test, et comment fonctionnent les vrais codes promo App Store.

## Vue d'ensemble

Il existe **deux** mécanismes distincts, gérés dans
[`SubscriptionStore.swift`](../../Tabularium/SubscriptionStore.swift) et exposés
dans l'écran Réglages ([`SettingsScreen.swift`](../../Tabularium/SettingsScreen.swift)) :

| Mécanisme | Pour qui | Où | Coût |
|---|---|---|---|
| **Code de test interne** | Toi + testeurs TestFlight | Champ « Code de test » dans Réglages | Gratuit, aucune config |
| **Offer Codes Apple** | Vrais utilisateurs (prod) | Bouton « J'ai un code promo » → feuille Apple | Géré dans App Store Connect |

La section promo n'apparaît dans Réglages que si l'utilisateur **n'est pas déjà**
illimité.

## 1. Code de test interne (TestFlight)

### Comment l'utiliser

1. Lance l'app (depuis Xcode **ou** via TestFlight interne/externe).
2. Ouvre **Réglages** → section **Code promo**.
3. Saisis le code de test et tape **Valider**.
4. Le Premium est débloqué immédiatement (persisté entre les lancements).

Le code par défaut est défini dans `SubscriptionStore.testPromoCode` :

```swift
static let testPromoCode = "TABU-VIP"
```

> Change cette valeur quand tu veux. La comparaison ignore la casse et les
> espaces autour.

### Revenir en version gratuite (test)

Une fois le Premium débloqué via le code de test, un bouton **« Repasser en
version gratuite »** apparaît dans Réglages (section dédiée). Il appelle
`SubscriptionStore.lockPremiumForTesting()`, qui annule le code de test (et, en
Debug, l'override `debugForcePremium`).

Ce bouton n'apparaît que si :

- `allowsTestPromo` est vrai (Debug/TestFlight), **et**
- l'utilisateur est illimité, **et**
- il **n'a pas** de vrai abonnement StoreKit (`entitled`) — un vrai abonnement
  ne peut être révoqué que par Apple, pas par l'app.

Il est donc absent en production App Store.

### Pourquoi c'est sans risque en production

Le champ et le code ne sont honorés que si `SubscriptionStore.allowsTestPromo`
est vrai. Cette propriété dépend du **type de reçu au runtime**, pas de la
configuration de build :

```swift
static var allowsTestPromo: Bool {
    #if DEBUG
    return true
    #else
    return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    #endif
}
```

| Build | Reçu | `allowsTestPromo` | Champ de test |
|---|---|---|---|
| Xcode (Debug) | — | `true` | ✅ visible & actif |
| TestFlight interne/externe (Release) | `sandboxReceipt` | `true` | ✅ visible & actif |
| App Store production (Release) | `receipt` | `false` | ❌ caché & inerte |

Important : la feature **est** compilée en Release (rien n'est entouré de
`#if DEBUG` à part l'ancien toggle de dev `debugForcePremium`). C'est donc bien
le même binaire qui part en TestFlight puis sur l'App Store ; seul le reçu
change, ce qui désactive automatiquement le code de test en production.

De plus, `isUnlimited` revérifie `allowsTestPromo` à chaque lecture :

```swift
if promoUnlocked && Self.allowsTestPromo { return true }
```

Donc même si le flag `promo.unlocked` survivait à une migration TestFlight →
App Store, il n'accorderait **aucun** Premium en production.

## 2. Offer Codes Apple (vrais codes promo)

Pour distribuer de vrais codes promo aux utilisateurs (presse, early adopters,
campagnes), on utilise les **Offer Codes** d'abonnement App Store.

### Côté app

Déjà en place : le bouton **« J'ai un code promo »** ouvre la feuille de
rédemption native via le modifier SwiftUI `.offerCodeRedemption`. Après une
rédemption réussie, `Transaction.updates` (écouté dans `SubscriptionStore.init`)
met à jour l'entitlement automatiquement.

### Côté App Store Connect (à faire une fois l'abonnement approuvé)

1. L'abonnement auto-renouvelable (`SubscriptionStore.productID`) doit exister et
   être **approuvé** (au moins « Ready to Submit » / publié).
2. App Store Connect → ton app → **Abonnements** → ton produit → **Offer Codes**.
3. Crée une campagne d'offer codes (gratuit X mois, prix réduit, etc.) et génère
   les codes (lien web ou liste de codes uniques).

> ⚠️ Les Offer Codes sont pensés pour la **production**. Ils ne sont pas
> testables de façon fiable en sandbox/TestFlight — d'où le code de test interne
> pour la phase de test.

### Alternative : achat sandbox en TestFlight

En TestFlight, tout achat via le paywall passe automatiquement en **sandbox**
(gratuit, sans vrai paiement), dès que le produit IAP existe en
« Ready to Submit ». C'est une autre façon de tester le parcours d'achat complet,
sans code.

## Récapitulatif des fichiers

- `Tabularium/SubscriptionStore.swift` — `testPromoCode`, `allowsTestPromo`,
  `promoUnlocked`, `redeemTestCode(_:)`, `isUnlimited`.
- `Tabularium/SettingsScreen.swift` — `promoSection`, modifier
  `.offerCodeRedemption`.
- `Tabularium/Localizable.xcstrings` — clés `settings.promo`,
  `settings.offercode`, `settings.testcode.*`.
