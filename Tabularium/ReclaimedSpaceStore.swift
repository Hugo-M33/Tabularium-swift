import Combine
import Foundation

/// Statistiques cumulées d'espace libéré par les suppressions.
struct ReclaimedStats: Codable, Equatable {
    var bytes: Int64 = 0
    var photos: Int = 0

    static let zero = ReclaimedStats()
}

/// Adaptateur de persistance des stats d'espace libéré.
///
/// Permet de remplacer le stockage local par iCloud (CloudKit) sans toucher au
/// reste de l'app : voir `LocalReclaimedStatsStorage` (actif) et
/// `CloudKitReclaimedStatsStorage` (prêt, à activer avec l'entitlement iCloud).
protocol ReclaimedStatsStorage {
    func load() async -> ReclaimedStats
    func save(_ stats: ReclaimedStats) async
}

/// Stockage local (UserDefaults). Implémentation par défaut.
struct LocalReclaimedStatsStorage: ReclaimedStatsStorage {
    private let key = "reclaimed.stats"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() async -> ReclaimedStats {
        guard let data = defaults.data(forKey: key),
              let stats = try? JSONDecoder().decode(ReclaimedStats.self, from: data)
        else { return .zero }
        return stats
    }

    func save(_ stats: ReclaimedStats) async {
        if let data = try? JSONEncoder().encode(stats) {
            defaults.set(data, forKey: key)
        }
    }
}

/// Source de vérité de l'espace libéré, exposée à l'UI. Indépendante du
/// stockage sous-jacent (local aujourd'hui, iCloud demain).
@MainActor
final class ReclaimedSpaceStore: ObservableObject {

    @Published private(set) var stats: ReclaimedStats = .zero
    /// Octets libérés au dernier commit (déclencheur du toast). Remis à 0 après
    /// affichage.
    @Published var lastBatchBytes: Int64 = 0

    private let storage: ReclaimedStatsStorage

    /// Pour passer à iCloud plus tard : injecter `CloudKitReclaimedStatsStorage()`
    /// ici (ou dans `TabulariumApp`).
    init(storage: ReclaimedStatsStorage = LocalReclaimedStatsStorage()) {
        self.storage = storage
    }

    func load() async {
        stats = await storage.load()
    }

    /// Enregistre un lot de suppressions appliquées. `bytes`/`photos` ne sont
    /// comptés que pour des suppressions réellement effectuées.
    func record(bytes: Int64, photos: Int) async {
        guard bytes > 0 || photos > 0 else { return }
        stats.bytes += bytes
        stats.photos += photos
        lastBatchBytes = bytes
        await storage.save(stats)
    }

    /// Libellé lisible du total (ex. « 1,2 Go »).
    var totalDisplay: String {
        ByteCountFormatter.string(fromByteCount: stats.bytes, countStyle: .file)
    }

    func display(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
