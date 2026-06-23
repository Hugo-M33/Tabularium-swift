import Photos
import SwiftUI

/// Écran de tri d'un batch, poussé depuis l'accueil.
/// Deux affichages d'un **même** contexte (`SortingSession`) : cartes ou flux.
struct SorterScreen: View {
    @EnvironmentObject private var session: SortingSession
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var credits: SwipeCreditsStore
    @EnvironmentObject private var subscription: SubscriptionStore
    @EnvironmentObject private var gestures: GestureSettings
    @EnvironmentObject private var reclaimed: ReclaimedSpaceStore
    @EnvironmentObject private var consent: ConsentManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var ads = RewardedAdManager()

    @State private var showPaywall = false
    @State private var showReview = false
    @State private var reviewOutOfSwipes = false
    @State private var deleteError: String?
    @State private var mode: SwipeMode = .cards

    @StateObject private var prefetcher = ImagePrefetcher()
    /// Taille réelle d'une carte (mesurée), base de la taille cible du cache.
    @State private var cardSize: CGSize = .zero
    /// Texte du toast « espace libéré » après un commit (nil = masqué).
    @State private var freedToast: String?

    /// Photos en aval à garder chaudes en cache (≥ curr+10).
    private let prefetchAhead = 12
    private let prefetchBehind = 2

    private var isUnlimited: Bool { subscription.isUnlimited }

    /// Taille cible plein-carte (en pixels) — identique aux requêtes de `SwipeCardView`.
    private var cardTargetSize: CGSize {
        let scale = UIScreen.main.scale
        return CGSize(width: cardSize.width * scale, height: cardSize.height * scale)
    }

    /// Met à jour le préchargement des cartes (curseur = `session.index`).
    private func prefetchCards() {
        guard mode == .cards else { return }
        let window = session.prefetchWindow(around: session.index,
                                            ahead: prefetchAhead, behind: prefetchBehind)
        prefetcher.update(window, targetSize: cardTargetSize, in: library)
    }

    enum SwipeMode: String, CaseIterable {
        case cards, feed
        var label: LocalizedStringKey {
            switch self {
            case .cards: return "mode.cards"
            case .feed:  return "mode.feed"
            }
        }
    }

    var body: some View {
        ZStack {
            Palette.surface.ignoresSafeArea()
            content
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Dans un dossier, on remplace le bouton retour système (qui afficherait
        // « Tri photo ») par un bouton retour personnalisé portant le nom du
        // dossier — voir `toolbarContent`.
        .navigationBarBackButtonHidden(isAlbumSource)
        .toolbar { toolbarContent }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("mode.picker", selection: $mode) {
                    ForEach(SwipeMode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if mode != .feed { bottomBar }
        }
        .overlay(alignment: .bottom) {
            if mode == .feed { bottomBar }
        }
        .overlay(alignment: .top) {
            if let freedToast { freedToastView(freedToast) }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showReview) {
            ReviewScreen(outOfSwipes: reviewOutOfSwipes,
                         // onWatchAd nil (bouton masqué) si pas de consentement pub.
                         resetDate: credits.nextReset,
                         onWatchAd: (isUnlimited || !consent.canRequestAds) ? nil : { watchAdFromReview() }) {
                await commitChanges()
            }
        }
        .task { if consent.canRequestAds { ads.load() } }
        .onChange(of: consent.canRequestAds) { _, allowed in
            if allowed { ads.load() }
        }
        .onChange(of: session.index) { _, _ in prefetchCards() }
        .onChange(of: cardSize) { _, _ in prefetchCards() }
        .onChange(of: session.items.count) { _, _ in prefetchCards() }
        .onChange(of: mode) { _, m in
            if m == .cards { prefetchCards() } else { prefetcher.reset(in: library) }
        }
        .onDisappear { prefetcher.reset(in: library) }
        .onChange(of: session.isFinished) { _, finished in
            // Premium : enchaîne automatiquement sur 100 nouvelles photos.
            if finished && isUnlimited { loadNextBatch() }
        }
        .alert("alert.error.title", isPresented: .constant(deleteError != nil)) {
            Button("common.ok") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    private var navTitle: String {
        if let source = session.source, source.isAlbum { return source.title }
        return NSLocalizedString("nav.title", comment: "")
    }

    /// Vrai quand la source de tri est un dossier/album (titre = nom du dossier).
    private var isAlbumSource: Bool { session.source?.isAlbum == true }

    // MARK: - Contenu

    @ViewBuilder
    private var content: some View {
        if session.items.isEmpty {
            ContentUnavailableView("empty.title",
                systemImage: "photo.on.rectangle",
                description: Text("empty.description"))
        } else if mode == .feed {
            FeedScreen(showPaywall: $showPaywall,
                       onOutOfCredits: { presentOutOfSwipes() })
        } else if session.isFinished {
            finishedView
        } else {
            cardStack
        }
    }

    private struct CardEntry: Identifiable {
        let item: SortingSession.Item
        let isTop: Bool
        var id: String { item.id }
    }

    /// Élément actif + aperçu du suivant. L'identité (`id`) est conservée d'un
    /// swipe à l'autre : la carte « suivante » devient « active » sans recharger
    /// son image (pas de clignotement), en animant échelle et opacité.
    private var visibleCards: [CardEntry] {
        var cards: [CardEntry] = []
        let nextIdx = session.index + 1
        if session.items.indices.contains(nextIdx) {
            cards.append(CardEntry(item: session.items[nextIdx], isTop: false))
        }
        if let current = session.currentItem {
            cards.append(CardEntry(item: current, isTop: true))
        }
        return cards
    }

    /// Léger angle d'inclinaison (-4°…+4°) appliqué aux cartes en arrière-plan
    /// pour conserver l'effet de pile maintenant que les cartes épousent la forme
    /// de la photo. Dérivé de façon déterministe de l'`id` (et non d'un hash aléatoire
    /// resemé à chaque lancement) pour rester stable d'un rendu à l'autre.
    private func tiltAngle(for id: String) -> Double {
        let hash = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        return Double(hash % 9) - 4
    }

    private var cardStack: some View {
        VStack(spacing: 0) {
            ZStack {
                ForEach(visibleCards) { entry in
                    cardView(for: entry)
                        .scaleEffect(entry.isTop ? 1 : 0.94)
                        .opacity(entry.isTop ? 1 : 0.6)
                        .rotationEffect(.degrees(entry.isTop ? 0 : tiltAngle(for: entry.id)))
                        .allowsHitTesting(entry.isTop)
                        .animation(.easeOut(duration: 0.22), value: entry.isTop)
                }
            }
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { cardSize = g.size }
                        .onChange(of: g.size) { _, s in cardSize = s }
                }
            )
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // Pub : bouton « Continuer » ; photo : boutons garder/supprimer.
            if session.currentItem?.isAd == true {
                continueButton.padding(.top, 20)
            } else {
                actionButtons.padding(.top, 20)
            }
        }
    }

    @ViewBuilder
    private func cardView(for entry: CardEntry) -> some View {
        switch entry.item {
        case .photo(let asset):
            SwipeCardView(asset: asset, library: library) { right in
                if entry.isTop { performCardSwipe(rightDirection: right) }
            }
        case .ad(let n):
            NativeAdSlot(slot: n, card: true)
        }
    }

    private var continueButton: some View {
        Button { session.advance() } label: {
            Label("ad.continue", systemImage: "chevron.right.circle.fill")
        }
        .buttonStyle(.primaryCTA(fullWidth: false))
        .padding(.bottom, Spacing.base)
    }

    private var actionButtons: some View {
        let hasShortcuts = !gestures.shortcuts.isEmpty
        let size: CGFloat = hasShortcuts ? 54 : 64
        return HStack(spacing: hasShortcuts ? 14 : 48) {
            roundButton("xmark", kind: .destructive, size: size) { performButton(.delete) }
            ForEach(gestures.shortcuts) { s in
                roundButton("folder.fill", kind: .neutral, size: size) { performButton(.folder(s.id)) }
            }
            roundButton("heart.fill", kind: .affirmative, size: size) { performButton(.keep) }
        }
        .padding(.bottom, Spacing.base)
    }

    /// Style des trois boutons d'action sous la carte (cf. design « cards mode »).
    private enum RoundButtonKind { case destructive, neutral, affirmative }

    /// Toast transitoire « espace libéré » affiché après un commit.
    private func freedToastView(_ text: String) -> some View {
        Label {
            Text("toast.freed.\(text)")
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
        .textStyle(.bodyEmph)
        .foregroundStyle(Palette.onPrimary)
        .padding(.horizontal, Spacing.stackMd)
        .padding(.vertical, Spacing.gutter)
        .background(Palette.primaryGradient, in: Capsule())
        .shadow(color: Palette.primary.opacity(0.3), radius: 8, y: 3)
        .padding(.top, Spacing.base)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private func roundButton(_ icon: String, kind: RoundButtonKind, size: CGFloat,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                switch kind {
                case .affirmative:
                    Image(systemName: icon)
                        .foregroundStyle(Palette.onPrimary)
                        .frame(width: size, height: size)
                        .background(Palette.primaryGradient, in: Circle())
                        .shadow(color: Palette.primary.opacity(0.3), radius: 10, y: 4)
                case .destructive:
                    Image(systemName: icon)
                        .foregroundStyle(Palette.error)
                        .frame(width: size, height: size)
                        .background(Palette.surfaceContainerLowest, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.error.opacity(0.4), lineWidth: 1.5))
                        .shadow(color: Palette.onSurface.opacity(0.08), radius: 8, y: 4)
                case .neutral:
                    Image(systemName: icon)
                        .foregroundStyle(Palette.amber)
                        .frame(width: size, height: size)
                        .background(Palette.halo, in: Circle())
                        .shadow(color: Palette.onSurface.opacity(0.08), radius: 8, y: 4)
                }
            }
            .font(.title2.weight(.bold))
        }
        .buttonStyle(.squish)
    }

    private var finishedView: some View {
        ContentUnavailableView {
            Label("finished.title", systemImage: "checkmark.circle.fill")
        } description: {
            Text("finished.batchsummary.\(session.sortedCount).\(Int(session.progress * 100))")
        } actions: {
            if session.pendingActionCount > 0 {
                Button {
                    reviewOutOfSwipes = false
                    showReview = true
                } label: {
                    Text("review.open.\(session.pendingActionCount)")
                }
                .buttonStyle(.borderedProminent)
            }
            Button("finished.backhome") { dismiss() }
                .buttonStyle(.bordered)
        }
    }

    // MARK: - Barres

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isAlbumSource {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Label(navTitle, systemImage: "chevron.backward")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            if isUnlimited {
                Label("status.unlimited", systemImage: "infinity")
                    .font(.app(.bodySM))
                    .foregroundStyle(Palette.primary)
            } else {
                Label {
                    Text("status.swipes.\(credits.remaining)")
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "bolt.fill")
                }
                .font(.app(.bodyEmph))
                .foregroundStyle(credits.remaining <= 10 ? Palette.error : Palette.primary)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !isUnlimited {
                Button { showPaywall = true } label: {
                    Label("premium", systemImage: "crown.fill")
                }
                .tint(Palette.gold)
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if session.pendingActionCount > 0 {
            Button {
                reviewOutOfSwipes = false
                showReview = true
            } label: {
                Label {
                    Text("review.open.\(session.pendingActionCount)")
                } icon: {
                    Image(systemName: "tray.full")
                }
            }
            .buttonStyle(.primaryCTA)
            .padding(.horizontal, Spacing.marginMain)
            .padding(.bottom, Spacing.base)
        }
    }

    // MARK: - Logique

    /// Swipe de carte : action de la direction (configurable), repli sur
    /// garder/supprimer si la direction n'a pas d'action assignée.
    private func performCardSwipe(rightDirection: Bool) {
        guard let asset = session.currentAsset else { return }
        let configured = rightDirection ? gestures.cardsRight : gestures.cardsLeft
        let action: GestureSettings.Action = (configured == .none)
            ? (rightDirection ? .keep : .delete) : configured
        guard performAction(action, on: asset) else { return }
        session.advance()
        if !isUnlimited && credits.remaining == 0 && !session.isFinished {
            presentOutOfSwipes()
        }
    }

    /// Bouton d'action (✕ / dossier / ♥) sous la carte.
    private func performButton(_ action: GestureSettings.Action) {
        guard let asset = session.currentAsset else { return }
        guard performAction(action, on: asset) else { return }
        session.advance()
        if !isUnlimited && credits.remaining == 0 && !session.isFinished {
            presentOutOfSwipes()
        }
    }

    /// Applique (en différé) une décision sur la photo et consomme un crédit.
    /// Retourne `false` si rien n'a été fait (action `.none` ou plus de crédit).
    @discardableResult
    private func performAction(_ action: GestureSettings.Action, on asset: PHAsset) -> Bool {
        guard action != .none else { return false }
        guard credits.canSwipe(isUnlimited: isUnlimited) else {
            presentOutOfSwipes()
            return false
        }
        credits.consume(isUnlimited: isUnlimited)
        switch action {
        case .keep: session.recordKeep(asset)
        case .delete: session.recordDelete(asset)
        case .folder(let id): session.recordFile(asset, albumID: id)
        case .none: break
        }
        return true
    }

    /// Ouvre l'écran de revue (commit) avec le bandeau « plus de swipes ».
    private func presentOutOfSwipes() {
        reviewOutOfSwipes = true
        showReview = true
    }

    /// Premium : recharge un nouveau lot depuis la même source.
    private func loadNextBatch() {
        guard let source = session.source else { return }
        let next = library.batch(for: source, excluding: session.sortedIDs, limit: 100)
        guard !next.isEmpty else { return }   // plus rien à trier : on garde l'écran « terminé ».
        session.start(next, source: source, totalCount: library.totalImageCount,
                      adInterval: isUnlimited ? nil : 20)
    }

    /// Pub récompensée depuis le bandeau de la revue : recrédite puis ferme la
    /// feuille pour reprendre le tri.
    private func watchAdFromReview() {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        ads.show(from: root) {
            credits.grantAdReward()
            showReview = false
        }
    }

    /// Applique les décisions batchées : classements (ajout aux albums) puis
    /// suppressions (alerte système iOS), et retire les photos traitées du batch.
    private func commitChanges() async {
        var committed = Set<String>()

        // Classements (sans alerte système).
        for albumID in session.filedAlbumIDs {
            for asset in session.filedAssets(albumID: albumID) {
                do {
                    try await library.addAsset(asset, toAlbumID: albumID)
                    committed.insert(asset.localIdentifier)
                } catch {
                    // On ignore ce classement, on continue les autres.
                }
            }
        }

        // Suppressions (l'utilisateur confirme via l'alerte système).
        let toDelete = session.pendingDeleteAssets
        if !toDelete.isEmpty {
            // Taille mesurée AVANT suppression (asset ininterrogeable après).
            let freedBytes = library.byteSize(of: toDelete)
            do {
                try await library.deleteAssets(toDelete)
                committed.formUnion(toDelete.map(\.localIdentifier))
                // Comptabilisé uniquement si la suppression a réellement eu lieu.
                await reclaimed.record(bytes: freedBytes, photos: toDelete.count)
                presentFreedToast(bytes: freedBytes)
            } catch {
                deleteError = error.localizedDescription
            }
        }

        session.clearCommitted(committed)
    }

    /// Affiche le toast d'espace libéré quelques secondes.
    private func presentFreedToast(bytes: Int64) {
        guard bytes > 0 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            freedToast = reclaimed.display(bytes)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.3)) { freedToast = nil }
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}
