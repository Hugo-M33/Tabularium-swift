import SwiftUI

/// Intro de premier lancement (rejouable depuis les Réglages). Explique le tri
/// par swipe, les deux modes et la revue/commit. Ne gère pas l'autorisation
/// photos (demandée par `HomeScreen`).
///
/// Habillé avec le design system « Organic Order » : en-tête cohérent sur
/// toutes les slides, indicateur de page unifié, typographie Plus Jakarta Sans.
struct OnboardingView: View {
    /// Appelé quand l'utilisateur termine ou passe l'intro.
    let onDone: () -> Void

    @State private var page = 0

    private struct Slide: Identifiable {
        let id = UUID()
        let icon: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    private let slides: [Slide] = [
        Slide(icon: "photo.stack",
              title: "onboarding.welcome.title", detail: "onboarding.welcome.detail"),
        Slide(icon: "hand.draw",
              title: "onboarding.swipe.title", detail: "onboarding.swipe.detail"),
        Slide(icon: "rectangle.grid.1x2",
              title: "onboarding.modes.title", detail: "onboarding.modes.detail"),
        Slide(icon: "internaldrive",
              title: "onboarding.review.title", detail: "onboarding.review.detail"),
    ]

    private var isLast: Bool { page == slides.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header

            TabView(selection: $page) {
                ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                    slideView(slide).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            PageIndicator(count: slides.count, index: page)
                .padding(.bottom, Spacing.stackLg)

            Button {
                if isLast { onDone() }
                else { withAnimation { page += 1 } }
            } label: {
                HStack(spacing: Spacing.base) {
                    Text(isLast ? "onboarding.start" : "onboarding.next")
                    if isLast { Image(systemName: "arrow.right") }
                }
            }
            .buttonStyle(.primaryCTA)
            .padding(.horizontal, Spacing.marginMain)
            .padding(.bottom, Spacing.stackLg)
        }
        .background(Palette.surface)
        .interactiveDismissDisabled()
    }

    // En-tête identique sur chaque slide : fermer (gauche), titre (centre),
    // passer (droite, masqué sur la dernière slide).
    private var header: some View {
        ZStack {
            Text("Tabularium")
                .textStyle(.headlineMD)
                .foregroundStyle(Palette.onSurface)

            HStack {
                Button { onDone() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.onSurfaceVariant)
                }
                Spacer()
                Button("onboarding.skip") { onDone() }
                    .textStyle(.bodySM)
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .opacity(isLast ? 0 : 1)
                    .disabled(isLast)
            }
        }
        .padding(.horizontal, Spacing.marginMain)
        .padding(.top, Spacing.stackMd)
    }

    private func slideView(_ slide: Slide) -> some View {
        VStack(spacing: Spacing.stackLg) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Palette.halo)
                    .frame(width: 160, height: 160)
                Image(systemName: slide.icon)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Palette.primary)
            }
            VStack(spacing: Spacing.gutter) {
                Text(slide.title)
                    .textStyle(.headlineLG)
                    .foregroundStyle(Palette.onSurface)
                    .multilineTextAlignment(.center)
                Text(slide.detail)
                    .textStyle(.bodyLG)
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.stackLg)
            Spacer()
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(onDone: {})
}
