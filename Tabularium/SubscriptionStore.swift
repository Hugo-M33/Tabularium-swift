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

    @Published private(set) var product: Product?
    /// Droit réel (entitlement StoreKit).
    @Published private(set) var entitled = false
    @Published private(set) var purchaseInProgress = false

    #if DEBUG
    /// 🛠️ DEV : force le premium pour tester (persisté). Compilé uniquement en
    /// build Debug → impossible à activer dans une app distribuée.
    @Published var debugForcePremium = UserDefaults.standard.bool(forKey: "debug.forcePremium") {
        didSet { UserDefaults.standard.set(debugForcePremium, forKey: "debug.forcePremium") }
    }
    #endif

    /// Premium effectif = abonnement actif (+ override de dev en build Debug).
    var isUnlimited: Bool {
        #if DEBUG
        return entitled || debugForcePremium
        #else
        return entitled
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
