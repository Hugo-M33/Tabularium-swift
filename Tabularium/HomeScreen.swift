import Photos
import SwiftUI

/// Écran d'accueil façon galerie iPhone : en-tête de stats + grille d'albums.
/// Gratuit : seul le dossier « Aléatoire » est jouable ; les albums réels sont
/// verrouillés (premium). Pousse `SorterScreen` sur la source choisie.
struct HomeScreen: View {
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var session: SortingSession
    @EnvironmentObject private var subscription: SubscriptionStore
    @EnvironmentObject private var credits: SwipeCreditsStore
    @EnvironmentObject private var reclaimed: ReclaimedSpaceStore
    @EnvironmentObject private var consent: ConsentManager

    @StateObject private var ads = RewardedAdManager()

    @State private var albums: [PhotoLibrary.Album] = []
    @State private var path: [SortingSession.Source] = []
    @State private var showPaywall = false
    @State private var showOutOfSwipes = false
    @State private var showSettings = false

    private var isUnlimited: Bool { subscription.isUnlimited }

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch library.status {
                case .authorized, .limited:
                    grid
                case .denied, .restricted:
                    permissionDenied
                default:
                    ProgressView("loading")
                }
            }
            .navigationTitle("home.title")
            .navigationDestination(for: SortingSession.Source.self) { _ in
                SorterScreen()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !isUnlimited {
                        Button { showPaywall = true } label: {
                            Label("premium", systemImage: "crown.fill")
                        }
                        .tint(Palette.gold)
                    } else {
                        Label("status.unlimited", systemImage: "infinity")
                            .foregroundStyle(Palette.primary)
                    }
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showSettings) { SettingsScreen() }
            .alert("alert.outofswipes.title", isPresented: $showOutOfSwipes) {
                // Pub récompensée proposée seulement si le consentement autorise
                // les pubs — sinon le bouton ne ferait rien.
                if consent.canRequestAds {
                    Button("alert.outofswipes.watchad") { watchAd() }
                }
                Button("alert.outofswipes.gounlimited") { showPaywall = true }
                Button("common.later", role: .cancel) { }
            } message: {
                Text("alert.outofswipes.message")
            }
            .task {
                if library.status == .notDetermined { await library.requestAccess() }
                await reload()
                if consent.canRequestAds { ads.load() }
            }
            .onChange(of: consent.canRequestAds) { _, allowed in
                // Le consentement peut arriver après le lancement (formulaire UMP) :
                // on précharge alors la pub récompensée.
                if allowed { ads.load() }
            }
            .onChange(of: path) { _, newPath in
                // De retour à l'accueil : recompte les stats.
                if newPath.isEmpty { Task { await reload() } }
            }
        }
    }

    // MARK: - Grille

    private var grid: some View {
        ScrollView {
            VStack(spacing: Spacing.stackMd) {
                statsHeader
                randomCard

                SectionHeader("home.choosepile")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.base)

                LazyVGrid(columns: columns, spacing: Spacing.gutter) {
                    ForEach(albums) { album in
                        albumCard(album)
                    }
                }
            }
            .padding(.horizontal, Spacing.marginMain)
            .padding(.top, Spacing.base)
            .padding(.bottom, Spacing.stackLg)
        }
        .background(Palette.surface)
    }

    private var statsHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.gutter) {
            SectionHeader("home.stats.title")

            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(session.sortedCount)")
                    .textStyle(.display)
                    .foregroundStyle(Palette.onSurface)
                Text(verbatim: "/ \(session.totalCount)")
                    .textStyle(.bodySM)
                    .foregroundStyle(Palette.onSurfaceVariant)
                Spacer()
                Text(verbatim: "\(Int(session.progress * 100)) %")
                    .textStyle(.headlineMD)
                    .foregroundStyle(Palette.primary)
                    .monospacedDigit()
            }

            ProgressView(value: session.progress)
                .tint(Palette.primary)

            Text("home.stats.detail.\(session.sortedCount).\(session.totalCount)")
                .textStyle(.bodySM)
                .foregroundStyle(Palette.onSurfaceVariant)
                .monospacedDigit()

            if reclaimed.stats.photos > 0 {
                Label {
                    Text("home.stats.freed.\(reclaimed.totalDisplay).\(reclaimed.stats.photos)")
                        .textStyle(.labelCaps)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "internaldrive.fill")
                }
                .foregroundStyle(Palette.primary)
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.base)
                .background(Palette.halo, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var randomCard: some View {
        Button { startRandom() } label: {
            ZStack(alignment: .leading) {
                Palette.primaryGradient
                VStack(alignment: .leading, spacing: Spacing.stackSm) {
                    Image(systemName: "dice.fill")
                        .font(.system(size: 32, weight: .bold))
                        .padding(.bottom, Spacing.stackSm)
                    Text("home.random.title")
                        .textStyle(.headlineMD)
                    Text("home.random.subtitle")
                        .textStyle(.bodySM)
                        .opacity(0.9)
                }
                .foregroundStyle(Palette.onPrimary)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
            .frame(height: 148)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .shadow(color: Palette.primary.opacity(0.25), radius: 16, y: 6)
        }
        .buttonStyle(.squish)
    }

    private func albumCard(_ album: PhotoLibrary.Album) -> some View {
        Button { startAlbum(album) } label: {
            ZStack(alignment: .bottomLeading) {
                AlbumThumbnail(asset: album.cover, library: library)
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .clipped()

                LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.55)],
                               startPoint: .center, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(album.count)")
                        .textStyle(.labelCaps)
                        .opacity(0.9)
                    Text(album.title)
                        .textStyle(.bodyEmph)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 20)

                if !isUnlimited {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.tertiary)
                        .padding(Spacing.base)
                        .background(.ultraThinMaterial, in: Circle())
                        // Décalé du coin pour ne pas être rogné par l'arrondi (28pt).
                        .padding(.top, 14)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .shadow(color: Palette.primary.opacity(0.06), radius: 20, y: 4)
        }
        .buttonStyle(.squish)
    }

    private var permissionDenied: some View {
        ContentUnavailableView {
            Label("permission.title", systemImage: "lock.fill")
        } description: {
            Text("permission.description")
        } actions: {
            Button("permission.opensettings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.primaryCTA(fullWidth: false))
        }
    }

    // MARK: - Actions

    private func reload() async {
        guard library.status == .authorized || library.status == .limited else { return }
        // Recompte sur les photos réellement présentes et élague les triées
        // obsolètes → stats cohérentes (sorted ≤ total).
        let ids = library.allImageIDs()
        session.pruneSorted(existing: ids)
        session.updateTotalCount(ids.count)
        albums = library.fetchAlbums()
    }

    private func startRandom() {
        // Gratuit sans crédit : on propose pub / premium.
        if !isUnlimited && credits.remaining == 0 {
            showOutOfSwipes = true
            return
        }
        let batch = library.batch(for: .random, excluding: session.sortedIDs, limit: 100)
        guard !batch.isEmpty else { return }
        // Pas de slot de pub native sans consentement (sinon placeholder vide) :
        // l'intervalle reste nil tant que les pubs ne sont pas autorisées.
        session.start(batch, source: .random, totalCount: library.totalImageCount,
                      adInterval: (isUnlimited || !consent.canRequestAds) ? nil : 20)
        path.append(.random)
    }

    private func startAlbum(_ album: PhotoLibrary.Album) {
        guard isUnlimited else { showPaywall = true; return }
        let source = SortingSession.Source.album(id: album.id, title: album.title)
        let batch = library.batch(for: source, excluding: session.sortedIDs, limit: 100)
        guard !batch.isEmpty else { return }
        session.start(batch, source: source, totalCount: library.totalImageCount,
                      adInterval: isUnlimited ? nil : 20)
        path.append(source)
    }

    private func watchAd() {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        ads.show(from: root) { credits.grantAdReward() }
    }
}

/// Vignette de couverture d'un album (chargée via PhotoKit).
private struct AlbumThumbnail: View {
    let asset: PHAsset?
    let library: PhotoLibrary
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Palette.surfaceContainer
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(Palette.outline)
            }
        }
        .task(id: asset?.localIdentifier) {
            guard let asset else { return }
            image = await library.image(for: asset,
                                        targetSize: CGSize(width: 600, height: 600))
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}
