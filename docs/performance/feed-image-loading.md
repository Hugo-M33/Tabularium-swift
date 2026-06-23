# Mode flux : chargement d'images annulable

## Problème

En mode flux (`FeedScreen`), scroller très vite ne gelait pas, mais après une
**pause de 0,5–1 s** l'UI se figeait quelques secondes (impossible de scroller).

## Cause racine

`PhotoLibrary.image(for:targetSize:)` n'était **pas annulable**. Chaque
`FeedPhotoCell` charge son image plein écran via `.task(id:)`. Quand la cellule
sort de l'écran, SwiftUI **annule le `.task`**, mais le `withCheckedContinuation`
ignorait l'annulation et la requête `PHImageManager.requestImage` sous-jacente
continuait. Un scroll rapide empilait donc des dizaines de requêtes plein écran
jamais annulées ; `PHCachingImageManager` ayant une concurrence limitée, ce
**backlog se vidait à l'arrêt du scroll** (décodage + livraison + mises à jour
d'état SwiftUI sur le thread principal) → gel « après une pause ».

## Correctif

`image(for:)` est désormais enveloppé dans `withTaskCancellationHandler` :
l'annulation du `.task` (cellule qui sort de l'écran) **annule la requête
`PHImageManager` en vol** (`cancelImageRequest`), ce qui draine le backlog.

Détails (`PhotoLibrary.swift`) :

- `ImageRequestBox` (verrou `NSLock`) coordonne trois courses :
  - handler de résultat (thread principal) vs `onCancel` (thread quelconque) ;
  - reprise **unique** de la continuation (contrat `withCheckedContinuation`) ;
  - annulation arrivée **avant** que l'ID de requête soit connu (image en cache →
    handler synchrone, ou annulation très précoce) → `setID` annule alors aussitôt.
- `.opportunistic` livre d'abord une miniature dégradée (ignorée) : on attend la
  pleine résolution ou le résultat d'annulation.

## À surveiller

L'effet *perçu* doit être validé sur **appareil réel** (le profilage perf ne se
fait pas en simulateur). Si un gel résiduel subsiste, le suspect suivant est la
fenêtre de préchargement (`prefetchAhead = 12` images plein écran, assez lourde
en mémoire dans `FeedScreen`/`SorterScreen`) — à ajuster avec des mesures.
