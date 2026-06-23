import SwiftUI

struct RootView: View {
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var showOnboarding = false

    var body: some View {
        HomeScreen()
            .tint(Palette.primary)
            // « Organic Order » est un thème clair : on le verrouille pour que
            // la palette et les matériaux s'affichent comme prévu.
            .preferredColorScheme(.light)
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView { didOnboard = true; showOnboarding = false }
            }
            .onAppear { if !didOnboard { showOnboarding = true } }
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
