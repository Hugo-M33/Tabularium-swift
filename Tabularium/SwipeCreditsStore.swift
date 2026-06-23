import Combine
import SwiftUI

/// Gère le quota quotidien de swipes.
/// - 100 swipes par jour, remis à zéro à minuit (heure locale).
/// - Une pub récompensée redonne 100 swipes.
/// - L'abonnement actif débloque l'illimité (vérifié via SubscriptionStore).
///
/// Anti-triche (côté client, garde-fous proportionnés) :
/// - On ne recrédite QUE si le jour courant est strictement postérieur au plus
///   grand jour déjà observé. Reculer l'horloge ne redonne donc pas de swipes.
/// - On mémorise aussi un horodatage de référence : si l'horloge système recule
///   nettement, on considère qu'on est toujours le même jour (pas de reset).
/// Note : aucune protection client n'est inviolable. La vraie barrière contre la
/// fraude à enjeu (abonnement) est la vérification serveur — voir le backend.
@MainActor
final class SwipeCreditsStore: ObservableObject {

    static let dailyLimit = 100

    @Published private(set) var remaining: Int = dailyLimit

    private let defaults = UserDefaults.standard
    private enum Key {
        static let remaining = "swipe.remaining"
        /// Plus grand index de jour jamais observé (anti retour en arrière).
        static let maxDaySeen = "swipe.maxDaySeen"
        /// Dernier horodatage de référence enregistré (anti horloge reculée).
        static let lastSeenTimestamp = "swipe.lastSeenTimestamp"
    }

    init() {
        rolloverIfNeeded()
    }

    /// Prochaine réinitialisation du quota : minuit local à venir.
    var nextReset: Date {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        return cal.date(byAdding: .day, value: 1, to: startToday)
            ?? startToday.addingTimeInterval(86_400)
    }

    /// Jour courant (jours depuis 1970) en heure locale.
    private var currentDay: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return Int(start.timeIntervalSince1970 / 86_400)
    }

    /// Réinitialise le quota uniquement si on a réellement avancé dans le temps.
    func rolloverIfNeeded() {
        let now = Date().timeIntervalSince1970
        let today = currentDay
        let storedMax = defaults.object(forKey: Key.maxDaySeen) as? Int
        let lastSeen = defaults.object(forKey: Key.lastSeenTimestamp) as? Double ?? now

        // Détection d'horloge qui recule : si l'heure système est nettement
        // antérieure au dernier passage (tolérance 60 s pour les micro-ajustements),
        // on ne fait confiance ni au "jour" ni à un éventuel reset.
        let clockWentBackwards = now < lastSeen - 60

        // Premier lancement.
        guard let maxDaySeen = storedMax else {
            defaults.set(today, forKey: Key.maxDaySeen)
            defaults.set(now, forKey: Key.lastSeenTimestamp)
            defaults.set(Self.dailyLimit, forKey: Key.remaining)
            remaining = Self.dailyLimit
            return
        }

        if today > maxDaySeen && !clockWentBackwards {
            // Vrai nouveau jour : on recrédite.
            defaults.set(today, forKey: Key.maxDaySeen)
            defaults.set(Self.dailyLimit, forKey: Key.remaining)
            remaining = Self.dailyLimit
        } else if maxDaySeen - today > 2 {
            // maxDaySeen a manifestement été poussé dans le futur (date avancée
            // puis remise à l'heure). On resynchronise sur le jour réel pour ne pas
            // bloquer indéfiniment un utilisateur honnête, sans recréditer ici.
            // On resynchronise aussi l'horodatage de référence, sinon il resterait
            // bloqué dans le futur et fausserait la détection les jours suivants.
            defaults.set(today, forKey: Key.maxDaySeen)
            defaults.set(now, forKey: Key.lastSeenTimestamp)
            remaining = defaults.object(forKey: Key.remaining) as? Int ?? Self.dailyLimit
            return
        } else {
            // Même jour, ou horloge manipulée : on conserve le solde courant.
            remaining = defaults.object(forKey: Key.remaining) as? Int ?? Self.dailyLimit
        }

        // On n'avance l'horodatage de référence que vers le futur, jamais vers le passé.
        if now > lastSeen {
            defaults.set(now, forKey: Key.lastSeenTimestamp)
        }
    }

    /// Peut-on swiper ? (illimité si abonné)
    func canSwipe(isUnlimited: Bool) -> Bool {
        if isUnlimited { return true }
        rolloverIfNeeded()
        return remaining > 0
    }

    /// Consomme un swipe. Ne fait rien si illimité.
    func consume(isUnlimited: Bool) {
        guard !isUnlimited else { return }
        rolloverIfNeeded()
        remaining = max(0, remaining - 1)
        defaults.set(remaining, forKey: Key.remaining)
    }

    /// Rend un swipe consommé lors d'un retour en arrière (annulation).
    /// Ne fait rien si illimité. Plafonné au même seuil que la pub récompensée.
    func refund(isUnlimited: Bool) {
        guard !isUnlimited else { return }
        rolloverIfNeeded()
        remaining = min(Self.dailyLimit * 10, remaining + 1)
        defaults.set(remaining, forKey: Key.remaining)
    }

    /// Crédit accordé après une pub récompensée vérifiée.
    func grantAdReward() {
        rolloverIfNeeded()
        remaining = min(Self.dailyLimit * 10, remaining + Self.dailyLimit)
        defaults.set(remaining, forKey: Key.remaining)
    }
}
