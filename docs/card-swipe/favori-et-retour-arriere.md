# Mode cartes — swipe favori (haut) & retour arrière (tap)

Deux gestes ajoutés au mode cartes (`SwipeCardView` + `SorterScreen`) :

- **Swipe vers le haut** = ajout aux favoris façon « superlike », puis passage à la
  carte suivante.
- **Tap simple** sur la carte = retour à la carte précédente, avec **annulation
  complète** de l'action qui y avait été appliquée.

## Geste de swipe (SwipeCardView)

Le callback est passé de `(_ keep: Bool)` à `(_ direction: SwipeDirection)`
(`SwipeDirection` est défini dans `SortingSession.swift`, partagé modèle/vue).

Détection en fin de `DragGesture` :

1. **Haut** si le déplacement vers le haut dépasse le seuil **et** domine l'axe
   horizontal (`-height > threshold && -height > |width|`) → `onSwipe(.up)`. La carte
   s'envole par le haut.
2. Sinon **gauche/droite** si `|width| > threshold` (comportement inchangé).
3. Sinon ressort de rappel.

Seuil unique : `threshold = 110`. Haptique `.medium` à la validation, action émise
après 0,18 s (le temps de l'animation de sortie), comme l'horizontal.

Une 3ᵉ étiquette **FAVORI** (étoile, `Palette.gold`, clé i18n `card.favorite`)
apparaît au swipe vertical. Les étiquettes sont gatées par l'axe dominant pour ne pas
clignoter ensemble en diagonale.

## Favori (swipe haut)

`SorterScreen.performCardFavorite()` :

- consomme un crédit de swipe (comme tout swipe carte) ;
- `session.recordFavoriteKeep(asset)` : marque la photo `.kept` **et** l'ajoute à
  `favorites`. Renvoie `true` si le favori est **nouveau** ;
- si nouveau → `library.setFavorite(asset, true)` (écriture PhotoKit idempotente, ne
  bascule pas un favori déjà posé contrairement à `toggleFavorite`) ;
- empile une action annulable et avance le curseur.

Marquer favori n'ajoute **pas** d'action à committer (`.kept` n'est pas une action en
attente) : le favori est écrit immédiatement dans la photothèque.

## Retour arrière (tap)

Pile d'annulation explicite dans `SortingSession` :

```swift
struct UndoStep { let id: String; let direction: SwipeDirection; let addedFavorite: Bool }
@Published private(set) var undoStack: [UndoStep]
```

Chaque action carte (swipe G/D, swipe haut, boutons ✕/dossier/♥) empile un `UndoStep`
via `pushUndo`. `goBack()` dépile le dernier, **retrouve la photo par son identifiant**
(robuste à l'interleaving des pubs), efface sa décision (`recordUndo`), retire le favori
**uniquement si cette action l'avait posé** (`addedFavorite`), et ramène le curseur.

`SorterScreen.goBack()` applique ensuite :

- `credits.refund(...)` — le swipe consommé est rendu ;
- `library.setFavorite(asset, false)` si l'on avait posé le favori ;
- déclenche la transition d'entrée.

### Conditions de désactivation

- **Aucune action réalisée** → `undoStack` vide → `goBack()` renvoie `nil` → no-op.
- **Après un commit** → `clearCommitted(...)` vide la pile : on ne peut pas annuler une
  décision déjà appliquée (suppression / classement effectués). Idem au démarrage d'un
  batch (`start`).

## Transition d'entrée

`UndoStep.direction` mémorise le bord de sortie de la carte. Au retour, `SorterScreen`
cible la carte concernée (`reentryID` + `reentryEdge`) et `SwipeCardView` la fait
**glisser depuis ce bord** : état `entered` initialement `false` + `entryOffset(in:)`
hors écran, animé à zéro à l'`onAppear` (ressort). Pas de flash car le premier rendu
part déjà hors champ. Mapping bouton → bord : garder=droite, supprimer=gauche,
classer=bas, favori=haut.

## Crédits

`SwipeCreditsStore.refund(isUnlimited:)` rend un swipe (plafonné comme la pub
récompensée à `dailyLimit * 10`). Sans effet en illimité.

## Fichiers touchés

- `SwipeCardView.swift` — directions, label favori, tap, transition d'entrée.
- `SortingSession.swift` — `SwipeDirection`, `UndoStep`/`Undo`, `undoStack`,
  `recordFavoriteKeep`, `pushUndo`, `goBack`, purge au commit/start.
- `SorterScreen.swift` — `handleSwipe`, `performCardFavorite`, `goBack`,
  `undoDirection`, état de ré-entrée, push undo sur les actions existantes.
- `SwipeCreditsStore.swift` — `refund`.
- `PhotoLibrary.swift` — `setFavorite`.
- `Localizable.xcstrings` — clé `card.favorite` (FR « FAVORI » / EN « FAVORITE »).
