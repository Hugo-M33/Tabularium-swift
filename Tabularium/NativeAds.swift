import Combine
import GoogleMobileAds
import SwiftUI
import UIKit

/// Charge et conserve les pubs natives AdMob affichées dans le flux / les cartes
/// (un emplacement toutes les N photos pour les comptes non premium).
///
/// Une pub native est chargée **par emplacement** (`slot` = index de la pub dans
/// la session). Chaque pub n'est donc affichée qu'à un seul endroit, conforme
/// aux règles AdMob (pas de réutilisation d'une même `NativeAd`).
///
/// L'identifiant du bloc d'annonces est centralisé dans `AdConfig` (ID de test
/// en Debug, ID réel en release).
@MainActor
final class NativeAdStore: NSObject, ObservableObject {

    static let adUnitID = AdConfig.nativeAdUnitID

    /// Pubs chargées, indexées par emplacement.
    @Published private(set) var ads: [Int: NativeAd] = [:]

    /// Présentateur des pages de destination (clics). Renseigné par l'écran.
    var rootViewController: UIViewController?

    // L'`AdLoader` doit être retenu pendant le chargement.
    private var loaders: [ObjectIdentifier: AdLoader] = [:]
    private var slotByLoader: [ObjectIdentifier: Int] = [:]
    private var inFlight: Set<Int> = []

    func ad(for slot: Int) -> NativeAd? { ads[slot] }

    /// Lance le chargement de la pub pour cet emplacement si nécessaire.
    func loadIfNeeded(for slot: Int) {
        guard ads[slot] == nil, !inFlight.contains(slot) else { return }
        inFlight.insert(slot)

        let loader = AdLoader(
            adUnitID: Self.adUnitID,
            rootViewController: rootViewController,
            adTypes: [.native],
            options: nil
        )
        loader.delegate = self

        let id = ObjectIdentifier(loader)
        loaders[id] = loader
        slotByLoader[id] = slot

        loader.load(Request())
    }

    private func finish(_ loader: AdLoader) {
        let id = ObjectIdentifier(loader)
        if let slot = slotByLoader[id] { inFlight.remove(slot) }
        loaders[id] = nil
        slotByLoader[id] = nil
    }
}

extension NativeAdStore: NativeAdLoaderDelegate {
    // Les callbacks de l'AdLoader sont délivrés sur le main thread.
    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        MainActor.assumeIsolated {
            if let slot = slotByLoader[ObjectIdentifier(adLoader)] {
                ads[slot] = nativeAd
            }
            finish(adLoader)
        }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: any Error) {
        MainActor.assumeIsolated {
            finish(adLoader)
        }
    }
}

// MARK: - Emplacement SwiftUI

/// Emplacement de pub dans le flux / les cartes. Affiche un placeholder pendant
/// le chargement puis la vraie pub native une fois reçue.
struct NativeAdSlot: View {
    @EnvironmentObject private var store: NativeAdStore
    let slot: Int
    /// `true` pour le mode cartes (coins arrondis + ombre), `false` pour le flux.
    var card: Bool = false

    var body: some View {
        Group {
            if let ad = store.ad(for: slot) {
                NativeAdContainer(nativeAd: ad, card: card)
                    .modifier(AdSlotChrome(card: card))
            } else {
                NativeAdPlaceholder(card: card)
            }
        }
        .onAppear {
            if store.rootViewController == nil {
                store.rootViewController = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .first(where: \.isKeyWindow)?.rootViewController
            }
            store.loadIfNeeded(for: slot)
        }
    }
}

// MARK: - Rendu UIKit de la pub native

/// Enrobe un `NativeAdView` AdMob dans SwiftUI.
struct NativeAdContainer: UIViewRepresentable {
    let nativeAd: NativeAd
    /// `true` : mode cartes (coins arrondis + clipping). `false` : flux plein écran.
    var card: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()
        let c = context.coordinator

        // Fond dégradé : assure le contraste du texte blanc (sinon blanc sur gris).
        let background = GradientView()
        background.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(background)

        if card {
            adView.layer.cornerRadius = 28
            adView.layer.cornerCurve = .continuous
            adView.clipsToBounds = true
        }

        c.icon.translatesAutoresizingMaskIntoConstraints = false
        c.icon.layer.cornerRadius = 10
        c.icon.clipsToBounds = true
        c.icon.contentMode = .scaleAspectFill

        c.headline.font = .preferredFont(forTextStyle: .headline)
        c.headline.numberOfLines = 2
        c.headline.textColor = .white

        c.advertiser.font = .preferredFont(forTextStyle: .caption1)
        c.advertiser.textColor = UIColor.white.withAlphaComponent(0.85)
        c.advertiser.numberOfLines = 1

        c.badge.text = NSLocalizedString("ad.sponsored", comment: "Ad attribution badge")
        c.badge.font = .systemFont(ofSize: 11, weight: .bold)
        c.badge.textColor = .white
        c.badge.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        c.badge.layer.cornerRadius = 5
        c.badge.clipsToBounds = true
        c.badge.textAlignment = .center
        c.badge.setContentHuggingPriority(.required, for: .horizontal)
        c.badge.setContentCompressionResistancePriority(.required, for: .horizontal)

        let titleStack = UIStackView(arrangedSubviews: [c.headline, c.advertiser])
        titleStack.axis = .vertical
        titleStack.spacing = 2

        let header = UIStackView(arrangedSubviews: [c.icon, titleStack, c.badge])
        header.axis = .horizontal
        header.spacing = 10
        header.alignment = .center

        c.body.font = .preferredFont(forTextStyle: .subheadline)
        c.body.textColor = UIColor.white.withAlphaComponent(0.9)
        c.body.numberOfLines = 3

        // CTA en UIButton.Configuration (API moderne, remplace contentEdgeInsets).
        var ctaConfig = UIButton.Configuration.filled()
        ctaConfig.baseBackgroundColor = .white
        ctaConfig.baseForegroundColor = .systemIndigo
        ctaConfig.cornerStyle = .fixed
        ctaConfig.background.cornerRadius = 14
        ctaConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        ctaConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var attrs = attrs
            attrs.font = .systemFont(ofSize: 16, weight: .semibold)
            return attrs
        }
        c.cta.configuration = ctaConfig
        c.cta.setContentHuggingPriority(.required, for: .vertical)
        // Le SDK gère le clic du CTA : on désactive l'interaction manuelle.
        c.cta.isUserInteractionEnabled = false

        let main = UIStackView(arrangedSubviews: [header, c.media, c.body, c.cta])
        main.axis = .vertical
        main.spacing = 12
        main.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(main)

        let mediaAspect = c.media.heightAnchor.constraint(equalTo: c.media.widthAnchor, multiplier: 0.75)
        mediaAspect.priority = .defaultHigh
        c.mediaAspect = mediaAspect

        let pad: CGFloat = card ? 18 : 24
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
            background.topAnchor.constraint(equalTo: adView.topAnchor),
            background.bottomAnchor.constraint(equalTo: adView.bottomAnchor),

            c.icon.widthAnchor.constraint(equalToConstant: 48),
            c.icon.heightAnchor.constraint(equalToConstant: 48),

            main.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: pad),
            main.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -pad),
            main.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
            main.topAnchor.constraint(greaterThanOrEqualTo: adView.topAnchor, constant: pad),
            main.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor, constant: -pad),
            mediaAspect,
        ])

        // Outlets AdMob (le SDK suit ces vues pour les impressions / clics).
        adView.headlineView = c.headline
        adView.iconView = c.icon
        adView.advertiserView = c.advertiser
        adView.bodyView = c.body
        adView.callToActionView = c.cta
        adView.mediaView = c.media

        return adView
    }

    func updateUIView(_ adView: NativeAdView, context: Context) {
        let c = context.coordinator

        c.headline.text = nativeAd.headline

        c.advertiser.text = nativeAd.advertiser
        c.advertiser.isHidden = nativeAd.advertiser == nil

        c.icon.image = nativeAd.icon?.image
        c.icon.isHidden = nativeAd.icon == nil

        c.body.text = nativeAd.body
        c.body.isHidden = nativeAd.body == nil

        c.cta.setTitle(nativeAd.callToAction, for: .normal)
        c.cta.isHidden = nativeAd.callToAction == nil

        c.media.mediaContent = nativeAd.mediaContent
        if nativeAd.mediaContent.aspectRatio > 0 {
            c.mediaAspect?.isActive = false
            let ratio = 1.0 / nativeAd.mediaContent.aspectRatio
            let updated = c.media.heightAnchor.constraint(equalTo: c.media.widthAnchor, multiplier: ratio)
            updated.priority = .defaultHigh
            updated.isActive = true
            c.mediaAspect = updated
        }

        // Associe la pub à la vue : déclenche le suivi d'impression. On évite de
        // réassocier la même pub à chaque update SwiftUI (ré-enregistrements
        // inutiles, source potentielle d'instabilité côté SDK).
        if adView.nativeAd !== nativeAd {
            adView.nativeAd = nativeAd
        }
    }

    final class Coordinator {
        let icon = UIImageView()
        let headline = UILabel()
        let advertiser = UILabel()
        let badge = PaddingLabel()
        let body = UILabel()
        let cta = UIButton(type: .system)
        let media = MediaView()
        var mediaAspect: NSLayoutConstraint?
    }
}

// MARK: - Placeholder (état de chargement)

/// Affiché pendant le chargement d'une pub native (ou si elle échoue).
struct NativeAdPlaceholder: View {
    var card: Bool = false

    var body: some View {
        ZStack {
            Palette.primaryGradient
            VStack(spacing: 12) {
                Text("ad.sponsored")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: Capsule())
                Image(systemName: "megaphone.fill")
                    .font(.system(size: card ? 56 : 48))
                    .foregroundStyle(.white)
                Text("ad.placeholder")
                    .multilineTextAlignment(.center)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding()
        }
        .modifier(AdSlotShape(card: card))
    }
}

/// Forme du placeholder SwiftUI : carte arrondie (cartes) ou plein écran (flux).
private struct AdSlotShape: ViewModifier {
    let card: Bool
    func body(content: Content) -> some View {
        if card {
            content
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
        } else {
            content.ignoresSafeArea()
        }
    }
}

/// Habillage du `NativeAdContainer` (UIKit) : la vue gère déjà ses coins arrondis
/// et son clipping, on n'ajoute donc que l'ombre (cartes) ou le plein écran (flux).
private struct AdSlotChrome: ViewModifier {
    let card: Bool
    func body(content: Content) -> some View {
        if card {
            content.shadow(color: .black.opacity(0.18), radius: 24, y: 12)
        } else {
            content.ignoresSafeArea()
        }
    }
}

// MARK: - Vues UIKit utilitaires

/// Fond dégradé indigo → violet (se redimensionne automatiquement avec la vue).
private final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.colors = [UIColor(Palette.primaryContainer).cgColor,
                           UIColor(Palette.primary).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Label avec marges internes (pour le badge « Sponsorisé »).
final class PaddingLabel: UILabel {
    var insets = UIEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }
}
