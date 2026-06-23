# Premium : revue obligatoire en fin de lot

## Comportement

En mode tri, un lot contient jusqu'à **100 photos** non triées. Pour un compte
**premium**, lorsque le lot est terminé (`SortingSession.isFinished`) :

- s'il reste des **décisions en attente** (`pendingActionCount > 0`, c.-à-d. des
  suppressions ou classements non validés), **l'écran de revue s'ouvre
  automatiquement**. Le lot suivant n'est chargé qu'**après validation**
  (`commitChanges()`), via le callback de `ReviewScreen`.
- s'il n'y a **rien à valider**, on enchaîne directement sur un nouveau lot
  (`loadNextBatch()`).

L'utilisateur peut aussi annuler la revue : les décisions sont alors **conservées**
(non perdues) et l'écran « terminé » reste affiché avec le bouton de revue.

## Pourquoi

Auparavant, à la fin du lot, `loadNextBatch()` appelait `session.start(...)` qui
réinitialise `decisions` et `undoStack`. Pour un premium (enchaînement
automatique), cela **effaçait silencieusement les suppressions/classements non
validés** et tirait un nouveau lot de 100 photos sans jamais passer par
`commitChanges()`. La revue forcée garantit qu'aucune décision n'est perdue au
passage d'un lot à l'autre.

## Où

- `SorterScreen.swift` — `onChange(of: session.isFinished)` (garde-fou) et le
  callback de commit du `sheet(isPresented: $showReview)` (enchaînement après
  validation).
- `SortingSession.swift` — `start(...)` réinitialise l'état du lot ;
  `pendingActionCount` ; `clearCommitted(_:)` (appliqué au commit, retire les
  photos traitées en préservant le curseur).
