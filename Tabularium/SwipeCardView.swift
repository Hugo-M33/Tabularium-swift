import SwiftUI
import Photos

/// Une carte photo qu'on peut faire glisser à gauche (supprimer) ou à droite (garder).
struct SwipeCardView: View {
    let asset: PHAsset
    let library: PhotoLibrary
    let onSwipe: (_ keep: Bool) -> Void

    @State private var image: UIImage?
    @State private var translation: CGSize = .zero
    @State private var isRemoving = false

    /// Seuil de validation du swipe.
    private let threshold: CGFloat = 110

    var body: some View {
        GeometryReader { geo in
            ZStack {
                cardBackground
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.secondary)
                }

                // Étiquettes GARDER / SUPPRIMER qui apparaissent au swipe.
                decisionLabels
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: Palette.primary.opacity(0.12), radius: 24, y: 12)
            .offset(translation)
            .rotationEffect(.degrees(Double(translation.width / 18)))
            .gesture(dragGesture(in: geo.size))
            .task(id: asset.localIdentifier) {
                let scale = UIScreen.main.scale
                let size = CGSize(width: geo.size.width * scale,
                                  height: geo.size.height * scale)
                image = await library.image(for: asset, targetSize: size)
            }
        }
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
