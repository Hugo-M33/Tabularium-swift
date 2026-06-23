import SwiftUI
import Photos

/// Une carte photo qu'on peut faire glisser à gauche (supprimer) ou à droite (garder).
struct SwipeCardView: View {
    let asset: PHAsset
    let library: PhotoLibrary
    let onSwipe: (_ keep: Bool) -> Void

    @State private var image: UIImage?
    @State private var translation: CGSize = .zero

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
            .rotationEffect(.degrees(Double(translation.width / 18)))
            .gesture(dragGesture(in: geo.size))
            .task(id: asset.localIdentifier) {
                let scale = UIScreen.main.scale
                let size = CGSize(width: card.width * scale, height: card.height * scale)
                image = await library.image(for: asset, targetSize: size)
            }
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
        ZStack {
            label(text: "card.keep", color: Palette.primary, systemImage: "heart.fill")
                .opacity(Double(max(0, translation.width) / threshold))
                .rotationEffect(.degrees(-12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Spacing.stackLg)

            label(text: "card.delete", color: Palette.error, systemImage: "trash.fill")
                .opacity(Double(max(0, -translation.width) / threshold))
                .rotationEffect(.degrees(12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(Spacing.stackLg)
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
                let w = value.translation.width
                if abs(w) > threshold {
                    let keep = w > 0
                    let endX = (keep ? 1.5 : -1.5) * size.width
                    withAnimation(.easeOut(duration: 0.28)) {
                        translation = CGSize(width: endX, height: value.translation.height)
                    }
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        onSwipe(keep)
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        translation = .zero
                    }
                }
            }
    }
}
