import Combine
import StoreKit

/// Gère l'abonnement « illimité » via StoreKit 2.
///
/// ⚙️ À CONFIGURER dans App Store Connect :
/// - Crée un produit d'abonnement auto-renouvelable au prix de 3 €/mois.
/// - Renseigne son identifiant ci-dessous dans `productID`.
/// - Pour tester en local : ajoute un fichier `.storekit` (Configuration StoreKit)
///   dans Xcode et coche-le dans le schéma de run.
@MainActor
final class SubscriptionStore: ObservableObject {

    /// 🔑 Remplace par ton identifiant produit App Store Connect.
    static let productID = "com.tonentreprise.tabularium.unlimited.monthly"

    /// 🎟️ Code de test interne pour débloquer le premium en TestFlight (sans
    /// vrai achat). N'a AUCUN effet en build App Store production (voir
    /// `allowsTestPromo`). Change-le pour ce que tu veux.
    static let testPromoCode = "TABU-VIP"

    private static let promoUnlockedKey = "promo.unlocked"

    @Published private(set) var product: Product?
    /// Droit réel (entitlement StoreKit).
    @Published private(set) var entitled = false
    @Published private(set) var purchaseInProgress = false
    /// Premium débloqué via le code de test interne (persisté). Ne compte que
    /// si `allowsTestPromo` est vrai → inerte en production.
    @Published private(set) var promoUnlocked = UserDefaults.standard.bool(forKey: SubscriptionStore.promoUnlockedKey)

    #if DEBUG
    /// 🛠️ DEV : force le premium pour tester (persisté). Compilé uniquement en
    /// build Debug → impossible à activer dans une app distribuée.
    @Published var debugForcePremium = UserDefaults.standard.bool(forKey: "debug.forcePremium") {
        didSet { UserDefaults.standard.set(debugForcePremium, forKey: "debug.forcePremium") }
    }
    #endif

    /// Le code de test n'est honoré qu'en build Debug ou en TestFlight (reçu
    /// « sandbox »). En App Store production il est totalement inerte, donc
    /// aucun risque de premium gratuit pour les vrais utilisateurs.
    static var allowsTestPromo: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    /// Premium effectif = abonnement actif (+ code de test en Debug/TestFlight,
    /// + override de dev en build Debug).
    var isUnlimited: Bool {
        if entitled { return true }
        if promoUnlocked && Self.allowsTestPromo { return true }
        #if DEBUG
        if debugForcePremium { return true }
        #endif
        return false
    }

    /// Résultat de la saisie d'un code de test interne.
    enum RedeemResult { case success, wrongCode, notAvailable }

    /// Valide un code de test interne et débloque le premium si correct.
    /// Sans effet hors Debug/TestFlight (`allowsTestPromo`).
    func redeemTestCode(_ raw: String) -> RedeemResult {
        guard Self.allowsTestPromo else { return .notAvailable }
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code == Self.testPromoCode.uppercased() else { return .wrongCode }
        promoUnlocked = true
        UserDefaults.standard.set(true, forKey: Self.promoUnlockedKey)
        return .success
    }

    /// Repasse en version gratuite pour le test : annule le code de test (et,
    /// en build Debug, l'override de dev). Sans effet sur un vrai abonnement
    /// StoreKit (`entitled`), qui ne peut être révoqué que par Apple.
    func lockPremiumForTesting() {
        promoUnlocked = false
        UserDefaults.standard.set(false, forKey: Self.promoUnlockedKey)
        #if DEBUG
        debugForcePremium = false
        #endif
    }

    private var updatesTask: Task<Void, Never>?

    init() {
        // Écoute les transactions (renouvellements, achats sur autre appareil…).
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            print("StoreKit: échec chargement produits — \(error)")
        }
    }

    /// Prix formaté pour l'UI (ex. « 3,00 € »), avec repli.
    var displayPrice: String { product?.displayPrice ?? "3 €" }

    func purchase() async {
        guard let product else { return }
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            print("StoreKit: achat échoué — \(error)")
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    /// Vérifie les droits actuels (appelé au lancement).
    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                active = true
            }
        }
        entitled = active
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        if transaction.productID == Self.productID {
            entitled = transaction.revocationDate == nil
        }
        await transaction.finish()
    }
}
