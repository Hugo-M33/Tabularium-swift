# Écran de lancement (splash)

## Comportement

Au démarrage, l'app affiche un splash de marque : **fond vert forêt `#105637`**,
mot-symbole **« TABULARIUM »** centré en blanc (Plus Jakarta Sans Bold, capitales
espacées) et un fin indicateur de chargement indéterminé en bas. Après une durée
minimale (~1,6 s), le splash **s'efface en fondu** et laisse apparaître l'accueil
(ou l'onboarding au premier lancement).

## Deux couches (zéro flash blanc)

1. **Launch screen natif** — `Info.plist` → `UILaunchScreen` avec
   `UIColorName = AccentColor` (qui vaut `#105637`). Affiché instantanément par
   le système avant tout code SwiftUI : couvre l'instant zéro sans flash blanc.
2. **Splash SwiftUI animé** (`SplashView`) — prend le relais avec le mot-symbole
   animé (fondu + léger zoom), puis appelle `onFinished` pour se retirer.

Le même vert sur les deux couches rend la transition transparente.

## Ordre avec l'onboarding

`RootView` empile le splash **au-dessus** de tout (`zIndex(1)`). L'onboarding du
premier lancement (`fullScreenCover`) n'est déclenché qu'**une fois le splash
effacé** (dans `onFinished`), pour qu'il ne passe pas sous le splash.

## Où

- `SplashView.swift` — vue du splash + `LoadingBar` (segment lumineux glissant).
- `RootView.swift` — empilement splash / accueil / onboarding.
- `Info.plist` — clé `UILaunchScreen`.
- Couleur de marque : `Palette.primary` / `AccentColor` = `#105637`
  (`DesignSystem.swift`).

## À valider

Rendu visuel à confirmer sur simulateur/appareil (timing du fondu, taille du
mot-symbole). Maquette de référence générée via Stitch (nom seul, blanc sur vert,
capitales).
