import Combine
import Photos
import SwiftUI

/// Maintient une **fenêtre glissante** de photos préchargées via le cache de
/// `PhotoLibrary`. Partagé par la vue cartes et la vue flux : chacune fournit sa
/// fenêtre (ordonnée dans l'ordre d'apparition) et sa taille cible.
///
/// La taille cible fait partie de la clé de cache → si elle change (rotation,
/// passage cartes/flux), on purge l'ancienne fenêtre avant de recharger.
@MainActor
final class ImagePrefetcher: ObservableObject {
    private var current: [PHAsset] = []
    private var currentTarget: CGSize = .zero

    /// Met à jour la fenêtre préchargée : démarre les nouvelles photos, arrête
    /// celles sorties de la fenêtre.
    func update(_ window: [PHAsset], targetSize: CGSize, in library: PhotoLibrary) {
        guard targetSize.width > 0, targetSize.height > 0 else { return }

        // Changement de taille cible : on repart de zéro à l'ancienne taille.
        if targetSize != currentTarget {
            if !current.isEmpty { library.stopCaching(current, targetSize: currentTarget) }
            current = []
            currentTarget = targetSize
        }

        let windowIDs = Set(window.map(\.localIdentifier))
        let prevIDs = Set(current.map(\.localIdentifier))
        let toStop = current.filter { !windowIDs.contains($0.localIdentifier) }
        let toStart = window.filter { !prevIDs.contains($0.localIdentifier) }

        if !toStop.isEmpty { library.stopCaching(toStop, targetSize: currentTarget) }
        if !toStart.isEmpty { library.startCaching(toStart, targetSize: currentTarget) }
        current = window
    }

    /// Purge la fenêtre (sortie de l'écran / changement de mode).
    func reset(in library: PhotoLibrary) {
        if !current.isEmpty { library.stopCaching(current, targetSize: currentTarget) }
        current = []
    }
}
