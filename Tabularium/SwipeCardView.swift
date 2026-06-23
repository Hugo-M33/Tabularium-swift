import SwiftUI
import Photos

/// Une carte photo qu'on peut faire glisser à gauche (supprimer), à droite (garder)
/// ou vers le haut (favori « superlike »). Un tap simple demande un retour arrière.
struct SwipeCardView: View {
    let asset: PHAsset
    let library: PhotoLibrary
    let onSwipe: (_ direction: SwipeDirection) -> Void
    /// Tap simple sur la carte : revenir à la carte précédente.
    var onTapBack: () -> Void = {}
    /// Si défini, la carte **entre** en glissant depuis ce bord (animation de
    /// retour). `nil` = apparition normale (pas de glissement).
    var entryEdge: SwipeDirection? = nil

    @State private var image: UIImage?
    @State private var translation: CGSize = .zero
    /// Passe à `true` au premier affichage : déclenche le glissement d'entrée.
    @State private var entered = false

    /// Seuil de validation du swipe.
    private let threshold: CGFloat = 110

    /// Ratio largeur / hauteur de la photo, lu instantanément depuis l'asset
    /// (avant le chargement de l'image) pour dimensionner la carte sans
    /// recalcul ni clignotement. Repli 3:4 si l'asset n'expose pas ses dimensions.
    private var aspectRatio: CGFloat {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0 else { return 3.0 / 4.0 }
        return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    }

    var body: some View {
        GeometryReader { geo in
            // Carte à la forme exacte de la photo, centrée dans une zone de geste
            // plein cadre : on peut attraper et lancer la carte n'importe où, même
            // quand la photo est courte (paysage) ou étroite (portrait).
            let card = cardSize(in: geo.size)
            ZStack {
                Color.clear // zone de geste (transparente, plein cadre)
                photoCard
                    .frame(width: card.width, height: card.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .offset(translation)
            // Décalage d'entrée : la carte part hors écran depuis `entryEdge` puis
            // glisse jusqu'au centre (annulation). Sans `entryEdge`, reste à zéro.
            .offset(entered ? .zero : entryOffset(in: geo.size))
            .rotationEffect(.degrees(Double(translation.width / 18)))
            .gesture(dragGesture(in: geo.size))
            .onTapGesture { onTapBack() }
            .onAppear {
                guard !entered else { return }
                if entryEdge != nil {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { entered = true }
                } else {
                    entered = true
                }
            }
            .task(id: asset.localIdentifier) {
                let scale = UIScreen.main.scale
                let size = CGSize(width: card.width * scale, height: card.height * scale)
                image = await library.image(for: asset, targetSize: size)
            }
        }
    }

    /// Position hors écran de départ pour l'animation d'entrée, selon le bord.
    private func entryOffset(in size: CGSize) -> CGSize {
        switch entryEdge {
        case .left:  return CGSize(width: -1.6 * size.width, height: 0)
        case .right: return CGSize(width:  1.6 * size.width, height: 0)
        case .up:    return CGSize(width: 0, height: -1.6 * size.height)
        case .down:  return CGSize(width: 0, height:  1.6 * size.height)
        case nil:    return .zero
        }
    }

    /// Plus grand rectangle au ratio de la photo qui tient dans `bounds`.
    private func cardSize(in bounds: CGSize) -> CGSize {
        guard bounds.width > 0, bounds.height > 0 else { return bounds }
        let boundsRatio = bounds.width / bounds.height
        return aspectRatio > boundsRatio
            ? CGSize(width: bounds.width, height: bounds.width / aspectRatio)   // limitée par la largeur
            : CGSize(width: bounds.height * aspectRatio, height: bounds.height) // limitée par la hauteur
    }

    /// Carte arrondie à la forme de la photo : fond, image entière, bordure, ombre.
    private var photoCard: some View {
        ZStack {
            cardBackground
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.secondary)
            }
            // Étiquettes GARDER / SUPPRIMER qui apparaissent au swipe.
            decisionLabels
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: Palette.primary.opacity(0.12), radius: 24, y: 12)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Palette.surfaceContainer)
    }

    private var decisionLabels: some View {
        // L'axe dominant choisit l'étiquette : horizontal → garder/supprimer,
        // vertical (vers le haut) → favori. Évite que les libellés clignotent
        // ensemble pendant un swipe en diagonale.
        let horizontal = abs(translation.width) >= abs(translation.height)
        return ZStack {
            label(text: "card.keep", color: Palette.primary, systemImage: "heart.fill")
                .opacity(horizontal ? Double(max(0, translation.width) / threshold) : 0)
                .rotationEffect(.degrees(-12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Spacing.stackLg)

            label(text: "card.delete", color: Palette.error, systemImage: "trash.fill")
                .opacity(horizontal ? Double(max(0, -translation.width) / threshold) : 0)
                .rotationEffect(.degrees(12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(Spacing.stackLg)

            label(text: "card.favorite", color: Palette.gold, systemImage: "star.fill")
                .opacity(horizontal ? 0 : Double(max(0, -translation.height) / threshold))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, Spacing.stackLg)
        }
    }

    private func label(text: LocalizedStringKey, color: Color, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .textStyle(.bodyEmph)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.stackMd).padding(.vertical, Spacing.gutter)
            .background(color, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 2))
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in translation = value.translation }
            .onEnded { value in
                let t = value.translation
                let up = -t.height
                if up > threshold && up > abs(t.width) {
                    // Swipe vers le haut : favori. La carte s'envole par le haut.
                    withAnimation(.easeOut(duration: 0.28)) {
                        translation = CGSize(width: t.width, height: -1.5 * size.height)
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onSwipe(.up) }
                } else if abs(t.width) > threshold {
                    let right = t.width > 0
                    let endX = (right ? 1.5 : -1.5) * size.width
                    withAnimation(.easeOut(duration: 0.28)) {
                        translation = CGSize(width: endX, height: t.height)
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onSwipe(right ? .right : .left) }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        translation = .zero
                    }
                }
            }
    }
}
