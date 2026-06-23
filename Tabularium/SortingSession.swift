import Combine
import Photos
import SwiftUI

/// Direction d'une action de tri en mode cartes. Sert à la fois à router le geste
/// (gauche/droite/haut) et à rejouer la **transition d'entrée** à l'annulation :
/// la carte revient en glissant depuis le bord par lequel elle était sortie.
enum SwipeDirection {
    case left, right, up, down
}

/// Contexte de tri **partagé** entre la vue cartes et la vue flux.
///
/// Les deux modes lisent et écrivent le même curseur (`index`) et les mêmes
/// décisions : seul l'affichage change, l'avancement est commun. On conserve en
/// plus un index persistant des photos déjà triées (`sortedIDs`) pour ne jamais
/// les reproposer, et de quoi calculer le taux de galerie analysée.
@MainActor
final class SortingSession: ObservableObject {

    /// Source d'un batch de tri.
    enum Source: Equatable, Hashable {
        case random
        case album(id: String, title: String)

        var isAlbum: Bool { if case .album = self { return true }; return false }
        var title: String {
            switch self {
            case .random: return ""
            case .album(_, let t): return t
            }
        }
    }

    /// Décision (batchée) prise sur une photo, appliquée seulement au commit.
    enum Decision: Equatable, Hashable {
        case kept
        case deleted
        case filed(String)   // classer dans l'album (localIdentifier)
    }

    /// Élément de la séquence de tri partagée : une photo ou une pub.
    /// Les pubs font partie du contexte commun → elles apparaissent aussi bien
    /// en mode cartes qu'en mode flux, et le curseur peut s'y arrêter.
    enum Item: Identifiable, Equatable {
        case photo(PHAsset)
        case ad(Int)
        var id: String {
            switch self {
            case .photo(let a): return a.localIdentifier
            case .ad(let n): return "ad-\(n)"
            }
        }
        var asset: PHAsset? { if case .photo(let a) = self { return a } else { return nil } }
        var isAd: Bool { if case .ad = self { return true } else { return false } }
        static func == (l: Item, r: Item) -> Bool { l.id == r.id }
    }

    // Batch courant (partagé cartes/flux).
    /// Photos brutes du batch (pour décisions, corbeille, favoris).
    @Published private(set) var assets: [PHAsset] = []
    /// Séquence affichée = photos + pubs interleavées (partagée par les 2 vues).
    @Published private(set) var items: [Item] = []
    /// Curseur partagé : position dans `items`. Cartes et flux le pilotent.
    @Published var index: Int = 0
    @Published private(set) var decisions: [String: Decision] = [:]
    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var source: Source?

    /// Une action de tri annulable (mode cartes). On retient l'identifiant de la
    /// photo, la direction de sortie (pour l'animation de retour) et si **cette**
    /// action a posé le favori — afin de ne dé-favoriser à l'annulation que ce
    /// qu'on a réellement ajouté, jamais un favori préexistant.
    struct UndoStep: Equatable {
        let id: String
        let direction: SwipeDirection
        let addedFavorite: Bool
    }

    /// Résultat d'un retour en arrière, à appliquer côté écran (crédit + favori).
    struct Undo {
        let asset: PHAsset
        let direction: SwipeDirection
        let removeFavorite: Bool
    }

    /// Pile des actions annulables du batch courant. Vidée au démarrage d'un batch
    /// et **après un commit** : on ne peut pas annuler une décision déjà appliquée.
    @Published private(set) var undoStack: [UndoStep] = []

    // Stats globales.
    @Published private(set) var totalCount: Int = 0
    /// Photos déjà triées (toutes sessions confondues), persistées.
    @Published private(set) var sortedIDs: Set<String>

    private static let sortedKey = "sorting.sortedIDs"

    /// File d'attente dédiée à l'écriture disque, **hors thread principal**.
    /// `sortedIDs` est cumulatif (toutes sessions) : sa sérialisation grossit avec
    /// l'usage, et `persist()` est appelé à chaque photo qui sort de l'écran. Faire
    /// l'encodage sur le main bloquerait le défilement lors d'un swipe rapide.
    private let persistQueue = DispatchQueue(label: "com.tabularium.sorting.persist", qos: .utility)

    init() {
        sortedIDs = Set(UserDefaults.standard.stringArray(forKey: Self.sortedKey) ?? [])
    }

    // MARK: - Cycle de vie d'un batch

    /// - Parameter adInterval: insère une pub toutes les N photos ; `nil` = aucune
    ///   pub (premium).
    func start(_ batch: [PHAsset], source: Source, totalCount: Int, adInterval: Int?) {
        self.assets = batch
        self.source = source
        self.totalCount = totalCount
        self.index = 0
        self.decisions = [:]
        self.favorites = Set(batch.filter(\.isFavorite).map(\.localIdentifier))
        self.items = Self.buildItems(batch, adInterval: adInterval)
    }

    private static func buildItems(_ batch: [PHAsset], adInterval: Int?) -> [Item] {
        guard let interval = adInterval, interval > 0 else { return batch.map { .photo($0) } }
        var result: [Item] = []
        var adCount = 0
        for (i, asset) in batch.enumerated() {
            result.append(.photo(asset))
            if (i + 1) % interval == 0 { result.append(.ad(adCount)); adCount += 1 }
        }
        return result
    }

    func updateTotalCount(_ n: Int) { totalCount = n }

    // MARK: - Curseur partagé

    var currentItem: Item? { items.indices.contains(index) ? items[index] : nil }
    var currentAsset: PHAsset? { currentItem?.asset }
    var isFinished: Bool { !items.isEmpty && index >= items.count }
    func advance() { index = min(index + 1, items.count) }

    /// Index (dans `items`) d'un élément par son identifiant.
    func itemIndex(ofID id: String) -> Int? {
        items.firstIndex { $0.id == id }
    }

    /// Fenêtre de photos à précharger autour d'un index : la photo courante
    /// d'abord, puis l'aval, puis l'amont — dans l'ordre d'apparition. Les pubs
    /// sont ignorées.
    func prefetchWindow(around idx: Int, ahead: Int, behind: Int) -> [PHAsset] {
        guard items.indices.contains(idx) else { return [] }
        let lower = max(0, idx - behind)
        let upper = min(items.count - 1, idx + ahead)
        var result: [PHAsset] = []
        for i in idx...upper { if let a = items[i].asset { result.append(a) } }
        if lower < idx {
            for i in stride(from: idx - 1, through: lower, by: -1) {
                if let a = items[i].asset { result.append(a) }
            }
        }
        return result
    }

    // MARK: - Décisions

    func recordKeep(_ asset: PHAsset) { setDecision(.kept, asset) }
    func recordDelete(_ asset: PHAsset) { setDecision(.deleted, asset) }
    func recordFile(_ asset: PHAsset, albumID: String) { setDecision(.filed(albumID), asset) }
    func recordUndo(_ asset: PHAsset) {
        decisions[asset.localIdentifier] = nil
        removeSorted(asset.localIdentifier)
    }
    func decision(for asset: PHAsset) -> Decision? { decisions[asset.localIdentifier] }

    private func setDecision(_ d: Decision, _ asset: PHAsset) {
        decisions[asset.localIdentifier] = d
        insertSorted(asset.localIdentifier)
    }

    // MARK: - Favoris

    func isFavorite(_ asset: PHAsset) -> Bool { favorites.contains(asset.localIdentifier) }
    @discardableResult
    func toggleFavoriteState(_ asset: PHAsset) -> Bool {
        let id = asset.localIdentifier
        if favorites.contains(id) { favorites.remove(id); return false }
        favorites.insert(id); return true
    }

    // MARK: - Corbeille (photos du batch marquées à supprimer)

    var keptAssets: [PHAsset] {
        assets.filter { decisions[$0.localIdentifier] == .kept }
    }
    var pendingDeleteAssets: [PHAsset] {
        assets.filter { decisions[$0.localIdentifier] == .deleted }
    }
    func filedAssets(albumID: String) -> [PHAsset] {
        assets.filter { decisions[$0.localIdentifier] == .filed(albumID) }
    }
    /// Albums vers lesquels au moins une photo du batch est classée.
    var filedAlbumIDs: [String] {
        var ids: [String] = []
        for a in assets {
            if case .filed(let id)? = decisions[a.localIdentifier], !ids.contains(id) { ids.append(id) }
        }
        return ids
    }
    var trashCount: Int { pendingDeleteAssets.count }
    /// Nombre d'actions en attente de commit (suppressions + classements).
    var pendingActionCount: Int {
        assets.filter {
            guard let d = decisions[$0.localIdentifier] else { return false }
            return d != .kept
        }.count
    }

    /// Après commit (suppressions + classements appliqués) : retire ces photos
    /// du batch en préservant le curseur sur la prochaine photo à trier.
    func clearCommitted(_ ids: Set<String>) {
        let upTo = min(index, items.count)
        let removedBefore = items[..<upTo].filter { item in
            if let a = item.asset { return ids.contains(a.localIdentifier) }
            return false
        }.count
        assets.removeAll { ids.contains($0.localIdentifier) }
        items.removeAll { item in
            if let a = item.asset { return ids.contains(a.localIdentifier) }
            return false
        }
        ids.forEach { decisions[$0] = nil }
        index = max(0, min(index - removedBefore, items.count))
    }

    // MARK: - Stats

    var sortedCount: Int { sortedIDs.count }
    var progress: Double { totalCount == 0 ? 0 : min(1, Double(sortedCount) / Double(totalCount)) }

    /// Réinitialise l'index des photos triées : toutes redeviennent à trier.
    func resetSorted() {
        sortedIDs = []
        decisions = [:]
        persist()
    }

    /// Élague les IDs triés ne correspondant plus à une photo existante
    /// (supprimées, médias retirés…) → garantit `sortedCount ≤ totalCount`.
    func pruneSorted(existing ids: Set<String>) {
        let before = sortedIDs.count
        sortedIDs.formIntersection(ids)
        if sortedIDs.count != before { persist() }
    }

    private func insertSorted(_ id: String) {
        if sortedIDs.insert(id).inserted { persist() }
    }
    private func removeSorted(_ id: String) {
        if sortedIDs.remove(id) != nil { persist() }
    }
    private func persist() {
        // Snapshot léger (copie de références) pris sur le main, puis encodage +
        // écriture déportés : le thread principal ne paie jamais la sérialisation.
        let snapshot = Array(sortedIDs)
        let key = Self.sortedKey
        persistQueue.async {
            UserDefaults.standard.set(snapshot, forKey: key)
        }
    }
}
