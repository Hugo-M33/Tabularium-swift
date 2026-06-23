import Photos
import SwiftUI

/// Apparence d'une action de swipe (icône + teinte). `isActive == false` =
/// direction sans action assignée (aucun retour visuel, geste ignoré).
private struct SwipeVisual {
    let icon: String
    let tint: Color
    let isActive: Bool
}

/// Mode flux vertical façon TikTok. Affichage alternatif du **même** contexte de
/// tri (`SortingSession`). Les décisions (garder / supprimer / classer dans un
/// dossier) sont **batchées** et appliquées au commit. Les gestes horizontaux
/// sont configurables (premium) par direction.
struct FeedScreen: View {
    @EnvironmentObject private var session: SortingSession
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var credits: SwipeCreditsStore
    @EnvironmentObject private var subscription: SubscriptionStore
    @EnvironmentObject private var gestures: GestureSettings

    @Binding var showPaywall: Bool
    let onOutOfCredits: () -> Void

    @State private var scrolledID: String?
    @State private var creditedIDs: Set<String> = []
    @StateObject private var prefetcher = ImagePrefetcher()

    private var isUnlimited: Bool { subscription.isUnlimited }

    // MARK: - Préchargement (fenêtre glissante)

    /// Photos en aval à garder chaudes en cache (≥ curr+10).
    private let prefetchAhead = 12
    /// Quelques photos en amont (retour arrière fluide).
    private let prefetchBehind = 2

    /// Taille cible plein écran (en pixels) — identique à celle des cellules.
    private var feedTargetSize: CGSize {
        let scale = UIScreen.main.scale
        let b = UIScreen.main.bounds.size
        return CGSize(width: b.width * scale, height: b.height * scale)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(session.items) { item in
                    itemView(item)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(item.id)
                        .onAppear { handleAppear(item) }
                        .onDisappear { handleDisappear(item) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledID)
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if photoCount > 0 {
                positionCounter
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let asset = currentAsset {
                feedControls(for: asset)
            }
        }
        .onAppear {
            if scrolledID == nil { scrolledID = session.currentItem?.id }
            prefetch(around: scrolledID)
        }
        .onDisappear { prefetcher.reset(in: library) }
        .onChange(of: scrolledID) { _, id in
            syncCursor(to: id)
            prefetch(around: id)
        }
    }

    // MARK: - Compteur de position (n / N)

    /// Nombre total de photos du batch (les pubs ne comptent pas).
    private var photoCount: Int { session.assets.count }

    /// Position de la photo courante : nombre de photos dans `items[0...curseur]`.
    /// Sur un emplacement de pub, le compteur se cale sur la dernière photo vue.
    private var photoPosition: Int {
        guard let id = scrolledID, let idx = session.itemIndex(ofID: id) else {
            return min(1, photoCount)
        }
        let count = session.items[...idx].reduce(0) { $0 + ($1.asset != nil ? 1 : 0) }
        return max(1, min(count, photoCount))
    }

    private var positionCounter: some View {
        Text(verbatim: "\(photoPosition) / \(photoCount)")
            .font(.app(.bodyEmph).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassPill()
            .environment(\.colorScheme, .dark)
            .padding(.top, safeAreaTop + 8)
    }

    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.top }
            .first ?? 0
    }

    // MARK: - Préchargement

    /// Met à jour la fenêtre de préchargement autour du curseur.
    private func prefetch(around id: String?) {
        guard let id, let idx = session.itemIndex(ofID: id) else { return }
        let window = session.prefetchWindow(around: idx, ahead: prefetchAhead, behind: prefetchBehind)
        prefetcher.update(window, targetSize: feedTargetSize, in: library)
    }

    @ViewBuilder
    private func itemView(_ item: SortingSession.Item) -> some View {
        switch item {
        case .photo(let asset):
            FeedPhotoCell(
                asset: asset,
                library: library,
                leftVisual: visual(for: gestures.feedLeft),
                rightVisual: visual(for: gestures.feedRight),
                onLike: { toggleFavorite(asset) },
                onSwipe: { right in handleSwipe(rightDirection: right, on: asset) }
            )
        case .ad(let n):
            NativeAdSlot(slot: n)
        }
    }

    private func visual(for action: GestureSettings.Action) -> SwipeVisual {
        switch action {
        case .keep:   return SwipeVisual(icon: "heart.fill", tint: Palette.primary, isActive: true)
        case .delete: return SwipeVisual(icon: "trash.fill", tint: Palette.error, isActive: true)
        case .folder: return SwipeVisual(icon: "folder.fill", tint: Palette.tertiary, isActive: true)
        case .none:   return SwipeVisual(icon: "", tint: Palette.outline, isActive: false)
        }
    }

    // MARK: - Boutons fixes

    private var currentAsset: PHAsset? {
        guard let id = scrolledID, let idx = session.itemIndex(ofID: id) else {
            return session.currentAsset
        }
        return session.items[idx].asset
    }

    private func feedControls(for asset: PHAsset) -> some View {
        let isFav = session.isFavorite(asset)
        // Floating Liquid Glass cluster (iOS 26+) — morphs as one surface.
        return GlassGroup(spacing: Spacing.gutter) {
            VStack(spacing: Spacing.gutter) {
                controlButton(isFav ? "heart.fill" : "heart", tint: isFav ? Palette.error : Palette.onSurface) {
                    toggleFavorite(asset)
                }
                controlButton("trash", tint: Palette.error) {
                    performFeed(.delete, on: asset)
                }
                ForEach(gestures.shortcuts) { s in
                    controlButton("folder.fill", tint: Palette.tertiary) {
                        performFeed(.folder(s.id), on: asset)
                    }
                }
            }
        }
        .padding(.trailing, Spacing.stackMd)
        .padding(.bottom, 110)
    }

    private func controlButton(_ icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .glassCircle(diameter: 52)
        }
        .buttonStyle(.squish)
    }

    // MARK: - Curseur partagé

    private func syncCursor(to id: String?) {
        guard let id, let idx = session.itemIndex(ofID: id) else { return }
        session.index = idx
    }

    private func advanceToNext(after asset: PHAsset, delay: TimeInterval) {
        guard let bi = session.itemIndex(ofID: asset.localIdentifier) else { return }
        let next = bi + 1
        guard session.items.indices.contains(next) else { return }
        let nextID = session.items[next].id
        let go = { withAnimation(.easeInOut(duration: 0.35)) { scrolledID = nextID } }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: go)
        } else {
            go()
        }
    }

    // MARK: - Crédits & décisions

    private func handleAppear(_ item: SortingSession.Item) {
        guard case .photo(let asset) = item else { return }
        let id = asset.localIdentifier
        guard !creditedIDs.contains(id) else { return }
        if session.decision(for: asset) != nil { creditedIDs.insert(id); return }
        if creditedIDs.isEmpty { creditedIDs.insert(id); return }

        guard credits.canSwipe(isUnlimited: isUnlimited) else { onOutOfCredits(); return }
        credits.consume(isUnlimited: isUnlimited)
        creditedIDs.insert(id)
        if !isUnlimited && credits.remaining == 0 { onOutOfCredits() }
    }

    private func handleDisappear(_ item: SortingSession.Item) {
        guard case .photo(let asset) = item else { return }
        // Vue puis quittée sans décision → considérée gardée (triée).
        if session.decision(for: asset) == nil {
            session.recordKeep(asset)
        }
    }

    private func toggleFavorite(_ asset: PHAsset) {
        let nowFavorite = session.toggleFavoriteState(asset)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { try? await library.toggleFavorite(asset) }
        if nowFavorite {
            session.recordKeep(asset)
            advanceToNext(after: asset, delay: 0.35)
        }
    }

    /// Geste horizontal : action de la direction (configurable, premium).
    private func handleSwipe(rightDirection: Bool, on asset: PHAsset) {
        performFeed(rightDirection ? gestures.feedRight : gestures.feedLeft, on: asset)
    }

    /// Enregistre la décision (batchée) et passe à la suivante. Pas de crédit
    /// consommé ici (déjà compté à l'apparition de la photo).
    private func performFeed(_ action: GestureSettings.Action, on asset: PHAsset) {
        switch action {
        case .none:
            return
        case .keep:
            session.recordKeep(asset)
        case .delete:
            session.recordDelete(asset)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .folder(let id):
            session.recordFile(asset, albumID: id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        advanceToNext(after: asset, delay: 0.25)
    }
}

/// Une cellule plein écran du flux.
private struct FeedPhotoCell: View {
    let asset: PHAsset
    let library: PhotoLibrary
    let leftVisual: SwipeVisual
    let rightVisual: SwipeVisual
    let onLike: () -> Void
    let onSwipe: (_ rightDirection: Bool) -> Void

    @State private var image: UIImage?
    @State private var dragX: CGFloat = 0
    /// Direction du swipe en cours, verrouillée dès le début du geste : le ressort
    /// de relâchement peut faire osciller `dragX` autour de 0, mais le halo ne doit
    /// pas changer de bord ni de couleur pendant cette animation.
    @State private var dirRight = true
    @State private var heartBurst = false
    @State private var didCrossThreshold = false

    private let threshold: CGFloat = 220
    private var progress: CGFloat { min(1, abs(dragX) / threshold) }
    private var activeVisual: SwipeVisual { dirRight ? rightVisual : leftVisual }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // La photo reste fixe (paging vertical façon TikTok) : le geste
                // horizontal ne la déplace pas, seul le halo réagit au swipe.
                Color.black
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ProgressView().tint(.white)
                }
                if heartBurst { heartOverlay }

                // Halo lumineux glissé au-dessus de la photo, du côté du swipe.
                swipeHalo(in: geo.size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(swipeGesture)
            .onTapGesture(count: 2) { likeWithBurst() }
            .task(id: asset.localIdentifier) {
                let scale = UIScreen.main.scale
                image = await library.image(
                    for: asset,
                    targetSize: CGSize(width: geo.size.width * scale,
                                       height: geo.size.height * scale))
            }
        }
    }

    private var heartOverlay: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 110))
            .foregroundStyle(.pink)
            .shadow(radius: 12)
            .transition(.scale.combined(with: .opacity))
    }

    /// Halo lumineux dévoilé par le swipe : une lueur colorée irradie depuis le
    /// bord *opposé* à la direction du geste (glisser vers la droite → halo à
    /// gauche, comme la maquette), teintée par l'action de cette direction.
    /// Intensité, cœur blanc « shine » et icône grandissent avec la progression ;
    /// la photo est légèrement assombrie pour faire ressortir le halo.
    @ViewBuilder
    private func swipeHalo(in size: CGSize) -> some View {
        let v = activeVisual
        let p = Double(progress)
        // Glisser vers la droite (dirRight) → halo sur le bord gauche.
        let onLeft = dirRight
        // Les couches de lueur débordent l'écran de `bleed` pt de chaque côté :
        // le flou dispose ainsi de vraie couleur au-delà du bord visible (sinon il
        // se fond vers le transparent et laisse un liseré). `.clipped()` (sur la
        // cellule) rogne le débordement. Le centre, calé au bord de la couche
        // élargie, est donc physiquement hors écran → lumière venue de l'extérieur.
        let bleed: CGFloat = 70
        let edge: UnitPoint = onLeft ? .leading : .trailing

        ZStack {
            // 1. Assombrit doucement la photo pour faire « pop » le halo.
            Color.black.opacity(0.30 * p)

            // 2. Lueur colorée + cœur blanc, débordant les bords de l'écran.
            ZStack {
                EllipticalGradient(
                    colors: [v.tint.opacity(0.95), v.tint.opacity(0.40), .clear],
                    center: edge,
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.55 + 0.24 * p)
                    .blur(radius: 14)

                RadialGradient(
                    colors: [.white.opacity(0.55 * p), .clear],
                    center: edge,
                    startRadius: 0,
                    endRadius: size.width * 0.5)
                    .blendMode(.screen)
                    .blur(radius: 6)
            }
            .padding(.horizontal, -bleed)

            // 4. Icône d'action près du bord, avec une aura colorée.
            Image(systemName: v.icon)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: v.tint.opacity(0.9), radius: 12)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                .scaleEffect(0.7 + 0.4 * p)
                .frame(maxWidth: .infinity, alignment: onLeft ? .leading : .trailing)
                .padding(onLeft ? .leading : .trailing, 30)
                .opacity(p > 0.05 ? 1 : 0)
        }
        .frame(width: size.width, height: size.height)
        // Présence globale pilotée par la progression : 0 au repos, pleine vers le
        // seuil. Suit le ressort de relâchement → fondu propre, sans saut de bord.
        .opacity(v.isActive ? min(1, p * 1.7) : 0)
        .allowsHitTesting(false)
    }

    private func likeWithBurst() {
        onLike()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { heartBurst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.2)) { heartBurst = false }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                // Verrouille la direction sur le signe (stable) du déplacement du
                // doigt, avant de lire `activeVisual` qui en dépend.
                dirRight = value.translation.width > 0
                dragX = value.translation.width
                let crossed = abs(dragX) >= threshold && activeVisual.isActive
                if crossed && !didCrossThreshold {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    didCrossThreshold = true
                } else if !crossed {
                    didCrossThreshold = false
                }
            }
            .onEnded { _ in
                if progress >= 1 && activeVisual.isActive {
                    onSwipe(dirRight)
                }
                didCrossThreshold = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragX = 0 }
            }
    }
}
