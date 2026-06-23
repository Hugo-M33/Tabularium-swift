import Combine
import Photos
import SwiftUI

/// Passerelle PhotoKit : autorisations, liste d'albums, tirage de batchs non
/// triés, chargement d'images, favoris et suppression par lot. Ne porte pas
/// l'état de tri (curseur, décisions) → voir `SortingSession`.
@MainActor
final class PhotoLibrary: ObservableObject {

    @Published var status: PHAuthorizationStatus = .notDetermined

    private let imageManager = PHCachingImageManager()

    /// Un album présenté sur l'écran d'accueil.
    struct Album: Identifiable, Hashable {
        let id: String
        let title: String
        let count: Int
        let cover: PHAsset?

        static func == (a: Album, b: Album) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    func requestAccess() async {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        status = s
    }

    // MARK: - Fetch

    private func imageFetchOptions() -> PHFetchOptions {
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return o
    }

    private func allImageAssets() -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(with: imageFetchOptions())
    }

    /// Nombre total de photos de la photothèque (toutes images).
    var totalImageCount: Int { allImageAssets().count }

    /// Identifiants de toutes les photos actuellement présentes (pour élaguer
    /// l'index des photos triées et garder des stats cohérentes).
    func allImageIDs() -> Set<String> {
        var ids = Set<String>()
        allImageAssets().enumerateObjects { a, _, _ in ids.insert(a.localIdentifier) }
        return ids
    }

    /// Albums créés par l'utilisateur (où l'on peut ajouter des photos). Inclut
    /// les albums vides → cibles possibles pour les raccourcis de classement.
    func fetchUserAlbums() -> [Album] {
        var albums: [Album] = []
        let user = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        user.enumerateObjects { coll, _, _ in
            let assets = PHAsset.fetchAssets(in: coll, options: self.imageFetchOptions())
            albums.append(Album(id: coll.localIdentifier,
                                title: coll.localizedTitle ?? "Album",
                                count: assets.count,
                                cover: assets.firstObject))
        }
        return albums
    }

    /// Ajoute une photo à un album utilisateur (classement par raccourci).
    func addAsset(_ asset: PHAsset, toAlbumID id: String) async throws {
        guard let coll = PHAssetCollection
            .fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
            .firstObject else { return }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest(for: coll)
            request?.addAssets([asset] as NSArray)
        }
    }

    /// Albums (smart + utilisateur) contenant au moins une image.
    func fetchAlbums() -> [Album] {
        var albums: [Album] = []

        func add(_ collections: PHFetchResult<PHAssetCollection>) {
            collections.enumerateObjects { coll, _, _ in
                let assets = PHAsset.fetchAssets(in: coll, options: self.imageFetchOptions())
                guard assets.count > 0 else { return }
                albums.append(Album(id: coll.localIdentifier,
                                    title: coll.localizedTitle ?? "Album",
                                    count: assets.count,
                                    cover: assets.firstObject))
            }
        }

        // Albums « intelligents » utiles (favoris, récents…).
        let smart = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        // Albums créés par l'utilisateur.
        let user = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        add(smart)
        add(user)
        return albums
    }

    /// Construit un batch de photos **non triées** pour une source.
    /// - `.random` : tirage aléatoire dans toute la photothèque.
    /// - `.album`  : photos de l'album, dans l'ordre.
    func batch(for source: SortingSession.Source,
               excluding sorted: Set<String>,
               limit: Int) -> [PHAsset] {
        switch source {
        case .random:
            var pool: [PHAsset] = []
            allImageAssets().enumerateObjects { a, _, _ in
                if !sorted.contains(a.localIdentifier) { pool.append(a) }
            }
            pool.shuffle()
            return Array(pool.prefix(limit))

        case .album(let id, _):
            guard let coll = PHAssetCollection
                .fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
                .firstObject else { return [] }
            var pool: [PHAsset] = []
            PHAsset.fetchAssets(in: coll, options: imageFetchOptions()).enumerateObjects { a, _, _ in
                if !sorted.contains(a.localIdentifier) { pool.append(a) }
            }
            return Array(pool.prefix(limit))
        }
    }

    /// Nombre de photos non triées restantes pour une source (pour les stats).
    func remainingCount(for source: SortingSession.Source, excluding sorted: Set<String>) -> Int {
        switch source {
        case .random:
            var n = 0
            allImageAssets().enumerateObjects { a, _, _ in
                if !sorted.contains(a.localIdentifier) { n += 1 }
            }
            return n
        case .album(let id, _):
            guard let coll = PHAssetCollection
                .fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
                .firstObject else { return 0 }
            var n = 0
            PHAsset.fetchAssets(in: coll, options: imageFetchOptions()).enumerateObjects { a, _, _ in
                if !sorted.contains(a.localIdentifier) { n += 1 }
            }
            return n
        }
    }

    // MARK: - Préchargement (cache)

    /// Options de requête/cache communes : conditionnent la clé de cache, donc
    /// elles doivent être identiques pour le préchargement et l'affichage afin
    /// que le cache soit réellement réutilisé.
    private func cachingOptions() -> PHImageRequestOptions {
        let o = PHImageRequestOptions()
        o.deliveryMode = .opportunistic
        o.isNetworkAccessAllowed = true
        o.resizeMode = .fast
        return o
    }

    /// Démarre le préchargement des photos données (dans l'ordre fourni, c.-à-d.
    /// l'ordre où elles vont apparaître). `targetSize`/`contentMode` doivent
    /// correspondre à `image(for:targetSize:)` pour un cache effectif.
    func startCaching(_ assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        imageManager.startCachingImages(for: assets,
                                        targetSize: targetSize,
                                        contentMode: .aspectFill,
                                        options: cachingOptions())
    }

    /// Arrête le préchargement des photos sorties de la fenêtre.
    func stopCaching(_ assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        imageManager.stopCachingImages(for: assets,
                                       targetSize: targetSize,
                                       contentMode: .aspectFill,
                                       options: cachingOptions())
    }

    /// Vide tout le cache de préchargement (sortie du flux).
    func stopAllCaching() {
        imageManager.stopCachingImagesForAllAssets()
    }

    // MARK: - Image

    func image(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            imageManager.requestImage(
                for: asset, targetSize: targetSize,
                contentMode: .aspectFill, options: options
            ) { img, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded { continuation.resume(returning: img) }
            }
        }
    }

    // MARK: - Taille disque

    /// Estimation des octets occupés par les photos données (somme des
    /// ressources : original, version éditée, etc.). À calculer **avant**
    /// suppression — l'asset n'est plus interrogeable une fois supprimé.
    func byteSize(of assets: [PHAsset]) -> Int64 {
        var total: Int64 = 0
        for asset in assets {
            for resource in PHAssetResource.assetResources(for: asset) {
                // `fileSize` n'est pas exposé publiquement mais lisible en KVC ;
                // usage répandu et accepté sur l'App Store.
                if let size = resource.value(forKey: "fileSize") as? Int64 {
                    total += size
                } else if let size = resource.value(forKey: "fileSize") as? Int {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    // MARK: - Mutations

    func toggleFavorite(_ asset: PHAsset) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest(for: asset)
            request.isFavorite = !asset.isFavorite
        }
    }

    /// Supprime les photos données (iOS affiche sa propre alerte de confirmation).
    func deleteAssets(_ assets: [PHAsset]) async throws {
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }
}
