import StoreKit
import SwiftUI

/// Menu utilisateur : abonnement, réinitialisation de l'index, et (premium)
/// personnalisation des dossiers raccourcis + des gestes. Plus un interrupteur
/// de dev pour forcer le premium.
struct SettingsScreen: View {
    @EnvironmentObject private var subscription: SubscriptionStore
    @EnvironmentObject private var session: SortingSession
    @EnvironmentObject private var gestures: GestureSettings
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var consent: ConsentManager
    @Environment(\.dismiss) private var dismiss

    @State private var showPaywall = false
    @State private var confirmReset = false
    @State private var showOnboarding = false
    @State private var showOfferCode = false
    @State private var testCodeInput = ""
    @State private var testCodeFeedback: TestCodeFeedback?

    private var isUnlimited: Bool { subscription.isUnlimited }

    private enum TestCodeFeedback { case success, wrongCode }

    var body: some View {
        NavigationStack {
            Form {
                subscriptionSection

                if !isUnlimited {
                    promoSection
                }

                if isUnlimited {
                    shortcutsSection
                    gesturesSection
                }

                if SubscriptionStore.allowsTestPromo && isUnlimited && !subscription.entitled {
                    testRevertSection
                }

                sortingSection
                helpSection
                if consent.isPrivacyOptionsRequired { privacySection }
                #if DEBUG
                devSection
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(Palette.surface)
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.close") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .offerCodeRedemption(isPresented: $showOfferCode) { result in
                if case .failure(let error) = result {
                    print("StoreKit: rédemption offer code échouée — \(error)")
                }
                Task { await subscription.refreshEntitlements() }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView { showOnboarding = false }
            }
            .alert("settings.reset.title", isPresented: $confirmReset) {
                Button("settings.reset.confirm", role: .destructive) { session.resetSorted() }
                Button("common.cancel", role: .cancel) { }
            } message: {
                Text("settings.reset.message")
            }
        }
    }

    // MARK: - Sections

    private var subscriptionSection: some View {
        Section("settings.subscription") {
            Label(isUnlimited ? "status.unlimited" : "settings.free",
                  systemImage: isUnlimited ? "infinity" : "person.crop.circle")
                .foregroundStyle(isUnlimited ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))

            if !isUnlimited {
                Button("settings.gounlimited") { showPaywall = true }
            }
            if subscription.entitled {
                Button("settings.manage") { Task { await manageSubscriptions() } }
            }
            Button("paywall.restore") { Task { await subscription.restore() } }
        }
    }

    /// Codes promo : feuille officielle Apple (Offer Codes) + champ de code de
    /// test interne, ce dernier visible seulement en Debug/TestFlight.
    private var promoSection: some View {
        Section {
            Button("settings.offercode") { showOfferCode = true }

            if SubscriptionStore.allowsTestPromo {
                HStack {
                    TextField("settings.testcode.placeholder", text: $testCodeInput)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("settings.testcode.validate") { redeemTestCode() }
                        .disabled(testCodeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let testCodeFeedback {
                    switch testCodeFeedback {
                    case .success:
                        Label("settings.testcode.success", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .wrongCode:
                        Label("settings.testcode.wrong", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
        } header: {
            Text("settings.promo")
        } footer: {
            if SubscriptionStore.allowsTestPromo {
                Text("settings.testcode.footer")
            }
        }
    }

    private func redeemTestCode() {
        switch subscription.redeemTestCode(testCodeInput) {
        case .success:
            testCodeFeedback = .success
            testCodeInput = ""
        case .wrongCode, .notAvailable:
            testCodeFeedback = .wrongCode
        }
    }

    /// Test uniquement (Debug/TestFlight) : repasse en version gratuite pour
    /// revérifier le parcours non-payant. Masqué en production.
    private var testRevertSection: some View {
        Section {
            Button("settings.testrevert", role: .destructive) {
                subscription.lockPremiumForTesting()
                testCodeFeedback = nil
            }
        } footer: {
            Text("settings.testrevert.footer")
        }
    }

    private var shortcutsSection: some View {
        Section {
            NavigationLink {
                ShortcutPickerView()
            } label: {
                HStack {
                    Label("settings.shortcuts", systemImage: "folder")
                    Spacer()
                    Text(verbatim: "\(gestures.shortcuts.count)/\(GestureSettings.maxShortcuts)")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(gestures.shortcuts) { s in
                Label(s.title, systemImage: "folder.fill")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("settings.shortcuts.header")
        } footer: {
            Text("settings.shortcuts.footer")
        }
    }

    private var gesturesSection: some View {
        Section {
            actionPicker("settings.gesture.cardsright", selection: $gestures.cardsRight)
            actionPicker("settings.gesture.cardsleft", selection: $gestures.cardsLeft)
            actionPicker("settings.gesture.feedright", selection: $gestures.feedRight)
            actionPicker("settings.gesture.feedleft", selection: $gestures.feedLeft)
        } header: {
            Text("settings.gestures")
        } footer: {
            Text("settings.gestures.footer")
        }
    }

    private func actionPicker(_ title: LocalizedStringKey,
                              selection: Binding<GestureSettings.Action>) -> some View {
        Picker(title, selection: selection) {
            ForEach(actionOptions(), id: \.self) { action in
                Text(actionLabel(action)).tag(action)
            }
        }
    }

    private func actionOptions() -> [GestureSettings.Action] {
        var opts: [GestureSettings.Action] = [.keep, .delete, .none]
        opts += gestures.shortcuts.map { .folder($0.id) }
        return opts
    }

    private func actionLabel(_ a: GestureSettings.Action) -> String {
        switch a {
        case .keep: return NSLocalizedString("action.keep", comment: "")
        case .delete: return NSLocalizedString("action.delete", comment: "")
        case .none: return NSLocalizedString("action.none", comment: "")
        case .folder(let id): return gestures.title(forFolder: id)
            ?? NSLocalizedString("action.folder", comment: "")
        }
    }

    private var sortingSection: some View {
        Section {
            LabeledContent("settings.sortedcount", value: "\(session.sortedCount)")
            Button("settings.reset", role: .destructive) { confirmReset = true }
        } header: {
            Text("settings.sorting")
        } footer: {
            Text("settings.sorting.footer")
        }
    }

    private var helpSection: some View {
        Section {
            Button {
                showOnboarding = true
            } label: {
                Label("settings.replayintro", systemImage: "questionmark.circle")
            }
        } header: {
            Text("settings.help")
        }
    }

    /// Réouverture du formulaire de consentement publicitaire (RGPD).
    /// Affichée seulement quand Google l'exige (≈ utilisateurs UE). Si l'utilisateur
    /// accorde son consentement ici, on démarre le SDK pub à la volée.
    private var privacySection: some View {
        Section {
            Button("settings.privacyoptions") {
                Task {
                    await consent.presentPrivacyOptionsForm()
                    consent.startAdsIfAllowed()
                }
            }
        } header: {
            Text("settings.privacy")
        }
    }

    #if DEBUG
    private var devSection: some View {
        Section {
            Toggle("settings.forcepremium", isOn: $subscription.debugForcePremium)
        } header: {
            Text("settings.dev")
        }
    }
    #endif

    private func manageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
    }
}

/// Sélection des dossiers raccourcis (max 3) parmi les albums utilisateur.
private struct ShortcutPickerView: View {
    @EnvironmentObject private var gestures: GestureSettings
    @EnvironmentObject private var library: PhotoLibrary
    @State private var albums: [PhotoLibrary.Album] = []

    private var selectedIDs: Set<String> { Set(gestures.shortcuts.map(\.id)) }

    var body: some View {
        List {
            Section {
                ForEach(albums) { album in
                    Button { toggle(album) } label: {
                        HStack {
                            Label(album.title, systemImage: "folder")
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedIDs.contains(album.id) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .disabled(!selectedIDs.contains(album.id)
                              && gestures.shortcuts.count >= GestureSettings.maxShortcuts)
                }
            } footer: {
                if albums.isEmpty { Text("settings.shortcuts.noalbums") }
                else { Text("settings.shortcuts.max") }
            }
        }
        .navigationTitle("settings.shortcuts")
        .navigationBarTitleDisplayMode(.inline)
        .task { albums = library.fetchUserAlbums() }
    }

    private func toggle(_ album: PhotoLibrary.Album) {
        if let idx = gestures.shortcuts.firstIndex(where: { $0.id == album.id }) {
            gestures.shortcuts.remove(at: idx)
        } else if gestures.shortcuts.count < GestureSettings.maxShortcuts {
            gestures.shortcuts.append(FolderShortcut(id: album.id, title: album.title))
        }
        gestures.sanitizeActions()
    }
}
