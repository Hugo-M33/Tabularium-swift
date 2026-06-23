//
//  DesignSystem.swift
//  Tabularium
//
//  "Organic Order" — the single source of truth for color, typography,
//  spacing, radii and shared components. Generated from the Stitch design
//  system of the same name. Every screen styles itself through these tokens;
//  no screen should hardcode a hex value, font face or magic radius.
//
//  See docs/design/tabularium-organic-order.md for rationale & token reference.
//

import SwiftUI
import UIKit

// MARK: - Hex color helper

extension Color {
    /// Creates a color from a `RRGGBB` or `#RRGGBB` hex string.
    init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xff) / 255
        let g = Double((value >> 8) & 0xff) / 255
        let b = Double(value & 0xff) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - Palette

/// Semantic colors. Names mirror the design system roles so the mapping from
/// design to code stays one-to-one.
enum Palette {
    // Surfaces — the warm off-white "Organic Order" floor and tonal layers.
    static let surface = Color(hex: "f9faf7")          // app background (Level 0)
    static let surfaceDim = Color(hex: "d9dad7")
    static let surfaceContainerLowest = Color(hex: "ffffff") // cards (Level 1)
    static let surfaceContainerLow = Color(hex: "f3f4f1")
    static let surfaceContainer = Color(hex: "edeeeb")
    static let surfaceContainerHigh = Color(hex: "e7e8e6")
    static let surfaceContainerHighest = Color(hex: "e2e3e0")

    // Content
    static let onSurface = Color(hex: "191c1b")        // primary text
    static let onSurfaceVariant = Color(hex: "404942") // secondary text
    static let outline = Color(hex: "707972")
    static let outlineVariant = Color(hex: "bfc9c0")

    // Primary — Forest Green, used for key actions & progress.
    static let primary = Color(hex: "105637")
    static let onPrimary = Color(hex: "ffffff")
    static let primaryContainer = Color(hex: "2e6f4e")
    static let onPrimaryContainer = Color(hex: "abefc6")

    // Secondary — olive-grey for supporting UI.
    static let secondary = Color(hex: "596058")
    static let secondaryContainer = Color(hex: "dee5d9")
    static let onSecondaryContainer = Color(hex: "5f665e")

    // Tertiary — gold/amber, reserved for premium & folder metaphors.
    static let tertiary = Color(hex: "654600")
    static let gold = Color(hex: "d9a441")             // premium accent
    static let amber = Color(hex: "f5bd58")            // folder/organization accent

    // Error
    static let error = Color(hex: "ba1a1a")
    static let errorContainer = Color(hex: "ffdad6")
    static let onErrorContainer = Color(hex: "93000a")

    /// The "Halo" — a soft green-tinted wash for selected/active containers
    /// and secondary buttons.
    static let halo = Color(hex: "e4f0e9")

    /// Forest-green gradient used on primary buttons & hero marks.
    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [primaryContainer, primary],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Spacing (8pt base grid)

enum Spacing {
    static let base: CGFloat = 8
    static let stackSm: CGFloat = 4
    static let gutter: CGFloat = 12
    static let stackMd: CGFloat = 16
    static let marginMain: CGFloat = 20   // standard screen side margin
    static let stackLg: CGFloat = 32
}

// MARK: - Corner radii

enum Radius {
    static let sm: CGFloat = 8
    static let chip: CGFloat = 12
    static let control: CGFloat = 16
    static let button: CGFloat = 18   // chunky, tactile buttons
    static let card: CGFloat = 28     // "squircle" main cards
    static let full: CGFloat = 9999
}

// MARK: - Typography

/// The Plus Jakarta Sans type scale. Each role maps to a face + size +
/// tracking + line height, scaling with Dynamic Type relative to a base style.
enum TextRole {
    case display      // 34 / 700
    case headlineLG   // 28 / 700
    case headlineMD   // 22 / 600
    case bodyLG       // 17 / 400 (iOS body baseline)
    case bodyEmph     // 17 / 600
    case bodySM       // 15 / 400
    case labelCaps    // 12 / 600 (tracked, used uppercase)
    case button       // 17 / 700

    fileprivate var faceName: String {
        switch self {
        case .display, .headlineLG, .button: return "PlusJakartaSans-Bold"
        case .headlineMD, .bodyEmph, .labelCaps: return "PlusJakartaSans-SemiBold"
        case .bodyLG, .bodySM: return "PlusJakartaSans-Regular"
        }
    }

    fileprivate var size: CGFloat {
        switch self {
        case .display: return 34
        case .headlineLG: return 28
        case .headlineMD: return 22
        case .bodyLG, .bodyEmph, .button: return 17
        case .bodySM: return 15
        case .labelCaps: return 12
        }
    }

    fileprivate var relativeTo: Font.TextStyle {
        switch self {
        case .display: return .largeTitle
        case .headlineLG: return .title
        case .headlineMD: return .title2
        case .bodyLG, .bodyEmph, .button: return .body
        case .bodySM: return .subheadline
        case .labelCaps: return .caption
        }
    }

    fileprivate var tracking: CGFloat {
        switch self {
        case .display: return -0.5
        case .headlineLG: return -0.4
        case .headlineMD: return -0.3
        case .bodyLG, .bodyEmph, .button: return -0.2
        case .bodySM: return 0
        case .labelCaps: return 0.5
        }
    }

    /// Extra leading on top of the font's natural line height.
    fileprivate var lineSpacing: CGFloat {
        switch self {
        case .display: return 41 - 34
        case .headlineLG: return 34 - 28
        case .headlineMD: return 28 - 22
        case .bodyLG, .bodyEmph, .button: return 22 - 17
        case .bodySM: return 20 - 15
        case .labelCaps: return 16 - 12
        }
    }

    var font: Font {
        .custom(faceName, size: size, relativeTo: relativeTo)
    }
}

private struct TextStyleModifier: ViewModifier {
    let role: TextRole
    func body(content: Content) -> some View {
        content
            .font(role.font)
            .tracking(role.tracking)
            .lineSpacing(role.lineSpacing)
    }
}

extension View {
    /// Applies a design-system text role (font face, size, tracking, leading).
    func textStyle(_ role: TextRole) -> some View {
        modifier(TextStyleModifier(role: role))
    }
}

extension Font {
    /// Direct access to a role's font, for places that need a `Font` value
    /// (e.g. navigation titles) rather than the full `.textStyle` modifier.
    static func app(_ role: TextRole) -> Font { role.font }
}

// MARK: - Press feedback ("squish")

struct SquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SquishButtonStyle {
    /// Plain button with the design system's tactile squish-on-press feedback.
    static var squish: SquishButtonStyle { SquishButtonStyle() }
}

// MARK: - Primary / secondary buttons

/// Full-width Forest-Green gradient CTA. 18pt corners, white label, squish.
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.button)
            .foregroundStyle(Palette.onPrimary)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 16)
            .padding(.horizontal, Spacing.stackLg)
            .background(Palette.primaryGradient, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
            .shadow(color: Palette.primary.opacity(0.25), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Tinted "Halo" secondary button: soft green background, forest-green label.
struct SecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.button)
            .foregroundStyle(Palette.primary)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 16)
            .padding(.horizontal, Spacing.stackLg)
            .background(Palette.halo, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primaryCTA: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func primaryCTA(fullWidth: Bool) -> PrimaryButtonStyle { PrimaryButtonStyle(fullWidth: fullWidth) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func secondary(fullWidth: Bool) -> SecondaryButtonStyle { SecondaryButtonStyle(fullWidth: fullWidth) }
}

// MARK: - Card & material surfaces

private struct AppCardModifier: ViewModifier {
    var padding: CGFloat = Spacing.stackMd
    var radius: CGFloat = Radius.card
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Palette.surfaceContainerLowest,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Palette.primary.opacity(0.06), radius: 20, y: 4)
    }
}

extension View {
    /// Level-1 white card: squircle corners + subtle forest-green drop shadow.
    func appCard(padding: CGFloat = Spacing.stackMd, radius: CGFloat = Radius.card) -> some View {
        modifier(AppCardModifier(padding: padding, radius: radius))
    }

    /// Level-2 floating surface. **Real Liquid Glass on iOS 26+**, with a
    /// graceful frosted-material fallback below. Use for floating chrome that
    /// hovers over content — counters, nav pills, control clusters.
    @ViewBuilder
    func liquidGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: Palette.onSurface.opacity(0.12), radius: 12, y: 4)
        }
    }

    /// Frosted "glass pill" for floating nav, filters and overlays.
    func glassPill(radius: CGFloat = Radius.full) -> some View {
        liquidGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// A circular glass control (e.g. floating photo actions).
    func glassCircle(diameter: CGFloat) -> some View {
        frame(width: diameter, height: diameter)
            .liquidGlass(in: Circle(), interactive: true)
    }
}

/// Groups several `liquidGlass` elements so they blend/morph together as one
/// Liquid Glass surface on iOS 26+ (no-op container below).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = Spacing.stackMd
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Page indicator (onboarding)

/// Consistent paging dots: a forest-green pill marks the active page,
/// muted dots mark the rest.
struct PageIndicator: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: Spacing.base) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Palette.primary : Palette.outlineVariant)
                    .frame(width: i == index ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: index)
            }
        }
    }
}

// MARK: - Global UIKit appearance

/// Applies Plus Jakarta Sans + Organic Order colors to UIKit-backed chrome
/// (navigation bars, tab bars) that SwiftUI styling can't reach directly.
/// Call once at app launch.
enum AppAppearance {
    static func configure() {
        func font(_ name: String, _ size: CGFloat, fallback: UIFont.Weight) -> UIFont {
            UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: fallback)
        }
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: font("PlusJakartaSans-SemiBold", 17, fallback: .semibold),
            .foregroundColor: UIColor(Palette.onSurface),
        ]
        let largeAttrs: [NSAttributedString.Key: Any] = [
            .font: font("PlusJakartaSans-Bold", 32, fallback: .bold),
            .foregroundColor: UIColor(Palette.onSurface),
        ]

        // Standard (content scrolled under the bar): a translucent material the
        // system promotes to Liquid Glass on iOS 26 — keep the brand fonts but
        // DON'T force an opaque fill, otherwise we'd suppress the glass.
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.shadowColor = .clear
        standard.titleTextAttributes = titleAttrs
        standard.largeTitleTextAttributes = largeAttrs

        // Scroll edge (at rest): transparent so large titles sit cleanly on the
        // warm surface.
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.titleTextAttributes = titleAttrs
        edge.largeTitleTextAttributes = largeAttrs

        UINavigationBar.appearance().standardAppearance = standard
        UINavigationBar.appearance().scrollEdgeAppearance = edge
        UINavigationBar.appearance().compactAppearance = standard
        UINavigationBar.appearance().tintColor = UIColor(Palette.primary)

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

// MARK: - Section header (grouped lists)

struct SectionHeader: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }
    var body: some View {
        Text(title)
            .textStyle(.labelCaps)
            .foregroundStyle(Palette.onSurfaceVariant)
            .textCase(.uppercase)
    }
}
