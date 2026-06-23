import SwiftUI

/// Écran de lancement animé, affiché par-dessus l'app au démarrage.
///
/// Couche « visible » du démarrage : un *launch screen* natif (Info.plist
/// `UILaunchScreen` → couleur `AccentColor`, le vert de marque) couvre déjà
/// l'instant zéro sans flash blanc ; ce splash SwiftUI prend le relais avec le
/// mot-symbole animé, puis s'efface en fondu (`onFinished`) après une durée
/// minimale — laissant apparaître l'accueil (ou l'onboarding).
struct SplashView: View {
    /// Appelé quand le splash a terminé son temps d'affichage minimal.
    var onFinished: () -> Void

    /// Durée d'affichage minimale (le temps que le mot-symbole respire).
    private let minimumDisplay: Duration = .seconds(1.6)

    @State private var appeared = false

    var body: some View {
        ZStack {
            Palette.primary.ignoresSafeArea()

            // Mot-symbole : « TABULARIUM » blanc, capitales espacées.
            Text(verbatim: "TABULARIUM")
                .font(.custom("PlusJakartaSans-Bold", size: 30))
                .tracking(8)
                .foregroundStyle(Palette.onPrimary)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.94)

            // Indicateur de chargement discret, calé en bas.
            VStack {
                Spacer()
                LoadingBar()
                    .frame(width: 48, height: 3)
                    .opacity(appeared ? 1 : 0)
                    .padding(.bottom, 48)
            }
        }
        .task {
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
            try? await Task.sleep(for: minimumDisplay)
            onFinished()
        }
    }
}

/// Fin trait de chargement indéterminé : un segment lumineux glisse en boucle
/// dans une piste translucide.
private struct LoadingBar: View {
    @State private var sliding = false

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Palette.onPrimary.opacity(0.25))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Palette.onPrimary.opacity(0.85))
                        .frame(width: geo.size.width * 0.45)
                        .offset(x: sliding ? geo.size.width * 0.55 : 0)
                }
                .clipShape(Capsule())
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                sliding = true
            }
        }
    }
}

#Preview {
    SplashView(onFinished: {})
}
