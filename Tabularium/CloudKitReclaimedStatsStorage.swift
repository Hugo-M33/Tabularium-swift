import CloudKit
import Foundation

/// Stockage iCloud (CloudKit, base privée) des stats d'espace libéré.
///
/// ⚠️ NON ACTIVÉ par défaut. Pour l'activer une fois le compte développeur prêt :
/// 1. Active la capability **iCloud → CloudKit** sur la cible (container par
///    défaut `iCloud.<bundle id>`).
/// 2. Injecte cette implémentation à la place de `LocalReclaimedStatsStorage`
///    dans `ReclaimedSpaceStore(storage:)` (idéalement via `TabulariumApp`).
/// 3. (Recommandé) Compose avec le local pour un cache hors-ligne : voir
///    `MirroredReclaimedStatsStorage` plus bas.
///
/// Les compteurs sont **cumulatifs** : pour éviter les régressions en cas de
/// course entre appareils, `save` fusionne en gardant le maximum par champ.
/// Une vraie addition atomique multi-appareils nécessiterait un champ delta côté
/// serveur — hors périmètre ici.
struct CloudKitReclaimedStatsStorage: ReclaimedStatsStorage {

    private let recordType = "ReclaimedStats"
    private let recordName = "reclaimedStats"          // enregistrement unique
    private enum Field {
        static let bytes = "bytes"
        static let photos = "photos"
    }

    private var database: CKDatabase { CKContainer.default().privateCloudDatabase }
    private var recordID: CKRecord.ID { CKRecord.ID(recordName: recordName) }

    func load() async -> ReclaimedStats {
        do {
            let record = try await database.record(for: recordID)
            return stats(from: record)
        } catch {
            // Enregistrement absent (premier lancement) ou hors-ligne → zéro.
            return .zero
        }
    }

    func save(_ stats: ReclaimedStats) async {
        do {
            // Récupère l'existant pour fusionner sans écraser une valeur plus haute.
            let record = (try? await database.record(for: recordID))
                ?? CKRecord(recordType: recordType, recordID: recordID)
            let merged = merge(local: stats, remote: self.stats(from: record))
            record[Field.bytes] = merged.bytes as CKRecordValue
            record[Field.photos] = Int64(merged.photos) as CKRecordValue
            _ = try await database.save(record)
        } catch {
            // Hors-ligne / quota : on échoue silencieusement, la valeur locale
            // (si composé avec le local) reste la référence.
        }
    }

    private func stats(from record: CKRecord) -> ReclaimedStats {
        let bytes = (record[Field.bytes] as? Int64) ?? 0
        let photos = Int((record[Field.photos] as? Int64) ?? 0)
        return ReclaimedStats(bytes: bytes, photos: photos)
    }

    private func merge(local: ReclaimedStats, remote: ReclaimedStats) -> ReclaimedStats {
        ReclaimedStats(bytes: max(local.bytes, remote.bytes),
                       photos: max(local.photos, remote.photos))
    }
}

/// Compose deux stockages : lit/écrit le local immédiatement (cache hors-ligne)
/// et réplique vers iCloud. À utiliser quand CloudKit sera activé.
struct MirroredReclaimedStatsStorage: ReclaimedStatsStorage {
    let local: ReclaimedStatsStorage
    let remote: ReclaimedStatsStorage

    init(local: ReclaimedStatsStorage = LocalReclaimedStatsStorage(),
         remote: ReclaimedStatsStorage = CloudKitReclaimedStatsStorage()) {
        self.local = local
        self.remote = remote
    }

    /// Au chargement : on prend le maximum entre local et distant (le distant
    /// peut être plus à jour depuis un autre appareil).
    func load() async -> ReclaimedStats {
        async let l = local.load()
        async let r = remote.load()
        let (lv, rv) = await (l, r)
        return ReclaimedStats(bytes: max(lv.bytes, rv.bytes),
                              photos: max(lv.photos, rv.photos))
    }

    func save(_ stats: ReclaimedStats) async {
        await local.save(stats)
        await remote.save(stats)
    }
}
