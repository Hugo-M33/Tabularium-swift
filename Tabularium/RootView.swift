import SwiftUI

struct RootView: View {
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var showOnboarding = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            HomeScreen()
                .tint(Palette.primary)
                // « Organic Order » est un thème clair : on le verrouille pour que
                // la palette et les matériaux s'affichent comme prévu.
                .preferredColorScheme(.light)
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView { didOnboard = true; showOnboarding = false }
                }

            // Splash par-dessus tout au lancement ; l'onboarding (1er lancement)
            // n'apparaît qu'une fois le splash effacé.
            if showSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
                    if !didOnboard { showOnboarding = true }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(SwipeCreditsStore())
        .environmentObject(SubscriptionStore())
        .environmentObject(PhotoLibrary())
        .environmentObject(SortingSession())
        .environmentObject(GestureSettings())
        .environmentObject(ReclaimedSpaceStore())
}
