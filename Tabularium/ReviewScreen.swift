import Photos
import SwiftUI

/// Écran de revue/commit. Affiche les décisions batchées en groupes distincts :
/// à supprimer, à classer (un groupe par dossier), à garder. On peut déplacer une
/// photo d'un groupe à l'autre (appui long), puis valider — ce qui applique
/// réellement classements + suppressions (alerte système iOS pour ces dernières).
struct ReviewScreen: View {
    @EnvironmentObject private var session: SortingSession
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var gestures: GestureSettings
    @Environment(\.dismiss) private var dismiss

    var outOfSwipes: Bool = false
    var resetDate: Date? = nil
    var onWatchAd: (() -> Void)? = nil
    /// Validation : applique classements + suppressions côté écran appelant.
    let onConfirm: () async -> Void

    @State private var working = false
    @State private var showPaywall = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    /// Destination d'un groupe.
    private enum Dest: Hashable { case keep, delete, folder(String) }

    private func assets(for dest: Dest) -> [PHAsset] {
        switch dest {
        case .keep: return session.keptAssets
        case .delete: return session.pendingDeleteAssets
        case .folder(let id): return session.filedAssets(albumID: id)
        }
    }

    /// Groupes affichés (non vides), dans l'ordre : dossiers, suppression, garder.
    private var groups: [Dest] {
        var g: [Dest] = session.filedAlbumIDs.map { .folder($0) }
        if !session.pendingDeleteAssets.isEmpty { g.append(.delete) }
        if !session.keptAssets.isEmpty { g.append(.keep) }
        return g
    }

    /// Toutes les destinations possibles (pour déplacer une photo).
    private var allDests: [Dest] {
        [.keep, .delete] + gestures.shortcuts.map { .folder($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if outOfSwipes { outOfSwipesBanner }

                    Text("review.hint")
                        .textStyle(.bodySM)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .padding(.horizontal, Spacing.marginMain)

                    if groups.isEmpty {
                        Text("review.emptygroup")
                            .textStyle(.bodySM)
                            .foregroundStyle(Palette.onSurfaceVariant)
                            .padding(.horizontal, Spacing.marginMain)
                    } else {
                        ForEach(groups, id: \.self) { dest in
                            group(dest)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("review.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { confirmBar }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    // MARK: - Groupe

    @ViewBuilder
    private func group(_ dest: Dest) -> some View {
        let items = assets(for: dest)
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title(for: dest)) + Text(verbatim: " · \(items.count)")
            } icon: {
                Image(systemName: icon(for: dest))
            }
            .font(.app(.headlineMD))
            .foregroundStyle(tint(for: dest))
            .padding(.horizontal, Spacing.marginMain)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(items, id: \.localIdentifier) { asset in
                    AssetThumbnail(asset: asset, library: library)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: icon(for: dest))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white, tint(for: dest))
                                .padding(4)
                        }
                        .contextMenu {
                            ForEach(allDests.filter { $0 != dest }, id: \.self) { target in
                                Button {
                                    move(asset, to: target)
                                } label: {
                                    Label(title(for: target), systemImage: icon(for: target))
                                }
                            }
                        } preview: {
                            AssetPreview(asset: asset, library: library)
                        }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var confirmBar: some View {
        Button {
            working = true
            Task { await onConfirm(); working = false; dismiss() }
        } label: {
            Label {
                Text("review.apply.\(session.pendingActionCount)")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
        }
        .buttonStyle(.primaryCTA)
        .disabled(session.pendingActionCount == 0 || working)
        .padding(Spacing.stackMd)
        .background(.bar)
    }

    // MARK: - Bandeau plus de swipes

    private var outOfSwipesBanner: some View {
        VStack(alignment: .leading, spacing: Spacing.gutter) {
            Label("review.outofswipes.title", systemImage: "checklist")
                .font(.app(.headlineMD))
                .foregroundStyle(Palette.primary)
            Text("review.outofswipes.message")
                .textStyle(.bodySM)
                .foregroundStyle(Palette.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

            if let resetDate, resetDate > Date() {
                HStack(spacing: Spacing.base) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("review.outofswipes.reset")
                    Text(timerInterval: Date()...resetDate, countsDown: true)
                        .monospacedDigit()
                }
                .textStyle(.bodySM)
                .foregroundStyle(Palette.onSurface)
            }

            HStack(spacing: Spacing.gutter) {
                if onWatchAd != nil {
                    Button { onWatchAd?() } label: {
                        Label("alert.outofswipes.watchad", systemImage: "play.rectangle.fill")
                    }
                    .buttonStyle(.secondary)
                }
                Button { showPaywall = true } label: {
                    Label("alert.outofswipes.gounlimited", systemImage: "crown.fill")
                }
                .buttonStyle(.primaryCTA)
            }
            .padding(.top, Spacing.stackSm)
        }
        .padding(Spacing.stackMd)
        .background(Palette.halo,
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .padding(.horizontal, Spacing.marginMain)
        .padding(.top, Spacing.base)
    }

    // MARK: - Helpers

    private func move(_ asset: PHAsset, to dest: Dest) {
        withAnimation(.snappy) {
            switch dest {
            case .keep: session.recordKeep(asset)
            case .delete: session.recordDelete(asset)
            case .folder(let id): session.recordFile(asset, albumID: id)
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func title(for dest: Dest) -> String {
        switch dest {
        case .keep: return NSLocalizedString("review.keep", comment: "")
        case .delete: return NSLocalizedString("review.delete", comment: "")
        case .folder(let id): return gestures.title(forFolder: id)
            ?? NSLocalizedString("action.folder", comment: "")
        }
    }

    private func icon(for dest: Dest) -> String {
        switch dest {
        case .keep: return "heart.fill"
        case .delete: return "trash.fill"
        case .folder: return "folder.fill"
        }
    }

    private func tint(for dest: Dest) -> Color {
        switch dest {
        case .keep: return Palette.primary
        case .delete: return Palette.error
        case .folder: return Palette.tertiary
        }
    }
}

/// Grand aperçu d'une photo (affiché au long press dans le menu contextuel).
private struct AssetPreview: View {
    let asset: PHAsset
    let library: PhotoLibrary
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(width: 320, height: 460)
        .task(id: asset.localIdentifier) {
            image = await library.image(for: asset,
                                        targetSize: CGSize(width: 1400, height: 1400))
        }
    }
}

/// Vignette carrée d'une photo (chargée via PhotoKit).
private struct AssetThumbnail: View {
    let asset: PHAsset
    let library: PhotoLibrary
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Palette.surfaceContainer)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            .task(id: asset.localIdentifier) {
                image = await library.image(for: asset,
                                            targetSize: CGSize(width: 300, height: 300))
            }
    }
}
